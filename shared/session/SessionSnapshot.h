#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace gy::session {

enum class InputMode : std::uint8_t { Simplified, Traditional, English };
enum class EngineSlot : std::uint8_t { A, B };

struct Candidate {
  std::string text;
  std::uint32_t engine_index{};

  bool operator==(const Candidate&) const = default;
};

// UTF-8 is the cross-platform wire representation. Platform bridges convert
// only at their edge; the guard never interprets, ranks, or uploads text.
struct SessionSnapshot {
  std::uint64_t sequence{};
  InputMode mode{InputMode::Simplified};
  std::string preedit;
  std::vector<Candidate> candidates;
  std::size_t selection{};
};

struct EngineRequest {
  std::uint64_t sequence{};
  InputMode mode{InputMode::Simplified};
  std::string preedit;
};

struct EngineResponse {
  std::uint64_t sequence{};
  std::string preedit;
  std::vector<Candidate> candidates;
};

}  // namespace gy::session
