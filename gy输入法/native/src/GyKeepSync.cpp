#include "GyKeepSync.h"

#include "ClipboardHistory.h"
#include "GyAccountAuth.h"

#include <windows.h>
#include <wincrypt.h>
#include <winhttp.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdint>
#include <ctime>
#include <cwctype>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

namespace gy::keep_sync {
namespace {

constexpr wchar_t kKeepHost[] = L"keep.gyenbox.com";
constexpr DWORD kKeepPort = INTERNET_DEFAULT_HTTPS_PORT;
constexpr DWORD kMaxResponseBytes = 48 * 1024 * 1024;
constexpr DWORD kPollMilliseconds = 750;

std::atomic_bool g_running{false};
std::atomic_bool g_enabled{true};
std::atomic_bool g_instant_paste{true};
HANDLE g_wake_event = nullptr;
std::thread g_worker;
std::mutex g_token_mutex;
std::wstring g_access_token;
std::int64_t g_access_expiry = 0;
std::mutex g_remote_head_mutex;
// The most recent Keep HEAD that this device has already handled.  Handling a
// local ACK means "leave the user's current clipboard alone"; handling a
// remote HEAD means "write it to the system clipboard".  Tracking both with
// one ID avoids turning a successful local ACK into a lossy clipboard rewrite.
std::wstring g_last_handled_head_id;

struct HttpResponse {
  DWORD status = 0;
  std::string body;
};

struct SyncPage {
  std::vector<clipboard_history::RemoteChange> changes;
  unsigned long long cursor = 0;
  bool has_more = false;
  bool snapshot = false;
};

void Wipe(std::wstring* value) {
  if (!value) return;
  std::fill(value->begin(), value->end(), L'\0');
  value->clear();
}

void Wipe(std::string* value) {
  if (!value) return;
  std::fill(value->begin(), value->end(), '\0');
  value->clear();
}

bool IsUnhandledHead(const clipboard_history::Entry& entry) {
  std::lock_guard<std::mutex> lock(g_remote_head_mutex);
  return g_last_handled_head_id != entry.id;
}

void RememberHandledHead(const clipboard_history::Entry& entry) {
  std::lock_guard<std::mutex> lock(g_remote_head_mutex);
  g_last_handled_head_id = entry.id;
}

void ForgetHandledHead() {
  std::lock_guard<std::mutex> lock(g_remote_head_mutex);
  Wipe(&g_last_handled_head_id);
}

std::string ToUtf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                                         nullptr, 0, nullptr, nullptr);
  if (length <= 0) return {};
  std::string value(static_cast<size_t>(length), '\0');
  if (!WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), value.data(),
                           length, nullptr, nullptr)) {
    Wipe(&value);
    return {};
  }
  return value;
}

bool FromUtf8(const std::string& text, std::wstring* output) {
  if (!output) return false;
  output->clear();
  if (text.empty()) return true;
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                                         static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) return false;
  output->assign(static_cast<size_t>(length), L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()),
                           output->data(), length)) {
    Wipe(output);
    return false;
  }
  return true;
}

bool Base64Encode(const std::string& bytes, std::string* output) {
  if (!output) return false;
  output->clear();
  if (bytes.empty()) return true;
  DWORD required = 0;
  if (!CryptBinaryToStringA(reinterpret_cast<const BYTE*>(bytes.data()), static_cast<DWORD>(bytes.size()),
                            CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr, &required)) return false;
  output->assign(required, '\0');
  if (!CryptBinaryToStringA(reinterpret_cast<const BYTE*>(bytes.data()), static_cast<DWORD>(bytes.size()),
                            CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, output->data(), &required)) {
    Wipe(output);
    return false;
  }
  if (!output->empty() && output->back() == '\0') output->pop_back();
  return true;
}

bool Base64Decode(const std::string& encoded, std::string* output) {
  if (!output || encoded.empty()) return false;
  output->clear();
  DWORD required = 0;
  if (!CryptStringToBinaryA(encoded.data(), static_cast<DWORD>(encoded.size()), CRYPT_STRING_BASE64,
                            nullptr, &required, nullptr, nullptr)) return false;
  output->assign(required, '\0');
  if (!CryptStringToBinaryA(encoded.data(), static_cast<DWORD>(encoded.size()), CRYPT_STRING_BASE64,
                            reinterpret_cast<BYTE*>(output->data()), &required, nullptr, nullptr)) {
    Wipe(output);
    return false;
  }
  output->resize(required);
  return true;
}

bool IsSafeSourceId(const std::wstring& value) {
  if (value.size() < 8 || value.size() > 128) return false;
  for (const wchar_t ch : value) {
    if (!(std::iswalnum(ch) || ch == L'_' || ch == L'-')) return false;
  }
  return true;
}

bool IsSafeBearerToken(const std::wstring& value) {
  return !value.empty() && value.find_first_of(L"\r\n") == std::wstring::npos;
}

bool Request(const wchar_t* method, const wchar_t* path, const std::wstring& access_token,
             const std::string& body, const std::wstring& extra_headers, HttpResponse* response) {
  if (!method || !path || !response || !IsSafeBearerToken(access_token)) return false;
  response->status = 0;
  Wipe(&response->body);

  HINTERNET session = WinHttpOpen(L"GYInput/0.10", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                 WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) return false;
  WinHttpSetTimeouts(session, 5000, 5000, 10000, 15000);
  HINTERNET connect = WinHttpConnect(session, kKeepHost, kKeepPort, 0);
  if (!connect) { WinHttpCloseHandle(session); return false; }
  HINTERNET request = WinHttpOpenRequest(connect, method, path, nullptr, WINHTTP_NO_REFERER,
                                         WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
  if (!request) {
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    return false;
  }
  DWORD redirect_policy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
  WinHttpSetOption(request, WINHTTP_OPTION_REDIRECT_POLICY, &redirect_policy, sizeof(redirect_policy));
  std::wstring headers = L"Accept: application/json\r\nAuthorization: Bearer " + access_token + L"\r\n" + extra_headers;
  if (!body.empty() && extra_headers.find(L"Content-Type:") == std::wstring::npos) {
    headers += L"Content-Type: application/json; charset=utf-8\r\n";
  }
  const BOOL sent = WinHttpSendRequest(request, headers.c_str(), static_cast<DWORD>(headers.size()),
                                       body.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char*>(body.data()),
                                       static_cast<DWORD>(body.size()), static_cast<DWORD>(body.size()), 0);
  bool ok = sent != FALSE && WinHttpReceiveResponse(request, nullptr) != FALSE;
  if (ok) {
    DWORD size = sizeof(response->status);
    ok = WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &response->status, &size,
                             WINHTTP_NO_HEADER_INDEX) != FALSE;
  }
  while (ok) {
    DWORD available = 0;
    if (!WinHttpQueryDataAvailable(request, &available)) { ok = false; break; }
    if (available == 0) break;
    if (available > kMaxResponseBytes || response->body.size() > kMaxResponseBytes - available) {
      ok = false;
      break;
    }
    const size_t offset = response->body.size();
    response->body.resize(offset + available);
    DWORD read = 0;
    if (!WinHttpReadData(request, response->body.data() + offset, available, &read)) { ok = false; break; }
    response->body.resize(offset + read);
    if (read == 0) break;
  }
  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connect);
  WinHttpCloseHandle(session);
  if (!ok) Wipe(&response->body);
  return ok;
}

bool JsonPayloadField(const std::string& body, std::string* payload) {
  if (!payload) return false;
  payload->clear();
  const size_t key = body.find("\"payload\"");
  if (key == std::string::npos) return false;
  const size_t colon = body.find(':', key + 9);
  if (colon == std::string::npos) return false;
  const size_t first = body.find('"', colon + 1);
  if (first == std::string::npos) return false;
  const size_t last = body.find('"', first + 1);
  if (last == std::string::npos) return false;
  const std::string value = body.substr(first + 1, last - first - 1);
  for (const unsigned char ch : value) {
    if (!(std::isalnum(ch) || ch == '+' || ch == '/' || ch == '=')) return false;
  }
  *payload = value;
  return true;
}

bool JsonStringField(const std::string& body, const char* field, std::string* output) {
  if (!field || !output) return false;
  output->clear();
  const std::string key = "\"" + std::string(field) + "\"";
  const size_t key_at = body.find(key);
  if (key_at == std::string::npos) return false;
  const size_t colon = body.find(':', key_at + key.size());
  if (colon == std::string::npos) return false;
  const size_t first = body.find('"', colon + 1);
  if (first == std::string::npos) return false;
  const size_t last = body.find('"', first + 1);
  if (last == std::string::npos) return false;
  *output = body.substr(first + 1, last - first - 1);
  return true;
}

bool JsonBoolField(const std::string& body, const char* field, bool* output) {
  if (!field || !output) return false;
  const std::string key = "\"" + std::string(field) + "\"";
  const size_t key_at = body.find(key);
  if (key_at == std::string::npos) return false;
  const size_t colon = body.find(':', key_at + key.size());
  if (colon == std::string::npos) return false;
  size_t value = colon + 1;
  while (value < body.size() && std::isspace(static_cast<unsigned char>(body[value]))) ++value;
  if (body.compare(value, 4, "true") == 0) { *output = true; return true; }
  if (body.compare(value, 5, "false") == 0) { *output = false; return true; }
  return false;
}

bool ParseSequence(const std::string& value, unsigned long long* output) {
  if (!output || value.empty() || value.size() > 20 ||
      !std::all_of(value.begin(), value.end(), [](unsigned char ch) { return std::isdigit(ch) != 0; })) return false;
  try { *output = std::stoull(value); } catch (...) { return false; }
  return true;
}

std::wstring CursorPath() {
  const std::wstring history = clipboard_history::HistoryPath();
  const size_t slash = history.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring{} : history.substr(0, slash + 1) + L"keep-sync-cursor.txt";
}

bool LoadCursor(unsigned long long* cursor) {
  if (!cursor) return false;
  const std::wstring path = CursorPath();
  if (path.empty()) return false;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  char buffer[32]{};
  DWORD read = 0;
  const bool ok = ReadFile(file, buffer, sizeof(buffer) - 1, &read, nullptr) != FALSE;
  CloseHandle(file);
  if (!ok || read == 0) return false;
  std::string value(buffer, read);
  return ParseSequence(value, cursor);
}

bool SaveCursor(unsigned long long cursor) {
  const std::wstring path = CursorPath();
  if (path.empty()) return false;
  const std::string value = std::to_string(cursor);
  const std::wstring temporary = path + L".tmp";
  HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool wrote = WriteFile(file, value.data(), static_cast<DWORD>(value.size()), &written, nullptr) != FALSE &&
                     written == value.size();
  CloseHandle(file);
  if (!wrote) { DeleteFileW(temporary.c_str()); return false; }
  return MoveFileExW(temporary.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}

bool IsSha256(const std::string& value) {
  if (value.size() != 64) return false;
  return std::all_of(value.begin(), value.end(), [](unsigned char ch) {
    return std::isdigit(ch) || (ch >= 'a' && ch <= 'f');
  });
}

bool Sha256(const std::string& bytes, std::string* output) {
  if (!output || bytes.empty()) return false;
  output->clear();
  HCRYPTPROV provider = 0;
  HCRYPTHASH hash = 0;
  BYTE digest[32]{};
  DWORD digest_size = sizeof(digest);
  const bool ok = CryptAcquireContextW(&provider, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) &&
                  CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash) &&
                  CryptHashData(hash, reinterpret_cast<const BYTE*>(bytes.data()), static_cast<DWORD>(bytes.size()), 0) &&
                  CryptGetHashParam(hash, HP_HASHVAL, digest, &digest_size, 0) && digest_size == sizeof(digest);
  if (hash) CryptDestroyHash(hash);
  if (provider) CryptReleaseContext(provider, 0);
  if (!ok) return false;
  static constexpr char kHex[] = "0123456789abcdef";
  output->reserve(sizeof(digest) * 2);
  for (BYTE value : digest) { output->push_back(kHex[value >> 4]); output->push_back(kHex[value & 0x0f]); }
  return true;
}

bool ParseWireEntries(const std::string& payload,
                      std::vector<clipboard_history::RemoteChange>* changes) {
  if (!changes) return false;
  changes->clear();
  if (payload.empty()) return true;
  std::string wire;
  if (!Base64Decode(payload, &wire)) return false;
  size_t begin = 0;
  while (begin <= wire.size()) {
    const size_t end = wire.find('\n', begin);
    const std::string line = wire.substr(begin, end == std::string::npos ? std::string::npos : end - begin);
    begin = end == std::string::npos ? wire.size() + 1 : end + 1;
    if (line.empty()) continue;
    std::vector<std::string> fields;
    size_t field_begin = 0;
    while (field_begin <= line.size()) {
      const size_t field_end = line.find('\t', field_begin);
      fields.push_back(line.substr(field_begin, field_end == std::string::npos ? std::string::npos : field_end - field_begin));
      if (field_end == std::string::npos) break;
      field_begin = field_end + 1;
    }
    if (fields.empty() || (fields[0] != "T" && fields[0] != "I" && fields[0] != "D")) {
      Wipe(&wire);
      return false;
    }
    const bool deleted = fields[0] == "D";
    if (deleted && fields.size() != 3) { Wipe(&wire); return false; }
    const bool image = fields[0] == "I";
    if (!deleted && ((!image && fields.size() != 5) || (image && fields.size() != 7))) {
      Wipe(&wire);
      return false;
    }
    unsigned long long sequence = 0;
    if (!ParseSequence(fields[1], &sequence) || sequence == 0) { Wipe(&wire); return false; }
    std::wstring id;
    if (!FromUtf8(fields[2], &id) || !IsSafeSourceId(id)) { Wipe(&wire); return false; }
    if (deleted) {
      clipboard_history::Entry entry;
      entry.id = std::move(id);
      entry.sync_sequence = sequence;
      changes->push_back({clipboard_history::RemoteChangeKind::Delete, std::move(entry)});
      if (changes->size() > 64) { Wipe(&wire); return false; }
      continue;
    }
    unsigned long long timestamp_ms = 0;
    try { timestamp_ms = std::stoull(fields[3]); } catch (...) { Wipe(&wire); return false; }
    if (timestamp_ms < 946684800000ULL) { Wipe(&wire); return false; }
    if (image) {
      unsigned long long size = 0;
      try { size = std::stoull(fields[5]); } catch (...) { Wipe(&wire); return false; }
      if (fields[4] != "image/png" || size == 0 || size > clipboard_history::kMaxImageBytes || !IsSha256(fields[6])) {
        Wipe(&wire);
        return false;
      }
      std::wstring sha;
      if (!FromUtf8(fields[6], &sha)) { Wipe(&wire); return false; }
      clipboard_history::Entry entry{id, timestamp_ms / 1000ULL, L"[图片]", false,
                                     clipboard_history::EntryKind::PngImage, sha, sequence};
      changes->push_back({clipboard_history::RemoteChangeKind::Add, std::move(entry)});
    } else {
      std::string text_utf8;
      std::wstring text;
      if (!Base64Decode(fields[4], &text_utf8) || !FromUtf8(text_utf8, &text) || text.empty()) {
        Wipe(&text_utf8);
        Wipe(&wire);
        return false;
      }
      Wipe(&text_utf8);
      clipboard_history::Entry entry{id, timestamp_ms / 1000ULL, text, false,
                                     clipboard_history::EntryKind::Text, L"", sequence};
      changes->push_back({clipboard_history::RemoteChangeKind::Add, std::move(entry)});
    }
    if (changes->size() > 64) { Wipe(&wire); return false; }
  }
  Wipe(&wire);
  return true;
}

bool FetchPage(const std::wstring& access_token, unsigned long long cursor, bool snapshot, SyncPage* page) {
  if (!page) return false;
  page->changes.clear();
  page->cursor = cursor;
  page->has_more = false;
  page->snapshot = snapshot;
  HttpResponse response;
  const std::wstring path = snapshot ? L"/api/clipboard/sync?snapshot=1" :
      L"/api/clipboard/sync?cursor=" + std::to_wstring(cursor);
  if (!Request(L"GET", path.c_str(), access_token, "", L"", &response)) return false;
  if (response.status != 200) { Wipe(&response.body); return false; }
  std::string payload;
  std::string cursor_text;
  unsigned long long next_cursor = 0;
  bool has_more = false;
  const bool parsed = JsonPayloadField(response.body, &payload) &&
      JsonStringField(response.body, "cursor", &cursor_text) && ParseSequence(cursor_text, &next_cursor) &&
      JsonBoolField(response.body, "hasMore", &has_more) &&
      ParseWireEntries(payload, &page->changes);
  if (parsed) {
    page->cursor = next_cursor;
    page->has_more = has_more;
  }
  Wipe(&payload);
  Wipe(&cursor_text);
  Wipe(&response.body);
  return parsed;
}

bool DownloadImage(const std::wstring& access_token, const clipboard_history::Entry& entry) {
  if (entry.kind != clipboard_history::EntryKind::PngImage || !IsSafeSourceId(entry.id)) return false;
  HttpResponse response;
  const std::wstring path = L"/api/clipboard/images/" + entry.id;
  if (!Request(L"GET", path.c_str(), access_token, "", L"Accept: image/png\r\n", &response)) return false;
  if (response.status != 200 || response.body.empty() || response.body.size() > clipboard_history::kMaxImageBytes) {
    Wipe(&response.body);
    return false;
  }
  std::string actual_hash;
  const bool valid = Sha256(response.body, &actual_hash) && ToUtf8(entry.image_sha256) == actual_hash &&
                     clipboard_history::SaveImagePngFromKeep(entry, response.body);
  Wipe(&actual_hash);
  Wipe(&response.body);
  return valid;
}

bool EnsureRemoteImages(const std::wstring& access_token,
                        const std::vector<clipboard_history::RemoteChange>& changes) {
  for (const auto& change : changes) {
    if (change.kind != clipboard_history::RemoteChangeKind::Add) continue;
    const auto& entry = change.entry;
    if (entry.kind != clipboard_history::EntryKind::PngImage) continue;
    std::string local;
    if (clipboard_history::ReadImagePng(entry, &local)) {
      std::string actual_hash;
      const bool matches = Sha256(local, &actual_hash) && ToUtf8(entry.image_sha256) == actual_hash;
      Wipe(&local);
      Wipe(&actual_hash);
      if (matches) continue;
    }
    if (!DownloadImage(access_token, entry)) return false;
  }
  return true;
}

std::vector<clipboard_history::Entry> SnapshotEntries(
    const std::vector<clipboard_history::RemoteChange>& changes) {
  std::vector<clipboard_history::Entry> entries;
  entries.reserve(changes.size());
  for (const auto& change : changes) {
    if (change.kind == clipboard_history::RemoteChangeKind::Add) entries.push_back(change.entry);
  }
  return entries;
}

bool ParseAcknowledgement(const std::string& body, unsigned long long* sequence) {
  std::string value;
  const bool ok = JsonStringField(body, "sequence", &value) && ParseSequence(value, sequence) && *sequence != 0;
  Wipe(&value);
  return ok;
}

bool PostTextEntry(const std::wstring& access_token, const clipboard_history::Entry& entry,
                   unsigned long long* sequence) {
  if (!sequence) return false;
  *sequence = 0;
  if (!IsSafeSourceId(entry.id)) return false;
  std::string text = ToUtf8(entry.text);
  std::string text_base64;
  if (text.empty() || !Base64Encode(text, &text_base64)) { Wipe(&text); return false; }
  Wipe(&text);
  const unsigned long long captured_ms = entry.unix_time * 1000ULL;
  std::string id = ToUtf8(entry.id);
  if (id.empty()) { Wipe(&text_base64); return false; }
  std::string body = "{\"id\":\"" + id + "\",\"textBase64\":\"" + text_base64 +
                     "\",\"capturedAt\":" + std::to_string(captured_ms) + "}";
  Wipe(&id);
  Wipe(&text_base64);
  HttpResponse response;
  const bool requested = Request(L"POST", L"/api/clipboard/sync", access_token, body, L"", &response);
  Wipe(&body);
  if (!requested || (response.status != 200 && response.status != 201)) { Wipe(&response.body); return false; }
  const bool acknowledged = ParseAcknowledgement(response.body, sequence);
  Wipe(&response.body);
  return acknowledged;
}

bool PostImageEntry(const std::wstring& access_token, const clipboard_history::Entry& entry,
                    unsigned long long* sequence) {
  if (!sequence) return false;
  *sequence = 0;
  if (!IsSafeSourceId(entry.id) || entry.kind != clipboard_history::EntryKind::PngImage) return false;
  std::string png;
  std::string sha256;
  if (!clipboard_history::ReadImagePng(entry, &png) || !Sha256(png, &sha256)) { Wipe(&png); return false; }
  const std::wstring path = L"/api/clipboard/images/" + entry.id;
  std::wstring wide_sha256;
  if (!FromUtf8(sha256, &wide_sha256)) { Wipe(&png); Wipe(&sha256); return false; }
  const std::wstring headers = L"Content-Type: image/png\r\nX-GY-Captured-At: " +
      std::to_wstring(entry.unix_time * 1000ULL) + L"\r\nX-GY-SHA256: " + wide_sha256 + L"\r\n";
  HttpResponse response;
  const std::wstring ack_path = path + L"?format=ack-v3";
  const bool requested = Request(L"PUT", ack_path.c_str(), access_token, png, headers, &response);
  Wipe(&png);
  Wipe(&sha256);
  if (!requested || (response.status != 200 && response.status != 201)) { Wipe(&response.body); return false; }
  const bool acknowledged = ParseAcknowledgement(response.body, sequence);
  Wipe(&response.body);
  return acknowledged;
}

bool GetAccessToken(std::wstring* access_token) {
  if (!access_token) return false;
  access_token->clear();
  const std::int64_t now = static_cast<std::int64_t>(std::time(nullptr));
  {
    std::lock_guard<std::mutex> lock(g_token_mutex);
    if (!g_access_token.empty() && g_access_expiry > now + 30) {
      *access_token = g_access_token;
      return true;
    }
  }
  account_auth::StoredSession stored;
  if (!account_auth::LoadStoredSession(&stored)) return false;
  account_auth::Result restored = account_auth::Restore(stored.refresh_token);
  Wipe(&stored.refresh_token);
  if (restored.status != account_auth::Status::Success) {
    if (restored.status == account_auth::Status::Unauthorized) account_auth::ClearStoredSession();
    Wipe(&restored.session.access_token);
    Wipe(&restored.session.refresh_token);
    return false;
  }
  account_auth::StoredSession updated{restored.session.email, restored.session.refresh_token};
  const bool saved = account_auth::SaveStoredSession(updated);
  Wipe(&updated.refresh_token);
  if (!saved) {
    Wipe(&restored.session.access_token);
    Wipe(&restored.session.refresh_token);
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(g_token_mutex);
    Wipe(&g_access_token);
    g_access_token = restored.session.access_token;
    g_access_expiry = restored.session.expires_at;
    *access_token = g_access_token;
  }
  Wipe(&restored.session.access_token);
  Wipe(&restored.session.refresh_token);
  return true;
}

void Synchronize() {
  if (!g_enabled.load()) return;
  if (!clipboard_history::MigratePendingHistoryToOutbox()) return;
  std::wstring access_token;
  if (!GetAccessToken(&access_token)) return;

  // The outbox is durable and ordered oldest first. Each successful request
  // returns Keep's global sequence, so no follow-up 20-item reload is needed.
  for (const auto& entry : clipboard_history::ReadPendingOutbox()) {
    unsigned long long sequence = 0;
    const bool uploaded = entry.kind == clipboard_history::EntryKind::PngImage
        ? PostImageEntry(access_token, entry, &sequence)
        : PostTextEntry(access_token, entry, &sequence);
    if (!uploaded || !clipboard_history::AcknowledgeUploaded(entry.id, sequence)) {
      Wipe(&access_token);
      return;
    }
    // Keep has now accepted a local capture.  Do not round-trip it through
    // SetClipboardData: doing so can discard rich formats that accompanied the
    // original copy (for example HTML, file data, or an application's custom
    // clipboard format).  A different device becoming HEAD still compares as
    // new below and is applied normally.
    RememberHandledHead(entry);
  }

  unsigned long long cursor = 0;
  bool snapshot = !LoadCursor(&cursor);
  bool refresh_snapshot = false;
  for (int page_count = 0; page_count < 8; ++page_count) {
    SyncPage page;
    if (!FetchPage(access_token, cursor, snapshot, &page) ||
        !EnsureRemoteImages(access_token, page.changes) ||
        (page.snapshot ? !clipboard_history::ReplaceConfirmedSnapshot(SnapshotEntries(page.changes))
                       : (!page.changes.empty() && !clipboard_history::ApplyConfirmedChanges(page.changes))) ||
        !SaveCursor(page.cursor)) {
      Wipe(&access_token);
      return;
    }
    if (!page.snapshot) {
      for (const auto& change : page.changes) {
        if (change.kind == clipboard_history::RemoteChangeKind::Delete) {
          refresh_snapshot = true;
          break;
        }
      }
    }
    if (!page.has_more || page.cursor == cursor) break;
    cursor = page.cursor;
    snapshot = false;
  }

  // A DELETE can expose the 21st confirmed item. Fetch one authoritative
  // HEAD(20) snapshot to fill that slot; copies and normal ADD events never
  // take this path.
  if (refresh_snapshot) {
    SyncPage page;
    if (!FetchPage(access_token, 0, true, &page) || !EnsureRemoteImages(access_token, page.changes)) {
      Wipe(&access_token);
      return;
    }
    if (!clipboard_history::ReplaceConfirmedSnapshot(SnapshotEntries(page.changes)) || !SaveCursor(page.cursor)) {
      Wipe(&access_token);
      return;
    }
  }

  const std::vector<clipboard_history::Entry> projection = clipboard_history::ReadAll();
  if (g_instant_paste.load() && !projection.empty() && !projection.front().pending_upload &&
      IsUnhandledHead(projection.front())) {
    const bool applied = projection.front().kind == clipboard_history::EntryKind::PngImage
        ? clipboard_history::SetSystemClipboardImageFromKeep(projection.front())
        : clipboard_history::SetSystemClipboardTextFromKeep(projection.front().text);
    if (applied) {
      RememberHandledHead(projection.front());
    }
  }
  Wipe(&access_token);
}

void WorkerMain() {
  while (g_running.load()) {
    Synchronize();
    if (!g_wake_event) break;
    WaitForSingleObject(g_wake_event, kPollMilliseconds);
    ResetEvent(g_wake_event);
  }
}

void Wake() {
  if (g_wake_event) SetEvent(g_wake_event);
}

}  // namespace

void Start() {
  bool expected = false;
  if (!g_running.compare_exchange_strong(expected, true)) return;
  g_wake_event = CreateEventW(nullptr, TRUE, TRUE, nullptr);
  if (!g_wake_event) { g_running.store(false); return; }
  g_worker = std::thread(WorkerMain);
}

void Stop() {
  if (!g_running.exchange(false)) return;
  Wake();
  if (g_worker.joinable()) g_worker.join();
  if (g_wake_event) { CloseHandle(g_wake_event); g_wake_event = nullptr; }
  std::lock_guard<std::mutex> lock(g_token_mutex);
  Wipe(&g_access_token);
  g_access_expiry = 0;
  ForgetHandledHead();
}

void NotifyLocalClipboardChanged() {
  Wake();
}

void NotifyAccountChanged() {
  {
    std::lock_guard<std::mutex> lock(g_token_mutex);
    Wipe(&g_access_token);
    g_access_expiry = 0;
  }
  Wake();
}

void SetEnabled(bool enabled) {
  g_enabled.store(enabled);
  Wake();
}

void SetInstantPasteEnabled(bool enabled) {
  g_instant_paste.store(enabled);
  if (enabled) ForgetHandledHead();
  Wake();
}

}  // namespace gy::keep_sync
