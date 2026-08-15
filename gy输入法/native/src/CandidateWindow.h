#pragma once

#include "CandidateLayout.h"
#include "CandidatePresentationPolicy.h"

#include <functional>
#include <limits>
#include <string>
#include <vector>
#include <windows.h>

class CandidateWindow {
public:
  static constexpr unsigned kCandidatesPerPage = gy::candidate_presentation::CompactCapacity();
  static constexpr unsigned kToggleModeAction = std::numeric_limits<unsigned>::max();
  static constexpr unsigned kPreviousPageAction = kToggleModeAction - 1;
  static constexpr unsigned kNextPageAction = kToggleModeAction - 2;
  static constexpr unsigned kToggleChineseGridAction = kToggleModeAction - 3;
  static constexpr unsigned kPreviousChineseGridPageAction = kToggleModeAction - 4;
  static constexpr unsigned kNextChineseGridPageAction = kToggleModeAction - 5;
  static constexpr unsigned kToggleEnglishListAction = kToggleModeAction - 6;
  // Expanded candidates are deliberately invariant across displays: five
  // columns by five rows. This is a product rule, not a responsive hint.
  static constexpr unsigned kExpandedColumns = gy::candidate_layout::ExpandedColumns();
  static constexpr unsigned kExpandedMaxRows = gy::candidate_layout::ExpandedRows(25);
  static constexpr unsigned kEnglishCandidates =
      gy::candidate_presentation::EnglishCompactCapacity();
  static constexpr unsigned kExpandedEnglishCandidates =
      gy::candidate_presentation::EnglishExpandedCapacity();

  CandidateWindow(std::function<bool(unsigned)> choose, std::function<void(const RECT&)> open_settings);
  ~CandidateWindow();
  CandidateWindow(const CandidateWindow&) = delete;
  CandidateWindow& operator=(const CandidateWindow&) = delete;

  void Show(const RECT& caret, const std::wstring& pinyin,
            const std::vector<std::wstring>& candidates, unsigned selected,
            unsigned page_start, int input_mode, unsigned candidate_purpose,
            bool chinese_grid_open, bool english_list_open, bool english_candidate_focus,
            const std::vector<unsigned>& correction_indices = {});
  void ShowMode(const RECT& caret, int input_mode);
  void Hide();
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

private:
  void ShowInternal(const RECT& caret, const std::wstring& pinyin,
                    const std::vector<std::wstring>& candidates, unsigned selected,
                    unsigned page_start, const std::vector<unsigned>& correction_indices = {});
  void Layout(UINT dpi, int available_width);
  void Paint(HDC dc);
  void OpenSettings();

  HWND hwnd_ = nullptr;
  std::wstring pinyin_;
  std::vector<std::wstring> candidates_;
  std::vector<unsigned> correction_indices_;
  std::vector<RECT> candidate_rects_;
  RECT pinyin_rect_{};
  RECT candidate_strip_rect_{};
  RECT caret_rect_{};
  RECT mode_rect_{};
  RECT previous_page_rect_{};
  RECT next_page_rect_{};
  RECT page_indicator_rect_{};
  RECT expand_rect_{};
  unsigned selected_ = 0;
  unsigned page_start_ = 0;
  unsigned grid_columns_ = kCandidatesPerPage;
  unsigned expanded_column_target_ = kExpandedColumns;
  UINT dpi_ = 96;
  int candidate_point_size_ = 15;
  int candidate_scale_percent_ = 100;
  int content_width_ = 0;
  int content_height_ = 0;
  int window_width_ = 0;
  int window_height_ = 0;
  bool dark_theme_ = false;
  int visual_style_ = 0;
  bool mode_popup_ = false;
  bool english_mode_ = false;
  int input_mode_ = 0;
  gy::candidate_presentation::Purpose candidate_purpose_ =
      gy::candidate_presentation::Purpose::ChineseConversion;
  std::function<bool(unsigned)> choose_;
  bool chinese_grid_open_ = false;
  bool english_list_open_ = false;
  bool english_candidate_focus_ = false;
  bool clip_overflow_ = false;
  std::function<void(const RECT&)> open_settings_;
};

