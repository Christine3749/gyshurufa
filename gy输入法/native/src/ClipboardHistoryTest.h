#pragma once

#ifdef GY_TESTING

#include <windows.h>

#include <string>

namespace gy::clipboard_history::testing {

// Test seam for the same GDI+ bitmap-to-PNG path used by clipboard capture.
// It deliberately accepts an off-screen HBITMAP so automated tests never
// overwrite the user's real system clipboard.
bool EncodeBitmapAsPng(HBITMAP bitmap, std::string* png);

// The receiver's own clipboard writes must only suppress their matching
// WM_CLIPBOARDUPDATE sequence.  These seams test that a user's immediately
// following copy is never mistaken for a remote write.
void SuppressRemoteText(const std::wstring& text, DWORD clipboard_sequence);
bool IsSuppressedRemoteText(const std::wstring& text, DWORD clipboard_sequence);
void SuppressRemoteImage(DWORD clipboard_sequence);
bool TakeSuppressedRemoteImage(DWORD clipboard_sequence);

// Exercises the durable local-image capture path without opening or changing
// the user's real system clipboard.
bool AppendPngForTesting(const std::string& png, DWORD clipboard_sequence);

}  // namespace gy::clipboard_history::testing

#endif  // GY_TESTING
