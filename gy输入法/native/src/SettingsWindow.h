#pragma once

#include <windows.h>

class SettingsWindow {
public:
  void Show(const RECT& anchor);
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

private:
  void CreateControls();
  void Layout();
  void Paint(HDC dc);
  void Load();
  void Save();
  void TogglePhrases();
  void ClearLearning();
  void ExportBackup();
  void ImportBackup();
  bool Hit(const RECT& rect, POINT point) const;

  HWND hwnd_ = nullptr;
  int width_ = 520;
  HWND account_edit_ = nullptr;
  HWND phrases_edit_ = nullptr;
  HBRUSH edit_brush_ = nullptr;
  UINT dpi_ = 96;
  int theme_ = 0;
  int size_index_ = 1;
  bool phrases_expanded_ = false;
  RECT account_rect_{};
  RECT theme_rects_[3]{};
  RECT size_rects_[3]{};
  RECT phrases_rect_{};
  RECT clear_rect_{};
  RECT export_rect_{};
  RECT import_rect_{};
  RECT done_rect_{};
  RECT close_rect_{};
};