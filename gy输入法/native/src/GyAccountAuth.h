#pragma once

#include <cstdint>
#include <string>

namespace gy::account_auth {

// Access tokens are intentionally process-memory only. The persisted record
// contains the refresh token and the email needed to identify a restored
// session, protected with the current Windows user's DPAPI key.
struct Session {
  std::wstring email;
  std::wstring access_token;
  std::wstring refresh_token;
  std::int64_t expires_at = 0;
};

struct StoredSession {
  std::wstring email;
  std::wstring refresh_token;
};

enum class Status {
  Success,
  Unauthorized,
  NetworkError,
  ServerError,
  InvalidResponse,
};

struct Result {
  Status status = Status::NetworkError;
  Session session;
};

Result Login(const std::wstring& email, const std::wstring& password);
Result Restore(const std::wstring& refresh_token);
void Logout(const std::wstring& refresh_token);

bool LoadStoredSession(StoredSession* session);
bool SaveStoredSession(const StoredSession& session);
bool ClearStoredSession();

}  // namespace gy::account_auth
