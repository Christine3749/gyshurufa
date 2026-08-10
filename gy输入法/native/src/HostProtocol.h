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
constexpr std::uint16_t kProtocolVersion = 1;
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
  std::vector<std::wstring> candidates;
  unsigned selected = 0;
  unsigned page_start = 0;
  unsigned input_mode = 0;  // 0 = simplified, 1 = traditional, 2 = English
  bool expanded = false;
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

inline std::wstring EncodeLearningEvent(const std::wstring& pinyin, const std::wstring& candidate) {
  return pinyin + std::wstring(1, L'\0') + candidate;
}

inline bool DecodeLearningEvent(const std::wstring& encoded, std::wstring* pinyin, std::wstring* candidate) {
  if (!pinyin || !candidate) return false;
  const size_t separator = encoded.find(L'\0');
  if (separator == std::wstring::npos || separator == 0 || separator + 1 >= encoded.size()) return false;
  *pinyin = encoded.substr(0, separator);
  *candidate = encoded.substr(separator + 1);
  return true;
}
inline std::wstring EncodeCandidateUi(const CandidateUiState& state) {
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
  encoded += std::to_wstring(state.page_start);
  // Tagged fields preserve compatibility with older payloads while letting the
  // TSF DLL make the Host render the exact active input mode and grid state.
  encoded.push_back(L'\0');
  encoded += L"@mode=" + std::to_wstring(state.input_mode > 2 ? 2 : state.input_mode);
  encoded.push_back(L'\0');
  encoded += L"@expanded=" + std::to_wstring(state.expanded ? 1 : 0);
  encoded.push_back(L'\0');
  encoded += L"@pipe=" + state.callback_pipe;
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
    state->expanded = value == L"1";
    ++first_candidate;
  }
  if (fields.size() > first_candidate && fields[first_candidate].rfind(L"@pipe=", 0) == 0) {
    state->callback_pipe = fields[first_candidate].substr(6);
    ++first_candidate;
  }
  state->candidates.assign(fields.begin() + first_candidate, fields.end());
  return !state->candidates.empty();
}
}  // namespace gy::host


