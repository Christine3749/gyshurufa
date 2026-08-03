#pragma once

#include "InputMode.h"

// Test-only scope for deterministic Chinese candidate checks. Production code
// continues to read the user's shared input-mode state normally.
namespace gy::test {
class ScopedInputMode final {
 public:
  explicit ScopedInputMode(int mode) : previous_(input_mode::Read()) {
    input_mode::Write(mode);
  }

  ~ScopedInputMode() { input_mode::Write(previous_); }

  ScopedInputMode(const ScopedInputMode&) = delete;
  ScopedInputMode& operator=(const ScopedInputMode&) = delete;

 private:
  int previous_;
};
}  // namespace gy::test
