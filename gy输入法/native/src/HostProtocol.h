#pragma once

#include <windows.h>

#include <cstdint>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

namespace gy::host {
constexpr wchar_t kPipeName[] = L"\\\\.\\pipe\\GYInput.Host.v1";

inline const std::wstring& HostPipeName() {
#ifdef GY_TESTING
  static const std::wstring name = [] {
    // Test builds may use a temporary isolated endpoint, never the live Host.
    wchar_t buffer[256]{};
    constexpr wchar_t kTestPrefix[] = L"\\\\.\\pipe\\GYInput.Host.test.";
    const DWORD length = GetEnvironmentVariableW(L"GYINPUT_HOST_PIPE", buffer, static_cast<DWORD>(std::size(buffer)));
    if (length && length < std::size(buffer) && std::wstring_view(buffer).rfind(kTestPrefix, 0) == 0) return std::wstring(buffer);
    return std::wstring(kPipeName);
  }();
#else
  static const std::wstring name(kPipeName);
#endif
  return name;
}
constexpr std::uint32_t kMagic = 0x4759494d;  // "GYIM"
// v2 made the input-mode snapshot part of every lookup. v3 additionally makes
// candidate purpose explicit so Chinese conversion, EN completion, and the
// opt-in English correction tool cannot inherit one another's presentation.
// v4 adds a bounded EN-list state that is independent from the Chinese grid.
// The version check deliberately fails closed during a mixed-version hand-off.
constexpr std::uint16_t kProtocolVersion = 4;
constexpr std::uint32_t kMaxPayloadBytes = 256 * 1024;

// The protocol is intentionally small and stable. The DLL only asks the Host
// for engine work and presents UI state; new visual behavior belongs in Host.
enum class MessageType : std::uint16_t {
  Lookup = 1,
  Status = 2,
  Shutdown = 3,
  ShowCandidates = 4,
  HideCandidates = 5,
  ShowMode = 6,
  SelectCandidate = 7,
  LearnCandidate = 8,
  LookupExact = 9,
  UndoLearnCandidate = 10,
  // Candidate clicks use a separate, per-TSF-session pipe.  The client sends
  // this tiny acknowledgement after it has read the result so the server does
  // not disconnect early and discard a successful response.
  AcknowledgeCandidateSelection = 11,
};

#pragma pack(push, 1)
struct Header {
  std::uint32_t magic = kMagic;
  std::uint16_t protocol_version = kProtocolVersion;
  std::uint16_t type = 0;
  std::uint32_t payload_bytes = 0;
};
#pragma pack(pop)

// Status decoding accepts both the current bare version response and the
// reserved structured response. This lets a future Host add health metadata
// without breaking DLLs that are still running during an update.
struct HostStatus {
  std::wstring host_version;
  std::uint32_t protocol_version = kProtocolVersion;
  std::wstring release_version;
};

inline bool MatchesHostIdentity(const HostStatus& status, std::wstring_view expected_version) {
  // An empty expected version is never a wildcard.  Accepting it allowed a
  // DLL retained by a long-running app to consume candidates from whichever
  // older Host happened to own the shared pipe after an incomplete upgrade.
  return !expected_version.empty() && status.host_version == expected_version &&
      status.release_version == expected_version && status.protocol_version == kProtocolVersion;
}

struct LookupRequest {
  std::wstring text;
  unsigned input_mode = 0;  // 0 = simplified, 1 = traditional, 2 = English
  std::uint64_t mode_generation = 0;
};

struct LookupResponse {
  std::vector<std::wstring> candidates;
  unsigned input_mode = 0;
  std::uint64_t mode_generation = 0;
};

inline bool ParseLookupUnsigned(const std::wstring& value, std::uint64_t* parsed) {
  if (!parsed || value.empty()) return false;
  for (const wchar_t character : value) {
    if (character < L'0' || character > L'9') return false;
  }
  size_t consumed = 0;
  try {
    const std::uint64_t result = std::stoull(value, &consumed);
    if (consumed != value.size()) return false;
    *parsed = result;
    return true;
  } catch (...) {
    return false;
  }
}

inline std::wstring EncodeLookupRequest(const LookupRequest& request) {
  std::wstring encoded = L"@mode=" + std::to_wstring(request.input_mode);
  encoded.push_back(L'\0');
  encoded += L"@generation=" + std::to_wstring(request.mode_generation);
  encoded.push_back(L'\0');
  encoded += request.text;
  return encoded;
}

inline bool DecodeLookupRequest(const std::wstring& encoded, LookupRequest* request) {
  if (!request) return false;
  const size_t first = encoded.find(L'\0');
  const size_t second = first == std::wstring::npos ? std::wstring::npos : encoded.find(L'\0', first + 1);
  if (first == std::wstring::npos || second == std::wstring::npos || second + 1 >= encoded.size()) return false;
  const std::wstring mode_field = encoded.substr(0, first);
  const std::wstring generation_field = encoded.substr(first + 1, second - first - 1);
  if (mode_field.rfind(L"@mode=", 0) != 0 || generation_field.rfind(L"@generation=", 0) != 0) return false;
  std::uint64_t mode = 0;
  if (!ParseLookupUnsigned(mode_field.substr(6), &mode) || mode > 2 ||
      !ParseLookupUnsigned(generation_field.substr(12), &request->mode_generation)) return false;
  request->input_mode = static_cast<unsigned>(mode);
  request->text = encoded.substr(second + 1);
  return !request->text.empty() && request->text.find(L'\0') == std::wstring::npos;
}

inline std::wstring EncodeLookupResponse(const LookupResponse& response) {
  std::wstring encoded = L"@mode=" + std::to_wstring(response.input_mode);
  encoded.push_back(L'\0');
  encoded += L"@generation=" + std::to_wstring(response.mode_generation);
  for (const auto& candidate : response.candidates) {
    encoded.push_back(L'\0');
    encoded += candidate;
  }
  return encoded;
}

inline bool DecodeLookupResponse(const std::wstring& encoded, LookupResponse* response) {
  if (!response) return false;
  const size_t first = encoded.find(L'\0');
  const size_t second = first == std::wstring::npos ? std::wstring::npos : encoded.find(L'\0', first + 1);
  const std::wstring mode_field = first == std::wstring::npos ? encoded : encoded.substr(0, first);
  const std::wstring generation_field = first == std::wstring::npos
      ? std::wstring{} : encoded.substr(first + 1, second == std::wstring::npos
          ? std::wstring::npos : second - first - 1);
  if (mode_field.rfind(L"@mode=", 0) != 0 || generation_field.rfind(L"@generation=", 0) != 0) return false;
  std::uint64_t mode = 0;
  if (!ParseLookupUnsigned(mode_field.substr(6), &mode) || mode > 2 ||
      !ParseLookupUnsigned(generation_field.substr(12), &response->mode_generation)) return false;
  response->input_mode = static_cast<unsigned>(mode);
  response->candidates.clear();
  if (second == std::wstring::npos) return true;
  size_t begin = second + 1;
  while (begin < encoded.size()) {
    const size_t end = encoded.find(L'\0', begin);
    const size_t length = (end == std::wstring::npos ? encoded.size() : end) - begin;
    if (length) response->candidates.emplace_back(encoded.substr(begin, length));
    if (end == std::wstring::npos) break;
    begin = end + 1;
  }
  return true;
}

inline bool MatchesLookupSnapshot(const LookupRequest& request, const LookupResponse& response) {
  return request.input_mode == response.input_mode &&
      request.mode_generation == response.mode_generation;
}

inline std::wstring EncodeStatus(const HostStatus& status) {
  return status.host_version + std::wstring(1, L'\0') + std::to_wstring(status.protocol_version) +
      std::wstring(1, L'\0') + status.release_version;
}

inline bool DecodeStatus(const std::wstring& encoded, HostStatus* status) {
  if (!status || encoded.empty()) return false;
  const size_t first = encoded.find(L'\0');
  if (first == std::wstring::npos) {
    status->host_version = encoded;
    status->protocol_version = 1;
    status->release_version.clear();
    return true;
  }
  const size_t second = encoded.find(L'\0', first + 1);
  if (second == std::wstring::npos) return false;
  try {
    status->host_version = encoded.substr(0, first);
    status->protocol_version = static_cast<std::uint32_t>(
        std::stoul(encoded.substr(first + 1, second - first - 1)));
    status->release_version = encoded.substr(second + 1);
  } catch (...) {
    return false;
  }
  return !status->host_version.empty() && status->protocol_version > 0;
}
struct CandidateUiState {
  RECT caret{};
  // Preedit is rendered by TSF in the focused app.  The Host receives this
  // small display-only copy solely to render English inline completion; it is
  // never persisted, learned, or sent across the network.
  std::wstring composition;
  std::vector<std::wstring> candidates;
  // Zero-based candidate indexes that must be painted as a visible correction
  // suggestion.  The committed text remains candidates[index].
  std::vector<unsigned> correction_indices;
  unsigned selected = 0;
  unsigned page_start = 0;
  unsigned input_mode = 0;  // 0 = simplified, 1 = traditional, 2 = English
  // Presentation purpose is independent from input mode: pure EN completion
  // and the explicit spelling-correction tool have different interaction
  // contracts even though both carry English text.
  unsigned candidate_purpose = 0;  // 0 = Chinese conversion, 1 = EN completion, 2 = EN correction
  // Chinese-only presentation state. English candidates never carry grid or
  // paging state across the process boundary.
  bool chinese_grid_open = false;
  // English-only explicit focus/list state. It never enables page navigation
  // and is ignored for Chinese conversion payloads.
  bool english_list_open = false;
  // The passive strip deliberately has no blue selection. An arrow action
  // makes this true, after which the highlighted item and Space semantics are
  // visually aligned.
  bool english_candidate_focus = false;
  std::wstring callback_pipe;
};

inline bool ReadExact(HANDLE handle, void* data, DWORD bytes) {
  auto* cursor = static_cast<unsigned char*>(data);
  while (bytes > 0) {
    DWORD read = 0;
    if (!ReadFile(handle, cursor, bytes, &read, nullptr) || read == 0) return false;
    cursor += read;
    bytes -= read;
  }
  return true;
}

inline bool WriteExact(HANDLE handle, const void* data, DWORD bytes) {
  const auto* cursor = static_cast<const unsigned char*>(data);
  while (bytes > 0) {
    DWORD written = 0;
    if (!WriteFile(handle, cursor, bytes, &written, nullptr) || written == 0) return false;
    cursor += written;
    bytes -= written;
  }
  return true;
}

inline bool ReadMessage(HANDLE handle, MessageType* type, std::wstring* payload) {
  if (!type || !payload) return false;
  Header header{};
  if (!ReadExact(handle, &header, sizeof(header)) || header.magic != kMagic ||
      header.protocol_version != kProtocolVersion || header.payload_bytes > kMaxPayloadBytes ||
      (header.payload_bytes % sizeof(wchar_t)) != 0) return false;
  payload->assign(header.payload_bytes / sizeof(wchar_t), L'\0');
  if (header.payload_bytes && !ReadExact(handle, payload->data(), header.payload_bytes)) return false;
  *type = static_cast<MessageType>(header.type);
  return true;
}

inline bool WriteMessage(HANDLE handle, MessageType type, const std::wstring& payload) {
  const auto byte_count = payload.size() * sizeof(wchar_t);
  if (byte_count > kMaxPayloadBytes) return false;
  Header header{};
  header.type = static_cast<std::uint16_t>(type);
  header.payload_bytes = static_cast<std::uint32_t>(byte_count);
  return WriteExact(handle, &header, sizeof(header)) &&
      (!byte_count || WriteExact(handle, payload.data(), header.payload_bytes));
}

// The TSF DLL is loaded inside every application that accepts text.  A Host
// pipe request therefore needs a single hard deadline: a wedged Host must
// cost one missed candidate refresh, never an indefinitely blocked browser,
// editor, or system input thread.  These helpers are only for client handles
// opened with FILE_FLAG_OVERLAPPED.
inline DWORD RemainingDeadlineMs(ULONGLONG deadline) {
  const ULONGLONG now = GetTickCount64();
  if (now >= deadline) return 0;
  const ULONGLONG remaining = deadline - now;
  return remaining > std::numeric_limits<DWORD>::max()
      ? std::numeric_limits<DWORD>::max()
      : static_cast<DWORD>(remaining);
}

inline bool TransferExactWithDeadline(HANDLE handle, bool write, void* mutable_data,
                                      const void* const_data, DWORD bytes,
                                      ULONGLONG deadline) {
  HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!event) return false;

  auto* read_cursor = static_cast<unsigned char*>(mutable_data);
  const auto* write_cursor = static_cast<const unsigned char*>(const_data);
  bool success = true;
  while (bytes > 0 && success) {
    const DWORD remaining = RemainingDeadlineMs(deadline);
    if (remaining == 0) {
      success = false;
      break;
    }
    OVERLAPPED operation{};
    operation.hEvent = event;
    ResetEvent(event);
    DWORD transferred = 0;
    const BOOL completed = write
        ? WriteFile(handle, write_cursor, bytes, &transferred, &operation)
        : ReadFile(handle, read_cursor, bytes, &transferred, &operation);
    if (!completed) {
      const DWORD start_error = GetLastError();
      if (start_error != ERROR_IO_PENDING) {
        success = false;
        break;
      }
      if (WaitForSingleObject(event, remaining) != WAIT_OBJECT_0 ||
          !GetOverlappedResult(handle, &operation, &transferred, FALSE)) {
        // Cancellation makes the outstanding request complete before its
        // OVERLAPPED storage goes out of scope.  This is a bounded local pipe
        // operation; it is intentionally never retried in a key event.
        CancelIoEx(handle, &operation);
        GetOverlappedResult(handle, &operation, &transferred, TRUE);
        success = false;
        break;
      }
    }
    if (transferred == 0) {
      success = false;
      break;
    }
    if (write) write_cursor += transferred;
    else read_cursor += transferred;
    bytes -= transferred;
  }
  CloseHandle(event);
  return success;
}

inline bool ReadExactWithDeadline(HANDLE handle, void* data, DWORD bytes, ULONGLONG deadline) {
  return TransferExactWithDeadline(handle, false, data, nullptr, bytes, deadline);
}

inline bool WriteExactWithDeadline(HANDLE handle, const void* data, DWORD bytes, ULONGLONG deadline) {
  return TransferExactWithDeadline(handle, true, nullptr, data, bytes, deadline);
}

inline bool ReadMessageWithDeadline(HANDLE handle, MessageType* type, std::wstring* payload,
                                    ULONGLONG deadline) {
  if (!type || !payload) return false;
  Header header{};
  if (!ReadExactWithDeadline(handle, &header, sizeof(header), deadline) || header.magic != kMagic ||
      header.protocol_version != kProtocolVersion || header.payload_bytes > kMaxPayloadBytes ||
      (header.payload_bytes % sizeof(wchar_t)) != 0) return false;
  payload->assign(header.payload_bytes / sizeof(wchar_t), L'\0');
  if (header.payload_bytes &&
      !ReadExactWithDeadline(handle, payload->data(), header.payload_bytes, deadline)) return false;
  *type = static_cast<MessageType>(header.type);
  return true;
}

inline bool WriteMessageWithDeadline(HANDLE handle, MessageType type, const std::wstring& payload,
                                     ULONGLONG deadline) {
  const auto byte_count = payload.size() * sizeof(wchar_t);
  if (byte_count > kMaxPayloadBytes) return false;
  Header header{};
  header.type = static_cast<std::uint16_t>(type);
  header.payload_bytes = static_cast<std::uint32_t>(byte_count);
  return WriteExactWithDeadline(handle, &header, sizeof(header), deadline) &&
      (!byte_count || WriteExactWithDeadline(handle, payload.data(), header.payload_bytes, deadline));
}

// Overlapped variants for server-side pipes created with FILE_FLAG_OVERLAPPED.
// Passing a null OVERLAPPED to ReadFile/WriteFile on such a handle is invalid,
// so the host must funnel every transfer through these. The event in
// `overlapped` must be manual-reset; each call re-arms it before issuing I/O.
inline bool ReadExactOverlapped(HANDLE handle, OVERLAPPED* overlapped, void* data, DWORD bytes) {
  auto* cursor = static_cast<unsigned char*>(data);
  while (bytes > 0) {
    DWORD read = 0;
    ResetEvent(overlapped->hEvent);
    if (!ReadFile(handle, cursor, bytes, &read, overlapped)) {
      if (GetLastError() != ERROR_IO_PENDING ||
          !GetOverlappedResult(handle, overlapped, &read, TRUE)) return false;
    }
    if (read == 0) return false;
    cursor += read;
    bytes -= read;
  }
  return true;
}

inline bool WriteExactOverlapped(HANDLE handle, OVERLAPPED* overlapped, const void* data, DWORD bytes) {
  const auto* cursor = static_cast<const unsigned char*>(data);
  while (bytes > 0) {
    DWORD written = 0;
    ResetEvent(overlapped->hEvent);
    if (!WriteFile(handle, cursor, bytes, &written, overlapped)) {
      if (GetLastError() != ERROR_IO_PENDING ||
          !GetOverlappedResult(handle, overlapped, &written, TRUE)) return false;
    }
    if (written == 0) return false;
    cursor += written;
    bytes -= written;
  }
  return true;
}

inline bool ReadMessageOverlapped(HANDLE handle, OVERLAPPED* overlapped, MessageType* type,
                                  std::wstring* payload) {
  if (!type || !payload || !overlapped) return false;
  Header header{};
  if (!ReadExactOverlapped(handle, overlapped, &header, sizeof(header)) || header.magic != kMagic ||
      header.protocol_version != kProtocolVersion || header.payload_bytes > kMaxPayloadBytes ||
      (header.payload_bytes % sizeof(wchar_t)) != 0) return false;
  payload->assign(header.payload_bytes / sizeof(wchar_t), L'\0');
  if (header.payload_bytes &&
      !ReadExactOverlapped(handle, overlapped, payload->data(), header.payload_bytes)) return false;
  *type = static_cast<MessageType>(header.type);
  return true;
}

inline bool WriteMessageOverlapped(HANDLE handle, OVERLAPPED* overlapped, MessageType type,
                                   const std::wstring& payload) {
  if (!overlapped) return false;
  const auto byte_count = payload.size() * sizeof(wchar_t);
  if (byte_count > kMaxPayloadBytes) return false;
  Header header{};
  header.type = static_cast<std::uint16_t>(type);
  header.payload_bytes = static_cast<std::uint32_t>(byte_count);
  return WriteExactOverlapped(handle, overlapped, &header, sizeof(header)) &&
      (!byte_count || WriteExactOverlapped(handle, overlapped, payload.data(), header.payload_bytes));
}

inline std::wstring EncodeCandidates(const std::vector<std::wstring>& candidates) {
  std::wstring encoded;
  for (const auto& candidate : candidates) {
    if (!encoded.empty()) encoded.push_back(L'\0');
    encoded += candidate;
  }
  return encoded;
}

inline std::vector<std::wstring> DecodeCandidates(const std::wstring& encoded) {
  std::vector<std::wstring> candidates;
  size_t begin = 0;
  while (begin < encoded.size()) {
    const size_t end = encoded.find(L'\0', begin);
    const size_t length = (end == std::wstring::npos ? encoded.size() : end) - begin;
    if (length) candidates.emplace_back(encoded.substr(begin, length));
    if (end == std::wstring::npos) break;
    begin = end + 1;
  }
  return candidates;
}

inline std::wstring EncodeLearningEvent(const std::wstring& pinyin, const std::wstring& candidate,
                                        int input_mode = -1) {
  std::wstring encoded = pinyin + std::wstring(1, L'\0') + candidate;
  if (input_mode >= 0 && input_mode <= 1) encoded += std::wstring(1, L'\0') + std::to_wstring(input_mode);
  return encoded;
}

inline bool DecodeLearningEvent(const std::wstring& encoded, std::wstring* pinyin, std::wstring* candidate,
                                int* input_mode = nullptr) {
  if (!pinyin || !candidate) return false;
  const size_t separator = encoded.find(L'\0');
  if (separator == std::wstring::npos || separator == 0 || separator + 1 >= encoded.size()) return false;
  *pinyin = encoded.substr(0, separator);
  const size_t mode_separator = encoded.find(L'\0', separator + 1);
  *candidate = encoded.substr(separator + 1, mode_separator == std::wstring::npos
      ? std::wstring::npos : mode_separator - separator - 1);
  if (candidate->empty()) return false;
  if (input_mode) {
    *input_mode = -1;  // v1 sender compatibility: resolve from active mode.
    if (mode_separator != std::wstring::npos) {
      const std::wstring value = encoded.substr(mode_separator + 1);
      if (value == L"0") *input_mode = 0;
      else if (value == L"1") *input_mode = 1;
      else return false;
    }
  }
  return true;
}
inline std::wstring EncodeCandidateUi(const CandidateUiState& state) {
  const bool chinese_candidates = state.candidate_purpose == 0;
  const unsigned effective_page_start = chinese_candidates ? state.page_start : 0;
  const bool effective_chinese_grid = chinese_candidates && state.chinese_grid_open;
  std::wstring encoded = std::to_wstring(state.caret.left);
  encoded.push_back(L'\0');
  encoded += std::to_wstring(state.caret.top);
  encoded.push_back(L'\0');
  encoded += std::to_wstring(state.caret.right);
  encoded.push_back(L'\0');
  encoded += std::to_wstring(state.caret.bottom);
  encoded.push_back(L'\0');
  encoded += std::to_wstring(state.selected);
  encoded.push_back(L'\0');
  encoded += std::to_wstring(effective_page_start);
  // Tagged fields preserve compatibility with older payloads while letting the
  // TSF DLL make the Host render the exact active input mode and grid state.
  encoded.push_back(L'\0');
  encoded += L"@mode=" + std::to_wstring(state.input_mode > 2 ? 2 : state.input_mode);
  encoded.push_back(L'\0');
  // Keep the legacy wire tag for protocol compatibility; the in-memory field
  // is deliberately Chinese-specific.
  encoded += L"@expanded=" + std::to_wstring(effective_chinese_grid ? 1 : 0);
  encoded.push_back(L'\0');
  encoded += L"@englishlist=" + std::to_wstring(
      !chinese_candidates && state.english_list_open ? 1 : 0);
  encoded.push_back(L'\0');
  encoded += L"@englishfocus=" + std::to_wstring(
      !chinese_candidates && state.english_candidate_focus ? 1 : 0);
  encoded.push_back(L'\0');
  encoded += L"@purpose=" + std::to_wstring(state.candidate_purpose > 2 ? 0 : state.candidate_purpose);
  encoded.push_back(L'\0');
  encoded += L"@pipe=" + state.callback_pipe;
  encoded.push_back(L'\0');
  encoded += L"@composition=" + state.composition;
  if (!state.correction_indices.empty()) {
    encoded.push_back(L'\0');
    encoded += L"@corrections=";
    for (size_t index = 0; index < state.correction_indices.size(); ++index) {
      if (index) encoded.push_back(L',');
      encoded += std::to_wstring(state.correction_indices[index]);
    }
  }
  for (const auto& candidate : state.candidates) {
    encoded.push_back(L'\0');
    encoded += candidate;
  }
  return encoded;
}

inline bool DecodeCandidateUi(const std::wstring& encoded, CandidateUiState* state) {
  if (!state) return false;
  std::vector<std::wstring> fields;
  size_t begin = 0;
  while (begin <= encoded.size()) {
    const size_t end = encoded.find(L'\0', begin);
    fields.emplace_back(encoded.substr(begin, end == std::wstring::npos ? std::wstring::npos : end - begin));
    if (end == std::wstring::npos) break;
    begin = end + 1;
  }
  if (fields.size() < 7) return false;
  try {
    const auto left = std::stoll(fields[0]);
    const auto top = std::stoll(fields[1]);
    const auto right = std::stoll(fields[2]);
    const auto bottom = std::stoll(fields[3]);
    if (left < std::numeric_limits<LONG>::min() || left > std::numeric_limits<LONG>::max() ||
        top < std::numeric_limits<LONG>::min() || top > std::numeric_limits<LONG>::max() ||
        right < std::numeric_limits<LONG>::min() || right > std::numeric_limits<LONG>::max() ||
        bottom < std::numeric_limits<LONG>::min() || bottom > std::numeric_limits<LONG>::max()) return false;
    state->caret = RECT{static_cast<LONG>(left), static_cast<LONG>(top), static_cast<LONG>(right), static_cast<LONG>(bottom)};
    state->selected = static_cast<unsigned>(std::stoul(fields[4]));
    state->page_start = static_cast<unsigned>(std::stoul(fields[5]));
  } catch (...) {
    return false;
  }
  size_t first_candidate = 6;
  if (fields.size() > first_candidate && fields[first_candidate].rfind(L"@mode=", 0) == 0) {
    try { state->input_mode = static_cast<unsigned>(std::stoul(fields[first_candidate].substr(6))); } catch (...) { return false; }
    if (state->input_mode > 2) return false;
    ++first_candidate;
  }
  if (fields.size() > first_candidate && fields[first_candidate].rfind(L"@expanded=", 0) == 0) {
    const std::wstring value = fields[first_candidate].substr(10);
    if (value != L"0" && value != L"1") return false;
    state->chinese_grid_open = value == L"1";
    ++first_candidate;
  }
  if (fields.size() > first_candidate && fields[first_candidate].rfind(L"@englishlist=", 0) == 0) {
    const std::wstring value = fields[first_candidate].substr(13);
    if (value != L"0" && value != L"1") return false;
    state->english_list_open = value == L"1";
    ++first_candidate;
  }
  if (fields.size() > first_candidate && fields[first_candidate].rfind(L"@englishfocus=", 0) == 0) {
    const std::wstring value = fields[first_candidate].substr(14);
    if (value != L"0" && value != L"1") return false;
    state->english_candidate_focus = value == L"1";
    ++first_candidate;
  }
  if (fields.size() > first_candidate && fields[first_candidate].rfind(L"@purpose=", 0) == 0) {
    try { state->candidate_purpose = static_cast<unsigned>(std::stoul(fields[first_candidate].substr(9))); }
    catch (...) { return false; }
    if (state->candidate_purpose > 2) return false;
    ++first_candidate;
  }
  if (fields.size() > first_candidate && fields[first_candidate].rfind(L"@pipe=", 0) == 0) {
    state->callback_pipe = fields[first_candidate].substr(6);
    ++first_candidate;
  }
  if (fields.size() > first_candidate && fields[first_candidate].rfind(L"@composition=", 0) == 0) {
    state->composition = fields[first_candidate].substr(13);
    ++first_candidate;
  }
  if (fields.size() > first_candidate && fields[first_candidate].rfind(L"@corrections=", 0) == 0) {
    const std::wstring list = fields[first_candidate].substr(13);
    size_t correction_begin = 0;
    while (correction_begin <= list.size()) {
      const size_t end = list.find(L',', correction_begin);
      try {
        const std::wstring token = list.substr(correction_begin, end == std::wstring::npos ? std::wstring::npos : end - correction_begin);
        if (token.empty()) return false;
        state->correction_indices.push_back(static_cast<unsigned>(std::stoul(token)));
      } catch (...) {
        return false;
      }
      if (end == std::wstring::npos) break;
      correction_begin = end + 1;
    }
    ++first_candidate;
  }
  // Defense in depth for legacy or hand-crafted payloads: English surfaces
  // have no page and no Chinese-grid state even if the wire fields request it.
  if (state->candidate_purpose != 0) {
    state->page_start = 0;
    state->chinese_grid_open = false;
  } else {
    state->english_list_open = false;
    state->english_candidate_focus = false;
  }
  state->candidates.assign(fields.begin() + first_candidate, fields.end());
  if (state->candidates.empty()) return false;
  for (const unsigned index : state->correction_indices) {
    if (index >= state->candidates.size()) return false;
  }
  return true;
}
}  // namespace gy::host
