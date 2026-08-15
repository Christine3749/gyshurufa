#include "EnglishCandidatePolicy.h"

#include <vector>

int main() {
  using gy::english_candidates::Candidate;
  using gy::english_candidates::Kind;

  const auto completion = gy::english_candidates::Completion(L"wor", L"work", 98);
  if (completion.kind != Kind::Completion || completion.replace_begin != 0 ||
      completion.replace_end != 3 || completion.confidence != 98 ||
      completion.source != gy::english_candidates::Source::LocalLexicon ||
      gy::english_candidates::ResolveCommit(L"wor", completion) != L"work") return 1;

  const Candidate correction{Kind::Correction, L"work", L"work", 0, 4, 99,
                             gy::english_candidates::Source::LocalCorrection};
  if (gy::english_candidates::ResolveCommit(L"wrok", correction) != L"work") return 2;

  const Candidate next_word{Kind::NextWord, L"like", L"like", 8, 8, 95,
                            gy::english_candidates::Source::LocalLanguageModel};
  if (gy::english_candidates::ResolveCommit(L"I would ", next_word) != L"I would like") return 3;

  const Candidate stale{Kind::Correction, L"work", L"work", 0, 9, 99,
                        gy::english_candidates::Source::LocalCorrection};
  if (gy::english_candidates::ResolveCommit(L"wor", stale) != L"wor") return 4;

  const std::vector<std::wstring> words{
      L"word", L"work", L"world", L"would", L"woman", L"worker", L"working", L"workplace", L"worry"};
  const auto visible = gy::english_candidates::CompletionCandidates(L"wo", words);
  if (visible.size() != gy::english_candidates::kMaximumVisible ||
      visible.front().display_text != L"word" || visible.back().display_text != L"workplace") return 5;
  if (gy::english_candidates::Completion(L"To", L"today").display_text != L"Today" ||
      gy::english_candidates::Completion(L"GP", L"gpt").display_text != L"GPT" ||
      gy::english_candidates::Completion(L"Mac", L"macbook").display_text != L"Macbook" ||
      gy::english_candidates::Completion(L"iP", L"iphone").display_text != L"iPhone") return 9;
  if (!gy::english_candidates::CanApplyAsyncResult(7, 7, false) ||
      gy::english_candidates::CanApplyAsyncResult(6, 7, false) ||
      gy::english_candidates::CanApplyAsyncResult(7, 7, true)) return 6;
  if (!gy::english_candidates::CanShowAtInputState(Kind::Completion, false) ||
      gy::english_candidates::CanShowAtInputState(Kind::Completion, true) ||
      gy::english_candidates::CanShowAtInputState(Kind::NextWord, false) ||
      !gy::english_candidates::CanShowAtInputState(Kind::NextWord, true)) return 7;
  if (!gy::english_candidates::CanCommitCandidate(9, 9) ||
      gy::english_candidates::CanCommitCandidate(8, 9)) return 8;
  return 0;
}
