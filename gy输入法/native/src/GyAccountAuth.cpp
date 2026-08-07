#include "GyAccountAuth.h"

#include <windows.h>
#include <wincrypt.h>
#include <winhttp.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <limits>
#include <string>
#include <vector>

namespace gy::account_auth {
namespace {

constexpr wchar_t kApiHost[] = L"gsyen-api-776196228503.asia-east1.run.app";
constexpr wchar_t kSessionCookieName[] = L"gsyen_rt";
constexpr wchar_t kSessionFileName[] = L"gsyen-session.dat";
constexpr std::uint32_t kSessionMagic = 0x4E535947;  // "GYSN" in little-endian storage
constexpr std::uint32_t kSessionFormatVersion = 1;
constexpr DWORD kMaxResponseBytes = 64 * 1024;
constexpr DWORD kMaxSessionBytes = 128 * 1024;

struct HttpResponse {
  DWORD status = 0;
  std::string body;
};

void SecureErase(std::wstring* value) {
  if (!value || value->empty()) return;
  SecureZeroMemory(value->data(), value->size() * sizeof(wchar_t));
  value->clear();
}

void SecureErase(std::string* value) {
  if (!value || value->empty()) return;
  SecureZeroMemory(value->data(), value->size());
  value->clear();
}

std::wstring SessionFilePath() {
  DWORD required = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
  if (required == 0 || required > 32768) return {};
  std::vector<wchar_t> root(static_cast<size_t>(required));
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", root.data(), required)) return {};
  const std::wstring directory = std::wstring(root.data()) + L"\\GYInput";
  if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return {};
  return directory + L"\\" + kSessionFileName;
}

bool WriteAll(const std::wstring& path, const std::vector<BYTE>& bytes) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool ok = bytes.size() <= std::numeric_limits<DWORD>::max() &&
      WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) != FALSE &&
      written == bytes.size() && FlushFileBuffers(file) != FALSE;
  CloseHandle(file);
  return ok;
}

bool ReadAll(const std::wstring& path, std::vector<BYTE>* bytes) {
  if (!bytes) return false;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size{};
  const bool valid_size = GetFileSizeEx(file, &size) != FALSE && size.QuadPart > 0 &&
      size.QuadPart <= kMaxSessionBytes;
  if (!valid_size) {
    CloseHandle(file);
    return false;
  }
  bytes->assign(static_cast<size_t>(size.QuadPart), 0);
  DWORD read = 0;
  const bool ok = ReadFile(file, bytes->data(), static_cast<DWORD>(bytes->size()), &read, nullptr) != FALSE &&
      read == bytes->size();
  CloseHandle(file);
  return ok;
}

void AppendUint32(std::vector<BYTE>* bytes, std::uint32_t value) {
  for (int shift = 0; shift < 32; shift += 8) {
    bytes->push_back(static_cast<BYTE>((value >> shift) & 0xFF));
  }
}

bool ReadUint32(const BYTE* bytes, size_t size, size_t* offset, std::uint32_t* value) {
  if (!bytes || !offset || !value || *offset > size || size - *offset < 4) return false;
  *value = static_cast<std::uint32_t>(bytes[*offset]) |
      (static_cast<std::uint32_t>(bytes[*offset + 1]) << 8) |
      (static_cast<std::uint32_t>(bytes[*offset + 2]) << 16) |
      (static_cast<std::uint32_t>(bytes[*offset + 3]) << 24);
  *offset += 4;
  return true;
}

bool WideToUtf8(const std::wstring& input, std::string* output) {
  if (!output) return false;
  if (input.empty()) {
    output->clear();
    return true;
  }
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input.data(),
                                       static_cast<int>(input.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0) return false;
  output->assign(static_cast<size_t>(size), '\0');
  return WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input.data(), static_cast<int>(input.size()),
                             output->data(), size, nullptr, nullptr) == size;
}

bool Utf8ToWide(const std::string& input, std::wstring* output) {
  if (!output) return false;
  if (input.empty()) {
    output->clear();
    return true;
  }
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
                                       static_cast<int>(input.size()), nullptr, 0);
  if (size <= 0) return false;
  output->assign(static_cast<size_t>(size), L'\0');
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), static_cast<int>(input.size()),
                             output->data(), size) == size;
}

bool ParseStoredSession(const BYTE* bytes, size_t size, StoredSession* session) {
  if (!bytes || !session) return false;
  size_t offset = 0;
  std::uint32_t magic = 0, version = 0, email_size = 0, refresh_size = 0;
  if (!ReadUint32(bytes, size, &offset, &magic) || !ReadUint32(bytes, size, &offset, &version) ||
      !ReadUint32(bytes, size, &offset, &email_size) || !ReadUint32(bytes, size, &offset, &refresh_size) ||
      magic != kSessionMagic || version != kSessionFormatVersion || email_size == 0 || refresh_size == 0 ||
      email_size > size - offset || refresh_size > size - offset - email_size) {
    return false;
  }
  const std::string email(reinterpret_cast<const char*>(bytes + offset), email_size);
  offset += email_size;
  const std::string refresh(reinterpret_cast<const char*>(bytes + offset), refresh_size);
  return Utf8ToWide(email, &session->email) && Utf8ToWide(refresh, &session->refresh_token) &&
      !session->email.empty() && !session->refresh_token.empty();
}

std::string JsonEscape(const std::string& input) {
  std::string escaped;
  escaped.reserve(input.size() + 8);
  constexpr char hex[] = "0123456789ABCDEF";
  for (unsigned char character : input) {
    switch (character) {
      case '\\': escaped += "\\\\"; break;
      case '"': escaped += "\\\""; break;
      case '\b': escaped += "\\b"; break;
      case '\f': escaped += "\\f"; break;
      case '\n': escaped += "\\n"; break;
      case '\r': escaped += "\\r"; break;
      case '\t': escaped += "\\t"; break;
      default:
        if (character < 0x20) {
          escaped += "\\u00";
          escaped += hex[(character >> 4) & 0x0F];
          escaped += hex[character & 0x0F];
        } else {
          escaped.push_back(static_cast<char>(character));
        }
    }
  }
  return escaped;
}

int HexValue(char value) {
  if (value >= '0' && value <= '9') return value - '0';
  if (value >= 'a' && value <= 'f') return value - 'a' + 10;
  if (value >= 'A' && value <= 'F') return value - 'A' + 10;
  return -1;
}

void AppendUtf8CodePoint(std::string* output, std::uint32_t code_point) {
  if (code_point <= 0x7F) {
    output->push_back(static_cast<char>(code_point));
  } else if (code_point <= 0x7FF) {
    output->push_back(static_cast<char>(0xC0 | (code_point >> 6)));
    output->push_back(static_cast<char>(0x80 | (code_point & 0x3F)));
  } else {
    output->push_back(static_cast<char>(0xE0 | (code_point >> 12)));
    output->push_back(static_cast<char>(0x80 | ((code_point >> 6) & 0x3F)));
    output->push_back(static_cast<char>(0x80 | (code_point & 0x3F)));
  }
}

bool ParseJsonString(const std::string& input, size_t* cursor, std::string* value) {
  if (!cursor || !value || *cursor >= input.size() || input[*cursor] != '"') return false;
  ++*cursor;
  value->clear();
  while (*cursor < input.size()) {
    const unsigned char character = static_cast<unsigned char>(input[(*cursor)++]);
    if (character == '"') return true;
    if (character < 0x20) return false;
    if (character != '\\') {
      value->push_back(static_cast<char>(character));
      continue;
    }
    if (*cursor >= input.size()) return false;
    const char escape = input[(*cursor)++];
    switch (escape) {
      case '"': value->push_back('"'); break;
      case '\\': value->push_back('\\'); break;
      case '/': value->push_back('/'); break;
      case 'b': value->push_back('\b'); break;
      case 'f': value->push_back('\f'); break;
      case 'n': value->push_back('\n'); break;
      case 'r': value->push_back('\r'); break;
      case 't': value->push_back('\t'); break;
      case 'u': {
        if (*cursor > input.size() - 4) return false;
        std::uint32_t code_point = 0;
        for (int i = 0; i < 4; ++i) {
          const int hex = HexValue(input[*cursor + i]);
          if (hex < 0) return false;
          code_point = (code_point << 4) | static_cast<std::uint32_t>(hex);
        }
        *cursor += 4;
        // API fields used here are identifiers and messages. Reject surrogate
        // pairs rather than emitting malformed UTF-8 for an unexpected field.
        if (code_point >= 0xD800 && code_point <= 0xDFFF) return false;
        AppendUtf8CodePoint(value, code_point);
        break;
      }
      default: return false;
    }
  }
  return false;
}

bool JsonStringField(const std::string& json, const char* field, std::wstring* value) {
  if (!field || !value) return false;
  const std::string quoted_field = std::string("\"") + field + "\"";
  size_t search_from = 0;
  while (true) {
    const size_t key = json.find(quoted_field, search_from);
    if (key == std::string::npos) return false;
    size_t cursor = key + quoted_field.size();
    while (cursor < json.size() && std::isspace(static_cast<unsigned char>(json[cursor]))) ++cursor;
    if (cursor >= json.size() || json[cursor] != ':') {
      search_from = key + quoted_field.size();
      continue;
    }
    ++cursor;
    while (cursor < json.size() && std::isspace(static_cast<unsigned char>(json[cursor]))) ++cursor;
    std::string utf8;
    if (!ParseJsonString(json, &cursor, &utf8)) return false;
    const bool converted = Utf8ToWide(utf8, value);
    SecureErase(&utf8);
    return converted;
  }
}

bool JsonIntegerField(const std::string& json, const char* field, std::int64_t* value) {
  if (!field || !value) return false;
  const std::string quoted_field = std::string("\"") + field + "\"";
  const size_t key = json.find(quoted_field);
  if (key == std::string::npos) return false;
  size_t cursor = key + quoted_field.size();
  while (cursor < json.size() && std::isspace(static_cast<unsigned char>(json[cursor]))) ++cursor;
  if (cursor >= json.size() || json[cursor++] != ':') return false;
  while (cursor < json.size() && std::isspace(static_cast<unsigned char>(json[cursor]))) ++cursor;
  bool negative = false;
  if (cursor < json.size() && json[cursor] == '-') { negative = true; ++cursor; }
  if (cursor >= json.size() || !std::isdigit(static_cast<unsigned char>(json[cursor]))) return false;
  std::int64_t parsed = 0;
  while (cursor < json.size() && std::isdigit(static_cast<unsigned char>(json[cursor]))) {
    const int digit = json[cursor++] - '0';
    if (parsed > (std::numeric_limits<std::int64_t>::max() - digit) / 10) return false;
    parsed = parsed * 10 + digit;
  }
  *value = negative ? -parsed : parsed;
  return true;
}

bool IsSafeCookieValue(const std::wstring& value) {
  return !value.empty() && value.find_first_of(L"\r\n;") == std::wstring::npos;
}

bool Request(const wchar_t* method, const wchar_t* path, const std::wstring& cookie,
             const std::string& body, HttpResponse* response) {
  if (!method || !path || !response || (!cookie.empty() && !IsSafeCookieValue(cookie))) return false;
  HINTERNET session = WinHttpOpen(L"GYInput/0.9", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                 WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) return false;
  WinHttpSetTimeouts(session, 5000, 5000, 10000, 10000);
  DWORD redirect_policy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
  WinHttpSetOption(session, WINHTTP_OPTION_REDIRECT_POLICY, &redirect_policy, sizeof(redirect_policy));
  HINTERNET connection = WinHttpConnect(session, kApiHost, INTERNET_DEFAULT_HTTPS_PORT, 0);
  if (!connection) {
    WinHttpCloseHandle(session);
    return false;
  }
  HINTERNET request = WinHttpOpenRequest(connection, method, path, nullptr, WINHTTP_NO_REFERER,
                                         WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
  if (!request) {
    WinHttpCloseHandle(connection);
    WinHttpCloseHandle(session);
    return false;
  }
  std::wstring headers = L"Accept: application/json\r\n";
  if (!body.empty()) headers += L"Content-Type: application/json; charset=utf-8\r\n";
  if (!cookie.empty()) headers += std::wstring(L"Cookie: ") + kSessionCookieName + L"=" + cookie + L"\r\n";
  const BOOL sent = WinHttpSendRequest(request, headers.c_str(), static_cast<DWORD>(headers.size()),
                                       body.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char*>(body.data()),
                                       static_cast<DWORD>(body.size()), static_cast<DWORD>(body.size()), 0);
  bool ok = sent != FALSE && WinHttpReceiveResponse(request, nullptr) != FALSE;
  DWORD status_size = sizeof(response->status);
  if (ok) ok = WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                                   WINHTTP_HEADER_NAME_BY_INDEX, &response->status, &status_size,
                                   WINHTTP_NO_HEADER_INDEX) != FALSE;
  while (ok) {
    DWORD available = 0;
    if (!WinHttpQueryDataAvailable(request, &available)) {
      ok = false;
      break;
    }
    if (available == 0) break;
    if (available > kMaxResponseBytes || response->body.size() > kMaxResponseBytes - available) {
      ok = false;
      break;
    }
    const size_t previous = response->body.size();
    response->body.resize(previous + available);
    DWORD read = 0;
    if (!WinHttpReadData(request, response->body.data() + previous, available, &read) || read != available) {
      ok = false;
      break;
    }
  }
  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connection);
  WinHttpCloseHandle(session);
  return ok;
}

Result ParseSessionResponse(const HttpResponse& response) {
  Result result;
  if (response.status == 401) {
    result.status = Status::Unauthorized;
    return result;
  }
  if (response.status < 200 || response.status >= 300) {
    result.status = Status::ServerError;
    return result;
  }
  if (!JsonStringField(response.body, "access_token", &result.session.access_token) ||
      !JsonStringField(response.body, "refresh_token", &result.session.refresh_token) ||
      !JsonStringField(response.body, "email", &result.session.email) ||
      !JsonIntegerField(response.body, "expires_at", &result.session.expires_at) ||
      result.session.access_token.empty() || result.session.refresh_token.empty() || result.session.email.empty()) {
    SecureErase(&result.session.access_token);
    SecureErase(&result.session.refresh_token);
    result.session.email.clear();
    result.status = Status::InvalidResponse;
    return result;
  }
  result.status = Status::Success;
  return result;
}

}  // namespace

Result Login(const std::wstring& email, const std::wstring& password) {
  Result result;
  std::string email_utf8;
  std::string password_utf8;
  if (email.empty() || password.empty() || !WideToUtf8(email, &email_utf8) || !WideToUtf8(password, &password_utf8)) {
    result.status = Status::InvalidResponse;
    return result;
  }
  std::string body = "{\"email\":\"" + JsonEscape(email_utf8) + "\",\"password\":\"" +
      JsonEscape(password_utf8) + "\"}";
  SecureErase(&email_utf8);
  SecureErase(&password_utf8);
  HttpResponse response;
  if (!Request(L"POST", L"/api/auth/login", L"", body, &response)) {
    SecureErase(&body);
    result.status = Status::NetworkError;
    return result;
  }
  SecureErase(&body);
  result = ParseSessionResponse(response);
  SecureErase(&response.body);
  return result;
}

Result Restore(const std::wstring& refresh_token) {
  Result result;
  HttpResponse response;
  if (!Request(L"GET", L"/api/auth/me", refresh_token, "", &response)) {
    result.status = Status::NetworkError;
    return result;
  }
  result = ParseSessionResponse(response);
  SecureErase(&response.body);
  return result;
}

void Logout(const std::wstring& refresh_token) {
  if (!IsSafeCookieValue(refresh_token)) return;
  HttpResponse response;
  Request(L"POST", L"/api/auth/logout", refresh_token, "", &response);
  SecureErase(&response.body);
}

bool SaveStoredSession(const StoredSession& session) {
  if (session.email.empty() || session.refresh_token.empty()) return false;
  std::string email;
  std::string refresh;
  if (!WideToUtf8(session.email, &email) || !WideToUtf8(session.refresh_token, &refresh) ||
      email.size() > 16 * 1024 || refresh.size() > 32 * 1024) {
    SecureErase(&email);
    SecureErase(&refresh);
    return false;
  }
  std::vector<BYTE> plaintext;
  plaintext.reserve(16 + email.size() + refresh.size());
  AppendUint32(&plaintext, kSessionMagic);
  AppendUint32(&plaintext, kSessionFormatVersion);
  AppendUint32(&plaintext, static_cast<std::uint32_t>(email.size()));
  AppendUint32(&plaintext, static_cast<std::uint32_t>(refresh.size()));
  plaintext.insert(plaintext.end(), reinterpret_cast<const BYTE*>(email.data()),
                   reinterpret_cast<const BYTE*>(email.data()) + email.size());
  plaintext.insert(plaintext.end(), reinterpret_cast<const BYTE*>(refresh.data()),
                   reinterpret_cast<const BYTE*>(refresh.data()) + refresh.size());
  SecureErase(&email);
  SecureErase(&refresh);
  DATA_BLOB input{static_cast<DWORD>(plaintext.size()), plaintext.data()};
  DATA_BLOB encrypted{};
  const bool protected_ok = CryptProtectData(&input, L"GY Input account session", nullptr, nullptr, nullptr,
                                             CRYPTPROTECT_UI_FORBIDDEN, &encrypted) != FALSE;
  SecureZeroMemory(plaintext.data(), plaintext.size());
  if (!protected_ok) return false;
  const std::wstring path = SessionFilePath();
  const std::wstring temporary = path.empty() ? std::wstring{} : path + L".tmp";
  const std::vector<BYTE> protected_bytes(encrypted.pbData, encrypted.pbData + encrypted.cbData);
  SecureZeroMemory(encrypted.pbData, encrypted.cbData);
  LocalFree(encrypted.pbData);
  if (temporary.empty() || !WriteAll(temporary, protected_bytes)) {
    if (!temporary.empty()) DeleteFileW(temporary.c_str());
    return false;
  }
  if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temporary.c_str());
    return false;
  }
  return true;
}

bool LoadStoredSession(StoredSession* session) {
  if (!session) return false;
  session->email.clear();
  SecureErase(&session->refresh_token);
  const std::wstring path = SessionFilePath();
  std::vector<BYTE> encrypted;
  if (path.empty() || !ReadAll(path, &encrypted)) return false;
  DATA_BLOB input{static_cast<DWORD>(encrypted.size()), encrypted.data()};
  DATA_BLOB plaintext{};
  const bool unprotected = CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                                              CRYPTPROTECT_UI_FORBIDDEN, &plaintext) != FALSE;
  SecureZeroMemory(encrypted.data(), encrypted.size());
  if (!unprotected) return false;
  const bool parsed = ParseStoredSession(plaintext.pbData, plaintext.cbData, session);
  SecureZeroMemory(plaintext.pbData, plaintext.cbData);
  LocalFree(plaintext.pbData);
  return parsed;
}

bool ClearStoredSession() {
  const std::wstring path = SessionFilePath();
  if (path.empty()) return false;
  return DeleteFileW(path.c_str()) != FALSE || GetLastError() == ERROR_FILE_NOT_FOUND;
}

}  // namespace gy::account_auth
