#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

class PinyinEngine {
public:
  enum class LearningTier : std::uint8_t {
    None,
    Once,
    Memory,
    High,
    Fixed,
  };

  struct LearningSummary {
    unsigned count = 0;
    unsigned recent_7_days = 0;
    unsigned recent_30_days = 0;
    unsigned active_days = 0;
    bool pinned = false;
    LearningTier tier = LearningTier::None;
  };

  explicit PinyinEngine(std::wstring module_directory);
  ~PinyinEngine();
  PinyinEngine(const PinyinEngine&) = delete;
  PinyinEngine& operator=(const PinyinEngine&) = delete;

  [[nodiscard]] std::vector<std::wstring> Lookup(const std::wstring& pinyin) const;
  // Returns only candidates produced for the exact query. Lookup() may append
  // shorter-prefix fallback candidates to fill the first page; segmentation
  // logic must never treat those fallback entries as proof that a longer
  // prefix was consumed.
  [[nodiscard]] std::vector<std::wstring> LookupExact(const std::wstring& pinyin) const;
  // Stores only a local pinyin-to-candidate preference; no surrounding text is retained.
  void Learn(const std::wstring& pinyin, const std::wstring& candidate) const;
  // A pinned entry is a user-approved fixed word. It is intentionally a
  // separate operation from normal learning so one accidental selection can
  // never create a permanent dictionary preference.
  bool SetLearningPinned(const std::wstring& pinyin, const std::wstring& candidate, bool pinned) const;
  [[nodiscard]] LearningSummary GetLearningSummary(const std::wstring& pinyin,
                                                   const std::wstring& candidate) const;
  [[nodiscard]] bool IsReady() const;
  [[nodiscard]] std::wstring Diagnostic() const;

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
