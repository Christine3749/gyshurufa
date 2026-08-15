#pragma once

#include <windows.h>

namespace gy::tsf_edit_session {

// RequestEditSession reports an accepted asynchronous request as TF_S_ASYNC,
// not S_OK.  Both are successful HRESULT values and both mean the caller must
// keep its composition state alive until DoEditSession runs.
constexpr bool WasAccepted(HRESULT result) noexcept {
  return SUCCEEDED(result);
}

// A queued content/ranking edit belongs to the mode generation that produced
// it. A composition lifecycle edit is different: once accepted it must still
// run even if discovering a URL/password scope changes the mode first.
constexpr bool ShouldApply(bool lifecycle_edit,
                           unsigned long long queued_generation,
                           unsigned long long current_generation) noexcept {
  return lifecycle_edit || queued_generation == current_generation;
}

// A direct-input classification can arrive after the first key (Firefox's
// address bar does this). That key belongs to the user and must be committed
// literally; only an empty transition has nothing to preserve.
constexpr bool ShouldCommitRawForDirectInput(bool entering_direct_input,
                                             bool has_composition_text) noexcept {
  return entering_direct_input && has_composition_text;
}

}  // namespace gy::tsf_edit_session
