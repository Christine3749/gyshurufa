#include "CandidatePool.h"

#include <cstdlib>
#include <iostream>

namespace {
using gy::session::CandidateEligibility;
using gy::session::CandidatePool;
using gy::session::RankedCandidate;

void Require(bool condition, const char* message) {
  if (condition) return;
  std::cerr << "FAIL: " << message << '\n';
  std::exit(1);
}

RankedCandidate Word(std::string text, unsigned index, CandidateEligibility eligibility = CandidateEligibility::Qualified) {
  return {{std::move(text), index}, eligibility, true};
}
}  // namespace

int main() {
  std::vector<RankedCandidate> raw = {
      Word("你好", 0, CandidateEligibility::Preferred), Word("妳好", 1, CandidateEligibility::Reject),
      Word("你好", 2), Word("", 3), Word("错误", 4), Word("\xF0\x28\x8C\xBC", 5)};
  raw[4].mode_compatible = false;
  const auto sparse = CandidatePool::Build(raw);
  Require(sparse.size() == 1 && sparse.front().text == "你好" && sparse.front().engine_index == 0,
          "only real eligible candidates appear; no fillers");

  std::vector<RankedCandidate> many;
  for (unsigned index = 0; index < 80; ++index) many.push_back(Word("候选" + std::to_string(index), index));
  const auto capped = CandidatePool::Build(many);
  Require(capped.size() == CandidatePool::kMaximum, "candidate pool is capped at 75");
  Require(CandidatePool::PageCount(capped) == 3, "75 candidates occupy exactly three pages");
  Require(CandidatePool::Page(capped, 0).size() == 25 && CandidatePool::Page(capped, 2).size() == 25,
          "each full page contains 25 real candidates");
  Require(CandidatePool::Page(capped, 3).empty(), "no fourth filler page");
  std::cout << "PASS: Candidate Pool preserves eligible order and never pads sparse results.\n";
}
