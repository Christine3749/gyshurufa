#include "CandidatePool.h"

#include <algorithm>

namespace gy::session {
namespace {
bool ValidUtf8(const std::string& text) {
  for (std::size_t i = 0; i < text.size();) {
    const auto byte = static_cast<unsigned char>(text[i]);
    std::size_t count = byte < 0x80 ? 1 : (byte & 0xe0) == 0xc0 ? 2 : (byte & 0xf0) == 0xe0 ? 3 : (byte & 0xf8) == 0xf0 ? 4 : 0;
    if (!count || i + count > text.size()) return false;
    if (count > 1 && (byte & (0x7f >> count)) == 0) return false;
    for (std::size_t offset = 1; offset < count; ++offset)
      if ((static_cast<unsigned char>(text[i + offset]) & 0xc0) != 0x80) return false;
    i += count;
  }
  return true;
}
}  // namespace

std::vector<Candidate> CandidatePool::Build(const std::vector<RankedCandidate>& ranked) {
  std::vector<Candidate> pool;
  pool.reserve(std::min(kMaximum, ranked.size()));
  for (const auto& entry : ranked) {
    if (entry.eligibility == CandidateEligibility::Reject || !entry.mode_compatible || entry.candidate.text.empty() ||
        !ValidUtf8(entry.candidate.text)) continue;
    const auto duplicate = std::find_if(pool.begin(), pool.end(), [&](const Candidate& candidate) {
      return candidate.text == entry.candidate.text;
    });
    if (duplicate != pool.end()) continue;
    pool.push_back(entry.candidate);
    if (pool.size() == kMaximum) break;
  }
  return pool;
}

std::vector<Candidate> CandidatePool::Page(const std::vector<Candidate>& pool, std::size_t page) {
  const std::size_t start = page * kPageSize;
  if (start >= pool.size()) return {};
  const std::size_t end = std::min(start + kPageSize, pool.size());
  return {pool.begin() + static_cast<std::ptrdiff_t>(start), pool.begin() + static_cast<std::ptrdiff_t>(end)};
}

std::size_t CandidatePool::PageCount(const std::vector<Candidate>& pool) {
  return (std::min(pool.size(), kMaximum) + kPageSize - 1) / kPageSize;
}

}  // namespace gy::session
