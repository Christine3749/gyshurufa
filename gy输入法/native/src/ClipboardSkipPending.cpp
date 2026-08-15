#include "ClipboardHistory.h"

#include <iostream>

int wmain() {
  size_t skipped = 0;
  if (!gy::clipboard_history::SkipPendingUploads(&skipped)) {
    std::wcerr << L"Could not skip the pending clipboard queue. No upload was attempted.\n";
    return 1;
  }
  std::wcout << L"Skipped " << skipped << L" pre-login clipboard records.\n";
  return 0;
}
