#pragma once

#include "SessionSnapshot.h"

#include <cstddef>
#include <vector>

namespace gy::session {

enum class CandidateEligibility : std::uint8_t { Reject, Qualified, Preferred };

// The Engine, not the panel, assigns eligibility from its dictionary and
// ranking model. The shared layer never guesses from word length or glyphs.
struct RankedCandidate {
  Candidate candidate;
  CandidateEligibility eligibility{CandidateEligibility::Reject};
  bool mode_compatible{};
};

class CandidatePool {
public:
  static constexpr std::size_t kMaximum = 75;
  static constexpr std::size_t kPageSize = 25;

  static std::vector<Candidate> Build(const std::vector<RankedCandidate>& ranked);
  static std::vector<Candidate> Page(const std::vector<Candidate>& pool, std::size_t page);
  static std::size_t PageCount(const std::vector<Candidate>& pool);
};

}  // namespace gy::session
