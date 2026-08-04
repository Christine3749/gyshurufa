#include "SessionGuard.h"

#include <cstdlib>
#include <iostream>

namespace {
using gy::session::Candidate;
using gy::session::EngineResponse;
using gy::session::EngineSlot;
using gy::session::InputMode;
using gy::session::ResponseResult;
using gy::session::SessionGuard;

void Require(bool condition, const char* message) {
  if (condition) return;
  std::cerr << "FAIL: " << message << '\n';
  std::exit(1);
}
}  // namespace

int main() {
  SessionGuard guard;
  guard.Start(InputMode::Simplified);
  for (const char letter : std::string("nihao")) Require(guard.Append({&letter, 1}), "append input");

  const auto request_a = guard.Request();
  Require(request_a.preedit == "nihao", "A receives complete preedit");
  Require(guard.Accept({request_a.sequence, "nihao", {{"你好", 0}, {"你号", 1}}}) == ResponseResult::Applied,
          "A result applies");
  Require(guard.Snapshot().candidates.front() == Candidate{"你好", 0}, "A first choice kept");

  const auto replay_b = guard.FailOverTo(EngineSlot::B);
  Require(guard.ActiveSlot() == EngineSlot::B, "backup slot becomes active");
  Require(replay_b.sequence == request_a.sequence && replay_b.preedit == "nihao", "B receives exact replay");
  Require(guard.Snapshot().candidates.empty(), "old candidates cannot select after failover");
  Require(guard.Accept({request_a.sequence - 1, "niha", {{"错误", 0}}}) == ResponseResult::IgnoredStale,
          "stale A response is ignored");
  Require(guard.Accept({replay_b.sequence, "nihao", {{"你好", 4}, {"拟好", 7}}}) == ResponseResult::Applied,
          "B result restores same composition");
  Require(guard.Snapshot().candidates.front() == Candidate{"你好", 4}, "engine selection index is preserved");

  Require(guard.Append("a"), "next input accepted");
  Require(guard.Accept({replay_b.sequence, "nihao", {{"你好", 0}}}) == ResponseResult::IgnoredStale,
          "late pre-failure result cannot overwrite new input");
  Require(guard.Snapshot().preedit == "nihaoa", "new input remains intact");
  std::cout << "PASS: Session Guard replays a full composition across Engine A/B failure.\n";
}
