#pragma once

namespace gy::candidate_pool {

// Candidate data is independent from its presentation. Chinese may render
// the pool as three 5 x 5 pages while English renders it as a paged word list,
// but both engines may return the same bounded number of real candidates.
constexpr unsigned MaximumSize() noexcept { return 75; }

}  // namespace gy::candidate_pool
