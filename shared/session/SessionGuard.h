#pragma once

#include "SessionSnapshot.h"

#include <string_view>

namespace gy::session {

enum class ResponseResult : std::uint8_t { Applied, IgnoredStale, RejectedMismatch };

// The guard owns only replayable composition state. It intentionally has no
// dependency on Rime, AppKit, TSF, a candidate panel, disk, or network.
class SessionGuard {
public:
  void Start(InputMode mode);
  bool Append(std::string_view utf8);
  bool EraseLastInput();
  void Clear();

  [[nodiscard]] EngineRequest Request() const;
  [[nodiscard]] EngineRequest FailOverTo(EngineSlot slot);
  ResponseResult Accept(const EngineResponse& response);

  [[nodiscard]] const SessionSnapshot& Snapshot() const { return snapshot_; }
  [[nodiscard]] EngineSlot ActiveSlot() const { return active_slot_; }

private:
  void Advance();

  SessionSnapshot snapshot_;
  EngineSlot active_slot_{EngineSlot::A};
  std::uint64_t next_sequence_{1};
};

}  // namespace gy::session
