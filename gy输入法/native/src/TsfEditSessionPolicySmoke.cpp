#include <windows.h>
#include <msctf.h>

#include "TsfEditSessionPolicy.h"

int wmain() {
  using gy::tsf_edit_session::ShouldApply;
  using gy::tsf_edit_session::ShouldCommitRawForDirectInput;
  using gy::tsf_edit_session::WasAccepted;

  if (!WasAccepted(S_OK)) return 1;
  // Firefox publishes the URL input scope from OnEndEdit.  A cleanup requested
  // there is necessarily queued and reports TF_S_ASYNC.
  if (!WasAccepted(TF_S_ASYNC)) return 2;
  if (WasAccepted(TF_E_LOCKED)) return 3;
  if (WasAccepted(TF_E_DISCONNECTED)) return 4;

  if (!ShouldApply(false, 7, 7)) return 5;
  if (ShouldApply(false, 7, 8)) return 6;
  // The regression: URL-scope discovery advances the mode generation before
  // the accepted lifecycle edit runs. Cleanup/commit must not be discarded.
  if (!ShouldApply(true, 7, 8)) return 7;
  // Late direct-input discovery must preserve the already captured first key.
  if (!ShouldCommitRawForDirectInput(true, true)) return 8;
  if (ShouldCommitRawForDirectInput(true, false)) return 9;
  if (ShouldCommitRawForDirectInput(false, true)) return 10;
  return 0;
}
