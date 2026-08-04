#pragma once

#include <windows.h>

#include <memory>
#include <string>
#include <vector>

class HostedPinyinEngine {
public:
  explicit HostedPinyinEngine(std::wstring module_directory);
  ~HostedPinyinEngine();
  HostedPinyinEngine(const HostedPinyinEngine&) = delete;
  HostedPinyinEngine& operator=(const HostedPinyinEngine&) = delete;

  [[nodiscard]] std::vector<std::wstring> Lookup(const std::wstring& pinyin);
  [[nodiscard]] std::wstring Diagnostic() const;
  // Start the Host when GY activates so the first candidate does not wait for
  // process creation and local Rime initialization.
  void Prewarm();
  void Learn(const std::wstring& pinyin, const std::wstring& candidate);

  // UI is hosted out of process so visual updates do not replace a DLL loaded by apps.
  void ShowCandidates(const RECT& caret, const std::vector<std::wstring>& candidates,
                      unsigned selected, unsigned page_start, int input_mode, bool expanded, const std::wstring& callback_pipe);
  void HideCandidates();
  void ShowMode(const RECT& caret, int input_mode);

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
