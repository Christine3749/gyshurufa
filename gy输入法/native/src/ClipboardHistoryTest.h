#pragma once

#ifdef GY_TESTING

#include <windows.h>

#include <string>

namespace gy::clipboard_history::testing {

// Test seam for the same GDI+ bitmap-to-PNG path used by clipboard capture.
// It deliberately accepts an off-screen HBITMAP so automated tests never
// overwrite the user's real system clipboard.
bool EncodeBitmapAsPng(HBITMAP bitmap, std::string* png);

}  // namespace gy::clipboard_history::testing

#endif  // GY_TESTING
