#include "SessionGuard.h"

namespace gy::session {

void SessionGuard::Start(InputMode mode) {
  snapshot_ = {};
  snapshot_.mode = mode;
  active_slot_ = EngineSlot::A;
  Advance();
}

bool SessionGuard::Append(std::string_view utf8) {
  if (utf8.empty() || snapshot_.mode == InputMode::English) return false;
  snapshot_.preedit.append(utf8);
  Advance();
  return true;
}

bool SessionGuard::EraseLastInput() {
  if (snapshot_.preedit.empty()) return false;
  snapshot_.preedit.pop_back();
  Advance();
  return true;
}

void SessionGuard::Clear() {
  const InputMode mode = snapshot_.mode;
  snapshot_ = {};
  snapshot_.mode = mode;
  Advance();
}

EngineRequest SessionGuard::Request() const {
  return {snapshot_.sequence, snapshot_.mode, snapshot_.preedit};
}

EngineRequest SessionGuard::FailOverTo(EngineSlot slot) {
  active_slot_ = slot;
  snapshot_.candidates.clear();
  snapshot_.selection = 0;
  return Request();
}

ResponseResult SessionGuard::Accept(const EngineResponse& response) {
  if (response.sequence < snapshot_.sequence) return ResponseResult::IgnoredStale;
  if (response.sequence != snapshot_.sequence || response.preedit != snapshot_.preedit)
    return ResponseResult::RejectedMismatch;
  snapshot_.candidates = response.candidates;
  snapshot_.selection = 0;
  return ResponseResult::Applied;
}

void SessionGuard::Advance() {
  snapshot_.sequence = next_sequence_++;
  snapshot_.candidates.clear();
  snapshot_.selection = 0;
}

}  // namespace gy::session
