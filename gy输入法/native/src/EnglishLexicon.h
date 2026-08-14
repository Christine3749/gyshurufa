#pragma once

#include "CandidatePoolPolicy.h"

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace gy::english_lexicon {

// Refreshes the verified local snapshot from disk.  This is Host maintenance
// work (startup / post-update), never part of a lookup or a TSF key callback.
// It never contacts a server; the separate updater owns download and hash
// verification before atomically replacing the local snapshot.
void RefreshVerifiedSnapshot();

// Mixed input is resolved only from an in-memory copy of a verified local
// snapshot. The TSF key path never reads a file or contacts a server.
[[nodiscard]] bool IsMixedInputEnabled();
[[nodiscard]] std::wstring ExactWord(std::wstring_view composition);
[[nodiscard]] std::wstring SuffixWord(std::wstring_view composition,
                                      std::size_t* pinyin_prefix_length);
// Pure EN mode uses the same verified local snapshot as mixed input, but
// exposes its prefix matches as the complete candidate list. No network or
// UI work occurs on this path.
[[nodiscard]] std::vector<std::wstring> PrefixMatches(std::wstring_view composition,
    std::size_t maximum_results = gy::candidate_pool::MaximumSize());

}  // namespace gy::english_lexicon
