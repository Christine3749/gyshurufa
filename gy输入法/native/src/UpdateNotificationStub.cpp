#include "UpdateNotification.h"

// Engine-only smoke builders may not have the Windows SDK C++/WinRT headers.
// Product builds never compile this file; update toasts remain covered by the
// normal MSVC build and installer tests.
bool ShowGyUpdateNotification(const std::wstring&) {
  return false;
}
