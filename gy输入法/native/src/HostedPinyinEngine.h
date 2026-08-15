#pragma once

#include <windows.h>

#include <memory>
#include <cstdint>
#include <string>
#include <vector>

class HostedPinyinEngine {
public:
  explicit HostedPinyinEngine(std::wstring module_directory);
  ~HostedPinyinEngine();
  HostedPinyinEngine(const HostedPinyinEngine&) = delete;
  HostedPinyinEngine& operator=(const HostedPinyinEngine&) = delete;

  [[nodiscard]] std::vector<std::wstring> Lookup(const std::wstring& pinyin, int input_mode,
                                                  std::uint64_t mode_generation);
  // If a selected candidate consumes only a prefix of a sentence-level
  // pinyin string, return the unconsumed suffix so TSF can start the next
  // composition instead of silently discarding it.
  [[nodiscard]] std::wstring RemainingPinyin(const std::wstring& pinyin,
                                              const std::wstring& candidate, int input_mode,
                                              std::uint64_t mode_generation);
  [[nodiscard]] std::wstring Diagnostic() const;
  // Start the Host when GY activates so the first candidate does not wait for
  // process creation and local Rime initialization.
  void Prewarm();
  void Learn(const std::wstring& pinyin, const std::wstring& candidate, int input_mode);
  void UndoLearn(const std::wstring& pinyin, const std::wstring& candidate, int input_mode);

  // UI is hosted out of process so visual updates do not replace a DLL loaded by apps.
  void ShowCandidates(const RECT& caret, const std::wstring& composition,
                      const std::vector<std::wstring>& candidates,
                      unsigned selected, unsigned page_start, int input_mode,
                      unsigned candidate_purpose, bool chinese_grid_open,
                      bool english_list_open, bool english_candidate_focus,
                      const std::wstring& callback_pipe, const std::vector<unsigned>& correction_indices = {});
  void HideCandidates();
  void ShowMode(const RECT& caret, int input_mode);

private:
  [[nodiscard]] std::vector<std::wstring> LookupExact(const std::wstring& pinyin, int input_mode,
                                                       std::uint64_t mode_generation);
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
