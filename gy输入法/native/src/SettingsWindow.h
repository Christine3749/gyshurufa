#pragma once

#include <windows.h>

#include "ClipboardHistory.h"

#include <cstdint>
#include <string>
#include <vector>

namespace gy::account_auth {
struct Result;
}

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
  void ApplyThemeBrush();
  void ClearLearning();
  void ClearHistory();
  void ExportBackup();
  void ImportBackup();
  void BeginAccountLogin();
  void BeginAccountRestore();
  void BeginAccountLogout();
  void FinishAccountRequest(std::uint64_t request_id, gy::account_auth::Result* result);
  bool Hit(const RECT& rect, POINT point) const;

  enum class Page { General, Input, Appearance, Account, Clipboard, Updates };
  enum class AccountState { LoggedOut, Restoring, LoggingIn, LoggedIn, Failed };

  HWND hwnd_ = nullptr;
  int width_ = 520;
  int height_ = 680;
  HWND account_edit_ = nullptr;
  HWND account_email_edit_ = nullptr;
  HWND account_password_edit_ = nullptr;
  HWND phrases_edit_ = nullptr;
  HBRUSH edit_brush_ = nullptr;
  HBRUSH account_input_brush_ = nullptr;
  // 0 = simplified Chinese, 1 = traditional Chinese, 2 = English passthrough.
  int input_mode_ = 0;
  UINT dpi_ = 96;
  int theme_ = 0;
  int size_index_ = 1;
  Page page_ = Page::General;
  RECT input_mode_rects_[3]{};
  RECT nav_rects_[6]{};
  bool phrases_expanded_ = false;
  // Performance\WarmStart: keep-alive between DLL and Host. Default on; the
  // 输入 page card toggles it and annotates the low-spec recommendation.
  bool warm_start_ = true;
  RECT account_rect_{};
  RECT account_email_rect_{};
  RECT account_password_rect_{};
  RECT account_action_rect_{};
  RECT account_logout_rect_{};
  RECT theme_rects_[3]{};
  RECT size_rects_[3]{};
  RECT phrases_rect_{};
  RECT clear_rect_{};
  RECT export_rect_{};
  RECT import_rect_{};
  RECT ai_preview_rect_{};
  RECT warm_rect_{};
  RECT done_rect_{};
  RECT close_rect_{};

  // 剪贴板页（CLIPBOARD-PAGE-DESIGN.md）：开关拨动即写入，不等“完成”。
  // 本机历史卡直接在页内列出最近 20 条文本，滚轮翻页。
  bool clip_enabled_ = true;
  bool clip_instant_ = true;
  std::vector<gy::clipboard_history::Entry> history_entries_;
  std::vector<int> history_card_heights_;  // variable: content owns 1..4 lines
  struct ClipboardThumbnail {
    std::wstring entry_id;
    HBITMAP bitmap = nullptr;
    SIZE size{};
  };
  // Decoded thumbnails are window-local only. The full PNG stays in the
  // clipboard asset store; this avoids decoding a 10 MiB screenshot on every
  // WM_PAINT while the settings page is open.
  std::vector<ClipboardThumbnail> history_thumbnails_;
  int history_scroll_ = 0;
  int history_max_scroll_ = 0;
  void MeasureClipboardCards();
  ClipboardThumbnail* FindOrCreateThumbnail(const gy::clipboard_history::Entry& entry,
                                            int max_width, int max_height);
  void PruneClipboardThumbnails();
  void ClearClipboardThumbnails();
  RECT clip_sync_card_{};
  RECT clip_sync_switch_{};
  RECT clip_instant_card_{};
  RECT clip_instant_switch_{};
  RECT clip_history_clear_{};
  RECT clip_history_list_{};
  RECT version_card_{};
  RECT update_card_{};
  std::wstring release_version_;
  std::wstring registered_version_;
  std::vector<std::wstring> release_notes_;
  std::wstring registered_core_version_;
  bool versions_consistent_ = false;

  // GY account credentials are never written into settings.ini. The refresh
  // token is DPAPI-protected in a separate file; the access token lives only
  // while GyImeHost is running.
  AccountState account_state_ = AccountState::LoggedOut;
  std::wstring account_email_;
  std::wstring account_access_token_;
  std::int64_t account_token_expiry_ = 0;
  std::wstring account_status_;
  std::uint64_t window_instance_id_ = 0;
  std::uint64_t account_request_id_ = 0;
};
