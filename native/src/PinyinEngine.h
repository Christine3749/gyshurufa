#pragma once

#include <memory>
#include <string>
#include <vector>

class PinyinEngine {
public:
  explicit PinyinEngine(std::wstring module_directory);
  ~PinyinEngine();
  PinyinEngine(const PinyinEngine&) = delete;
  PinyinEngine& operator=(const PinyinEngine&) = delete;

  [[nodiscard]] std::vector<std::wstring> Lookup(const std::wstring& pinyin) const;
  // Stores only a local pinyin-to-candidate preference; no surrounding text is retained.
  void Learn(const std::wstring& pinyin, const std::wstring& candidate) const;
  [[nodiscard]] bool IsReady() const;
  [[nodiscard]] std::wstring Diagnostic() const;

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
