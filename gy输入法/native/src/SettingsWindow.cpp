#include "SettingsWindow.h"
#include "InputMode.h"
#include "ClipboardHistory.h"
#include "SettingsFile.h"

#include <algorithm>
#include <commdlg.h>
#include <commctrl.h>
#include <ctime>
#include <windowsx.h>
#include <iterator>
#include <string>
#include <vector>

namespace {
constexpr wchar_t kClassName[] = L"GyImeSettingsWindow";
// The settings window follows the candidate-window theme (Appearance\Theme):
// one choice, one palette. GY Blue stays constant across themes because it is
// the VI-locked selection color, and text on accent pills stays near-white.
constexpr COLORREF kBlue = RGB(43, 96, 221);
constexpr COLORREF kOnAccent = RGB(250, 250, 251);

struct Palette {
  COLORREF ink;            // window background
  COLORREF surface;        // card background
  COLORREF surface_hover;  // selected card background
  COLORREF border;
  COLORREF text;           // primary text
  COLORREF muted;          // secondary text
};

Palette PaletteForTheme(int theme) {
  switch (theme) {
    case 1:  // 暖白: warm light surface matching the candidate strip swatch.
      return {RGB(243, 241, 235), RGB(252, 251, 248), RGB(234, 231, 224), RGB(208, 203, 193), RGB(26, 27, 30), RGB(122, 120, 113)};
    case 2:  // 石墨: neutral graphite without the blue-night cast.
      return {RGB(21, 23, 28), RGB(30, 33, 40), RGB(36, 40, 48), RGB(54, 59, 70), RGB(244, 245, 247), RGB(148, 154, 168)};
    default:  // GY 蓝夜: the original dark palette.
      return {RGB(16, 18, 22), RGB(29, 33, 40), RGB(35, 39, 47), RGB(52, 58, 69), RGB(250, 250, 251), RGB(155, 163, 179)};
  }
}
constexpr UINT kMaxSettingsDpi = 136;

int Scale(UINT dpi, int value) { return MulDiv(value, static_cast<int>(dpi), 96); }
UINT DpiFor(HWND hwnd) { return hwnd ? GetDpiForWindow(hwnd) : GetDpiForSystem(); }

void Fill(HDC dc, const RECT& rect, COLORREF color) {
  const HBRUSH brush = CreateSolidBrush(color);
  FillRect(dc, &rect, brush);
  DeleteObject(brush);
}
void Rounded(HDC dc, const RECT& rect, COLORREF fill, COLORREF border, int radius) {
  const HBRUSH brush = CreateSolidBrush(fill);
  const HPEN pen = CreatePen(PS_SOLID, 1, border);
  const HGDIOBJ old_brush = SelectObject(dc, brush);
  const HGDIOBJ old_pen = SelectObject(dc, pen);
  RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, radius, radius);
  SelectObject(dc, old_pen);
  SelectObject(dc, old_brush);
  DeleteObject(pen);
  DeleteObject(brush);
}
HFONT Font(UINT dpi, int points, int weight) {
  return CreateFontW(-Scale(dpi, points), 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                     OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                     DEFAULT_PITCH, L"Microsoft YaHei UI");
}
void Text(HDC dc, const std::wstring& value, RECT rect, COLORREF color, UINT format, HFONT font) {
  const HGDIOBJ previous = SelectObject(dc, font);
  SetTextColor(dc, color);
  SetBkMode(dc, TRANSPARENT);
  DrawTextW(dc, value.c_str(), -1, &rect, format | DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);
  SelectObject(dc, previous);
}

// Three related choices are one quiet control, not three separate cards. The
// selected item is the only solid accent; unselected items intentionally keep
// the panel background so the settings page has a calmer system feel.
void DrawSegmentedChoices(HDC dc, const RECT (&rects)[3], const wchar_t* const labels[3],
                          int selected, const Palette& pal, UINT dpi, HFONT font) {
  const RECT group{rects[0].left, rects[0].top, rects[2].right, rects[0].bottom};
  Rounded(dc, group, pal.surface, pal.border, Scale(dpi, 9));
  for (int i = 0; i < 3; ++i) {
    if (i > 0) {
      const RECT divider{rects[i].left, group.top + Scale(dpi, 8),
                         rects[i].left + 1, group.bottom - Scale(dpi, 8)};
      Fill(dc, divider, pal.border);
    }
    if (i == selected) {
      RECT pill = rects[i];
      InflateRect(&pill, -Scale(dpi, 3), -Scale(dpi, 3));
      Rounded(dc, pill, kBlue, kBlue, Scale(dpi, 7));
    }
    Text(dc, labels[i], rects[i], i == selected ? kOnAccent : pal.text, DT_CENTER, font);
  }
}

// The utility actions are stored as separate members for hit testing. Keep
// that storage explicit instead of relying on an invalid pointer cast.
void DrawSegmentedActions(HDC dc, const RECT& first, const RECT& second, const RECT& third,
                          const wchar_t* const labels[3], const Palette& pal, UINT dpi, HFONT font) {
  const RECT rects[] = {first, second, third};
  const RECT group{rects[0].left, rects[0].top, rects[2].right, rects[0].bottom};
  Rounded(dc, group, pal.surface, pal.border, Scale(dpi, 9));
  for (int i = 0; i < 3; ++i) {
    if (i > 0) {
      const RECT divider{rects[i].left, group.top + Scale(dpi, 8),
                         rects[i].left + 1, group.bottom - Scale(dpi, 8)};
      Fill(dc, divider, pal.border);
    }
    Text(dc, labels[i], rects[i], pal.text, DT_CENTER, font);
  }
}

// The clipboard page's only instant-apply controls (CLIPBOARD-PAGE-DESIGN §3):
// a 44×26 pill with a 20 knob. On = accent fill with the knob parked right;
// off = surface_hover fill with the knob parked left.
void DrawSwitch(HDC dc, const RECT& rect, bool on, const Palette& pal, UINT dpi) {
  const int height = rect.bottom - rect.top;
  Rounded(dc, rect, on ? kBlue : pal.surface_hover, on ? kBlue : pal.border, height / 2);
  const int knob = Scale(dpi, 20);
  const int left = on ? rect.right - knob - Scale(dpi, 3) : rect.left + Scale(dpi, 3);
  const int top = rect.top + (height - knob) / 2;
  const HBRUSH brush = CreateSolidBrush(kOnAccent);
  const HGDIOBJ old_brush = SelectObject(dc, brush);
  const HGDIOBJ old_pen = SelectObject(dc, static_cast<HGDIOBJ>(GetStockObject(NULL_PEN)));
  Ellipse(dc, left, top, left + knob, top + knob);
  SelectObject(dc, old_pen);
  SelectObject(dc, old_brush);
  DeleteObject(brush);
}

// 剪贴板历史条目的时间戳：HH:MM 本地时间。
std::wstring FormatEntryTime(unsigned long long unix_time) {
  std::time_t value = static_cast<std::time_t>(unix_time);
  std::tm local{};
  if (localtime_s(&local, &value) != 0) return L"--:--";
  wchar_t buffer[6]{};
  swprintf_s(buffer, std::size(buffer), L"%02d:%02d", local.tm_hour, local.tm_min);
  return buffer;
}

// The compact master wordmark is traced from the approved GY brand SVG.
void DrawGyWordmark(HDC dc, const RECT& bounds, COLORREF color) {
  const float sx = static_cast<float>(bounds.right - bounds.left) / 156.0f;
  const float sy = static_cast<float>(bounds.bottom - bounds.top) / 100.0f;
  const auto x = [&](float value) { return bounds.left + static_cast<int>(value * sx + 0.5f); };
  const auto y = [&](float value) { return bounds.top + static_cast<int>(value * sy + 0.5f); };
  const HBRUSH brush = CreateSolidBrush(color);
  const HGDIOBJ old_brush = SelectObject(dc, brush);
  BeginPath(dc);
  MoveToEx(dc, x(72), y(26), nullptr);
  POINT g[] = {{x(65), y(18)}, {x(54), y(13)}, {x(40), y(13)}, {x(21), y(13)}, {x(8), y(28)}, {x(8), y(50)}, {x(8), y(72)}, {x(21), y(87)}, {x(40), y(87)}, {x(56), y(87)}, {x(68), y(77)}, {x(72), y(63)}};
  PolyBezierTo(dc, g, static_cast<DWORD>(std::size(g)));
  LineTo(dc, x(72), y(52)); LineTo(dc, x(40), y(52)); LineTo(dc, x(40), y(66)); LineTo(dc, x(57), y(66));
  POINT tail[] = {{x(54), y(72)}, {x(48), y(74)}, {x(40), y(74)}, {x(28), y(74)}, {x(21), y(64)}, {x(21), y(50)}, {x(21), y(36)}, {x(28), y(26)}, {x(40), y(26)}, {x(49), y(26)}, {x(56), y(31)}, {x(60), y(37)}};
  PolyBezierTo(dc, tail, static_cast<DWORD>(std::size(tail)));
  LineTo(dc, x(72), y(26)); CloseFigure(dc); EndPath(dc); FillPath(dc);
  BeginPath(dc);
  MoveToEx(dc, x(80), y(15), nullptr); LineTo(dc, x(94), y(15)); LineTo(dc, x(114), y(50)); LineTo(dc, x(134), y(15)); LineTo(dc, x(148), y(15)); LineTo(dc, x(121), y(60)); LineTo(dc, x(121), y(87)); LineTo(dc, x(107), y(87)); LineTo(dc, x(107), y(60)); LineTo(dc, x(80), y(15)); CloseFigure(dc); EndPath(dc); FillPath(dc);
  SelectObject(dc, old_brush); DeleteObject(brush);
}

std::wstring SettingsPath() {
  wchar_t root[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", root, MAX_PATH)) return {};
  const std::wstring directory = std::wstring(root) + L"\\GYInput";
  CreateDirectoryW(directory.c_str(), nullptr);
  return directory + L"\\settings.ini";
}
bool EnsureUnicodeSettingsFile(const std::wstring& path) {
  return gy::settings_file::EnsureUnicodeIniFile(path);
}
bool IsPortableSettingsFile(const std::wstring& path) {
  WIN32_FILE_ATTRIBUTE_DATA data{};
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return false;
  const ULARGE_INTEGER bytes{data.nFileSizeLow, data.nFileSizeHigh};
  return bytes.QuadPart > 0 && bytes.QuadPart <= 64 * 1024;
}
bool PickSettingsFile(HWND owner, bool save, std::wstring* path) {
  if (!path) return false;
  wchar_t filename[MAX_PATH] = L"GYInput-settings-backup.ini";
  OPENFILENAMEW dialog{}; dialog.lStructSize = sizeof(dialog); dialog.hwndOwner = owner;
  dialog.lpstrFilter = L"GY Input settings (*.ini)\0*.ini\0All files (*.*)\0*.*\0";
  dialog.lpstrFile = filename; dialog.nMaxFile = static_cast<DWORD>(std::size(filename));
  dialog.Flags = OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
  if (!(save ? GetSaveFileNameW(&dialog) : GetOpenFileNameW(&dialog))) return false;
  *path = filename; return true;
}
std::wstring Trim(std::wstring text) {
  const auto first = text.find_first_not_of(L" \t\r\n");
  if (first == std::wstring::npos) return {};
  const auto last = text.find_last_not_of(L" \t\r\n");
  return text.substr(first, last - first + 1);
}
ATOM RegisterSettingsClass() {
  static const ATOM atom = [] {
    WNDCLASSEXW wc{sizeof(wc)}; wc.lpfnWndProc = SettingsWindow::WindowProc;
    wc.hInstance = GetModuleHandleW(nullptr); wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName; return RegisterClassExW(&wc);
  }();
  return atom;
}
}  // namespace

void SettingsWindow::Show(const RECT& anchor) {
  if (hwnd_ && IsWindow(hwnd_)) {
    SetForegroundWindow(hwnd_);
    return;
  }
  if (!RegisterSettingsClass()) return;
  MONITORINFO monitor{sizeof(monitor)};
  GetMonitorInfoW(MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST), &monitor);
  const RECT work = monitor.rcWork;
  const int work_height = static_cast<int>(work.bottom - work.top);
  const int work_width = static_cast<int>(work.right - work.left);
  // A 13/14 inch notebook at 150–200% cannot fit the old fixed 474-DIP panel.
  // Use a compact effective scale instead of opening a clipped black popup.
  const UINT native_dpi = DpiFor(nullptr);
  // This is a deliberately fixed, portrait-like settings shell. Pages may
  // change their contents, but must never resize the shell underneath the user.
  // On a small display the effective DPI is reduced only enough to keep the
  // complete shell on-screen.
  const UINT fitting_dpi = static_cast<UINT>(std::max(80, MulDiv(std::max(1, work_height - 16), 96, 680)));
  dpi_ = std::min({native_dpi, fitting_dpi, kMaxSettingsDpi});
  width_ = std::min(Scale(dpi_, 520), std::max(Scale(dpi_, 360), work_width - Scale(dpi_, 16)));
  height_ = std::min(Scale(dpi_, 680), std::max(Scale(dpi_, 420), work_height - Scale(dpi_, 16)));
  const int width = width_;
  const int height = height_;
  const int x = std::clamp(static_cast<int>(anchor.left), static_cast<int>(work.left) + Scale(dpi_, 8), static_cast<int>(work.right) - width - Scale(dpi_, 8));
  int y = anchor.top - height - Scale(dpi_, 12);
  if (y < work.top + Scale(dpi_, 8)) y = std::min(anchor.bottom + Scale(dpi_, 12), work.bottom - height - Scale(dpi_, 8));
  hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kClassName, L"GY 设置", WS_POPUP,
                          x, y, width, height, nullptr, nullptr, GetModuleHandleW(nullptr), this);
  if (!hwnd_) return;
  CreateControls();
  Load();
  ApplyThemeBrush();
  Layout();
  RECT actual{}; GetWindowRect(hwnd_, &actual);
  const int final_width = actual.right - actual.left, final_height = actual.bottom - actual.top;
  const int final_x = std::clamp(x, static_cast<int>(work.left) + Scale(dpi_, 8), std::max(static_cast<int>(work.left) + Scale(dpi_, 8), static_cast<int>(work.right) - final_width - Scale(dpi_, 8)));
  const int final_y = std::clamp(y, static_cast<int>(work.top) + Scale(dpi_, 8), std::max(static_cast<int>(work.top) + Scale(dpi_, 8), static_cast<int>(work.bottom) - final_height - Scale(dpi_, 8)));
  SetWindowPos(hwnd_, HWND_TOPMOST, final_x, final_y, final_width, final_height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
  RedrawWindow(hwnd_, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW);
  SetFocus(hwnd_);
}

void SettingsWindow::ApplyThemeBrush() {
  if (edit_brush_) DeleteObject(edit_brush_);
  edit_brush_ = CreateSolidBrush(PaletteForTheme(theme_).surface);
}

void SettingsWindow::CreateControls() {
  edit_brush_ = CreateSolidBrush(PaletteForTheme(theme_).surface);
  account_edit_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | WS_TABSTOP,
      0, 0, 0, 0, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
  phrases_edit_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL | WS_TABSTOP,
      0, 0, 0, 0, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
  const HFONT font = Font(dpi_, 12, FW_NORMAL);
  SendMessageW(account_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  SendMessageW(phrases_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  // Placeholder so the borderless account field explains itself before typing.
  SendMessageW(account_edit_, EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(L"输入邮箱，例如 name@example.com"));
  // The edit controls retain their UI font for the lifetime of this Host.
}

void SettingsWindow::Layout() {
  if (!hwnd_) return;
  const int width = width_;
  const int nav_left = Scale(dpi_, 18), nav_width = Scale(dpi_, 72);
  const int content_left = Scale(dpi_, 112), right_pad = Scale(dpi_, 24);
  const int card_width = width - content_left - right_pad;
  const int group_height = Scale(dpi_, 42), option_width = card_width / 3;
  const int nav_top = Scale(dpi_, 118), nav_step = Scale(dpi_, 47);
  for (int i = 0; i < 5; ++i) nav_rects_[i] = {nav_left, nav_top + i * nav_step, nav_left + nav_width, nav_top + (i + 1) * nav_step};
  for (int i = 0; i < 3; ++i) { input_mode_rects_[i] = {}; theme_rects_[i] = {}; size_rects_[i] = {}; }
  account_rect_ = {}; phrases_rect_ = {}; clear_rect_ = {}; export_rect_ = {}; import_rect_ = {}; ai_preview_rect_ = {}; warm_rect_ = {};
  clip_sync_card_ = {}; clip_sync_switch_ = {}; clip_instant_card_ = {}; clip_instant_switch_ = {};
  clip_history_clear_ = {}; clip_history_list_ = {};

  const int base_y = Scale(dpi_, 150);
  int done_y = base_y;
  if (page_ == Page::General) {
    phrases_rect_ = {content_left, base_y, content_left + card_width, base_y + (phrases_expanded_ ? Scale(dpi_, 132) : Scale(dpi_, 58))};
    MoveWindow(phrases_edit_, phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 45), card_width - Scale(dpi_, 32), Scale(dpi_, 75), TRUE);
    ShowWindow(phrases_edit_, phrases_expanded_ ? SW_SHOW : SW_HIDE);
    const int tools_y = phrases_rect_.bottom + Scale(dpi_, 14);
    clear_rect_ = {content_left, tools_y, content_left + option_width, tools_y + group_height};
    export_rect_ = {content_left + option_width, tools_y, content_left + option_width * 2, tools_y + group_height};
    import_rect_ = {content_left + option_width * 2, tools_y, content_left + card_width, tools_y + group_height};
    // 剪贴板的两个开关放在通用页（产品决策：剪贴板页只留历史卡片列表）。
    clip_sync_card_ = {content_left, tools_y + group_height + Scale(dpi_, 14), content_left + card_width, tools_y + group_height + Scale(dpi_, 78)};
    clip_sync_switch_ = {clip_sync_card_.right - Scale(dpi_, 60), clip_sync_card_.top + Scale(dpi_, 19),
                         clip_sync_card_.right - Scale(dpi_, 16), clip_sync_card_.top + Scale(dpi_, 45)};
    clip_instant_card_ = {content_left, clip_sync_card_.bottom + Scale(dpi_, 14), content_left + card_width,
                          clip_sync_card_.bottom + Scale(dpi_, 100)};
    clip_instant_switch_ = {clip_instant_card_.right - Scale(dpi_, 60), clip_instant_card_.top + Scale(dpi_, 30),
                            clip_instant_card_.right - Scale(dpi_, 16), clip_instant_card_.top + Scale(dpi_, 56)};
    done_y = clip_instant_card_.bottom + Scale(dpi_, 22);
  } else if (page_ == Page::Input) {
    for (int i = 0; i < 3; ++i) input_mode_rects_[i] = {content_left + i * option_width, base_y, content_left + (i + 1) * option_width, base_y + group_height};
    phrases_rect_ = {content_left, base_y + group_height + Scale(dpi_, 28), content_left + card_width, base_y + group_height + Scale(dpi_, 86)};
    warm_rect_ = {content_left, phrases_rect_.bottom + Scale(dpi_, 14), content_left + card_width, phrases_rect_.bottom + Scale(dpi_, 86)};
    ShowWindow(phrases_edit_, SW_HIDE);
    done_y = warm_rect_.bottom + Scale(dpi_, 22);
  } else if (page_ == Page::Appearance) {
    // Full-width stacked theme cards preserve the approved narrow vertical
    // composition instead of turning this page into a three-column strip.
    const int theme_height = Scale(dpi_, 48);
    const int theme_gap = Scale(dpi_, 8);
    for (int i = 0; i < 3; ++i) {
      const int top = base_y + i * (theme_height + theme_gap);
      theme_rects_[i] = {content_left, top, content_left + card_width, top + theme_height};
    }
    const int size_y = theme_rects_[2].bottom + Scale(dpi_, 36);
    for (int i = 0; i < 3; ++i) size_rects_[i] = {content_left + i * option_width, size_y, content_left + (i + 1) * option_width, size_y + group_height};
    ai_preview_rect_ = {content_left, size_y + group_height + Scale(dpi_, 32), content_left + card_width, size_y + group_height + Scale(dpi_, 168)};
    ShowWindow(phrases_edit_, SW_HIDE);
    done_y = ai_preview_rect_.bottom + Scale(dpi_, 20);
  } else if (page_ == Page::Account) {
    account_rect_ = {content_left, base_y, content_left + card_width, base_y + Scale(dpi_, 52)};
    MoveWindow(account_edit_, account_rect_.left + Scale(dpi_, 126), account_rect_.top + Scale(dpi_, 13), std::max(Scale(dpi_, 120), card_width - Scale(dpi_, 152)), Scale(dpi_, 26), TRUE);
    phrases_rect_ = {content_left, account_rect_.bottom + Scale(dpi_, 18), content_left + card_width, account_rect_.bottom + Scale(dpi_, 90)};
    // 从“通用”页展开短语后切过来，编辑器不能残留在本页。
    ShowWindow(phrases_edit_, SW_HIDE);
    done_y = phrases_rect_.bottom + Scale(dpi_, 22);
  } else {
    // Page::Clipboard：页内只有历史——标题/清空 + 卡片式条目列表（开关在通用页）。
    done_y = Scale(dpi_, 616);
    clip_history_clear_ = {content_left + card_width - Scale(dpi_, 60), base_y + Scale(dpi_, 2),
                           content_left + card_width, base_y + Scale(dpi_, 30)};
    clip_history_list_ = {content_left, base_y + Scale(dpi_, 40), content_left + card_width, done_y - Scale(dpi_, 10)};
    history_entries_ = gy::clipboard_history::ReadAll();
    const int entry_h = Scale(dpi_, 54);
    const int visible = std::max(1, static_cast<int>(clip_history_list_.bottom - clip_history_list_.top) / entry_h);
    history_scroll_ = std::clamp(history_scroll_, 0, std::max(0, static_cast<int>(history_entries_.size()) - visible));
    ShowWindow(phrases_edit_, SW_HIDE);
  }
  ShowWindow(account_edit_, page_ == Page::Account ? SW_SHOW : SW_HIDE);
  done_rect_ = {width - right_pad - Scale(dpi_, 110), done_y, width - right_pad, done_y + Scale(dpi_, 42)};
  close_rect_ = {width - Scale(dpi_, 48), Scale(dpi_, 18), width - Scale(dpi_, 18), Scale(dpi_, 48)};
  // The outer frame is fixed. Changing tabs or expanding phrases must never
  // make the settings dialog jump or change its proportions.
  const HRGN region = CreateRoundRectRgn(0, 0, width + 1, height_ + 1, Scale(dpi_, 14), Scale(dpi_, 14));
  SetWindowRgn(hwnd_, region, FALSE);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

bool SettingsWindow::Hit(const RECT& rect, POINT point) const { return !IsRectEmpty(&rect) && PtInRect(&rect, point); }
void SettingsWindow::TogglePhrases() { phrases_expanded_ = !phrases_expanded_; Layout(); }

void SettingsWindow::Paint(HDC dc) {
  const Palette pal = PaletteForTheme(theme_);
  RECT client{}; GetClientRect(hwnd_, &client);
  Fill(dc, client, pal.ink);
  const HPEN outline = CreatePen(PS_SOLID, 1, pal.border);
  const HGDIOBJ old_pen = SelectObject(dc, outline); const HGDIOBJ old_brush = SelectObject(dc, GetStockObject(HOLLOW_BRUSH));
  RoundRect(dc, 0, 0, client.right, client.bottom, Scale(dpi_, 14), Scale(dpi_, 14));
  SelectObject(dc, old_pen); SelectObject(dc, old_brush); DeleteObject(outline);
  const HFONT title = Font(dpi_, 17, FW_SEMIBOLD), medium = Font(dpi_, 11, FW_SEMIBOLD), tiny = Font(dpi_, 10, FW_NORMAL);
  DrawGyWordmark(dc, RECT{Scale(dpi_, 24), Scale(dpi_, 25), Scale(dpi_, 76), Scale(dpi_, 58)}, pal.text);
  Text(dc, L"输入法设置", RECT{Scale(dpi_, 90), Scale(dpi_, 23), Scale(dpi_, 300), Scale(dpi_, 56)}, pal.text, DT_LEFT, title);
  Text(dc, L"基础输入始终离线可用", RECT{Scale(dpi_, 90), Scale(dpi_, 52), Scale(dpi_, 310), Scale(dpi_, 72)}, pal.muted, DT_LEFT, tiny);
  Text(dc, L"×", close_rect_, pal.muted, DT_CENTER, title);

  const wchar_t* nav_labels[] = {L"通用", L"输入", L"外观", L"账户", L"剪贴板"};
  for (int i = 0; i < 5; ++i) {
    const bool selected = static_cast<int>(page_) == i;
    if (selected) {
      RECT marker{nav_rects_[i].right - Scale(dpi_, 2), nav_rects_[i].top + Scale(dpi_, 8), nav_rects_[i].right + Scale(dpi_, 7), nav_rects_[i].bottom - Scale(dpi_, 8)};
      Fill(dc, marker, kBlue);
    }
    Text(dc, nav_labels[i], nav_rects_[i], selected ? pal.text : pal.muted, DT_CENTER, medium);
  }

  const int content_left = Scale(dpi_, 112), content_right = width_ - Scale(dpi_, 24);
  const wchar_t* page_titles[] = {L"通用", L"输入", L"外观", L"账户", L"剪贴板"};
  const wchar_t* page_subtitles[] = {L"学习、短语与本机备份", L"切换正在使用的输入语言", L"主题、字号与 AI 预览助手", L"本机标识与未来的同步账户", L"跨设备复制粘贴与本机历史"};
  Text(dc, page_titles[static_cast<int>(page_)], RECT{content_left, Scale(dpi_, 98), content_right, Scale(dpi_, 122)}, pal.text, DT_LEFT, medium);
  Text(dc, page_subtitles[static_cast<int>(page_)], RECT{content_left, Scale(dpi_, 118), content_right, Scale(dpi_, 137)}, pal.muted, DT_LEFT, tiny);

  if (page_ == Page::General) {
    Rounded(dc, phrases_rect_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"常用短语", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 8), phrases_rect_.left + Scale(dpi_, 190), phrases_rect_.top + Scale(dpi_, 32)}, pal.text, DT_LEFT, medium);
    Text(dc, phrases_expanded_ ? L"完成编辑" : L"管理 ›", RECT{phrases_rect_.right - Scale(dpi_, 100), phrases_rect_.top + Scale(dpi_, 8), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 32)}, kBlue, DT_RIGHT, medium);
    if (!phrases_expanded_) Text(dc, L"例如：dz=地址|电子邮箱", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 31), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.bottom - Scale(dpi_, 7)}, pal.muted, DT_LEFT, tiny);
    const wchar_t* tools[] = {L"清空学习", L"导出", L"导入"};
    DrawSegmentedActions(dc, clear_rect_, export_rect_, import_rect_, tools, pal, dpi_, medium);
    // 剪贴板的两个开关挂在通用页（剪贴板页只留历史卡片列表）。
    Rounded(dc, clip_sync_card_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"跨设备剪贴板", RECT{clip_sync_card_.left + Scale(dpi_, 16), clip_sync_card_.top + Scale(dpi_, 9), clip_sync_card_.right - Scale(dpi_, 76), clip_sync_card_.top + Scale(dpi_, 31)}, pal.text, DT_LEFT, medium);
    Text(dc, L"在已配对的设备间同步复制内容", RECT{clip_sync_card_.left + Scale(dpi_, 16), clip_sync_card_.top + Scale(dpi_, 33), clip_sync_card_.right - Scale(dpi_, 76), clip_sync_card_.top + Scale(dpi_, 53)}, pal.muted, DT_LEFT, tiny);
    DrawSwitch(dc, clip_sync_switch_, clip_enabled_, pal, dpi_);
    Rounded(dc, clip_instant_card_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"即时粘贴", RECT{clip_instant_card_.left + Scale(dpi_, 16), clip_instant_card_.top + Scale(dpi_, 9), clip_instant_card_.right - Scale(dpi_, 76), clip_instant_card_.top + Scale(dpi_, 31)}, pal.text, DT_LEFT, medium);
    // Windows 面板只提 Ctrl+V；设计稿里的 ⌘V 是 Mac 端文案。
    Text(dc, L"我复制的内容直接写入其他设备的剪贴板，Ctrl+V 即可粘贴", RECT{clip_instant_card_.left + Scale(dpi_, 16), clip_instant_card_.top + Scale(dpi_, 32), clip_instant_card_.right - Scale(dpi_, 16), clip_instant_card_.top + Scale(dpi_, 51)}, pal.muted, DT_LEFT, tiny);
    Text(dc, L"关闭后，收到的内容只进入剪贴板历史，需手动选择", RECT{clip_instant_card_.left + Scale(dpi_, 16), clip_instant_card_.top + Scale(dpi_, 54), clip_instant_card_.right - Scale(dpi_, 16), clip_instant_card_.bottom - Scale(dpi_, 12)}, pal.muted, DT_LEFT, tiny);
    DrawSwitch(dc, clip_instant_switch_, clip_instant_, pal, dpi_);
  } else if (page_ == Page::Input) {
    Text(dc, L"输入语言", RECT{input_mode_rects_[0].left, input_mode_rects_[0].top - Scale(dpi_, 22), input_mode_rects_[2].right, input_mode_rects_[0].top - Scale(dpi_, 3)}, pal.muted, DT_LEFT, tiny);
    const wchar_t* input_modes[] = {L"简体", L"繁体", L"EN"};
    DrawSegmentedChoices(dc, input_mode_rects_, input_modes, input_mode_, pal, dpi_, medium);
    Rounded(dc, phrases_rect_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"切换规则", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 9), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 31)}, pal.text, DT_LEFT, medium);
    Text(dc, L"Shift 快速切换 EN；EN 模式下字母、标点、Enter 与快捷键原样直出。", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 31), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.bottom - Scale(dpi_, 7)}, pal.muted, DT_LEFT, tiny);
    // Warm start card: the toggle is honest about the low-spec trade-off, so
    // the annotation must stay in sync with PerformanceSettings.h consumers.
    Rounded(dc, warm_rect_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"热启动加速", RECT{warm_rect_.left + Scale(dpi_, 16), warm_rect_.top + Scale(dpi_, 9), warm_rect_.left + Scale(dpi_, 190), warm_rect_.top + Scale(dpi_, 31)}, pal.text, DT_LEFT, medium);
    Text(dc, warm_start_ ? L"已开启 · 点击关闭" : L"已关闭 · 点击开启", RECT{warm_rect_.right - Scale(dpi_, 150), warm_rect_.top + Scale(dpi_, 9), warm_rect_.right - Scale(dpi_, 16), warm_rect_.top + Scale(dpi_, 31)}, warm_start_ ? kBlue : pal.muted, DT_RIGHT, medium);
    Text(dc, L"开启后引擎保持热连接，按键零等待；关闭后每次按键重新握手。", RECT{warm_rect_.left + Scale(dpi_, 16), warm_rect_.top + Scale(dpi_, 32), warm_rect_.right - Scale(dpi_, 16), warm_rect_.top + Scale(dpi_, 48)}, pal.muted, DT_LEFT, tiny);
    Text(dc, L"建议 4 核 CPU / 8 GB 内存及以上开启；更低配置的设备请关闭。", RECT{warm_rect_.left + Scale(dpi_, 16), warm_rect_.top + Scale(dpi_, 49), warm_rect_.right - Scale(dpi_, 16), warm_rect_.bottom - Scale(dpi_, 7)}, pal.muted, DT_LEFT, tiny);
  } else if (page_ == Page::Appearance) {
    Text(dc, L"候选窗主题", RECT{theme_rects_[0].left, theme_rects_[0].top - Scale(dpi_, 22), theme_rects_[2].right, theme_rects_[0].top - Scale(dpi_, 3)}, pal.muted, DT_LEFT, tiny);
    const wchar_t* themes[] = {L"GY 蓝夜", L"暖白", L"石墨"};
    for (int i = 0; i < 3; ++i) {
      const bool selected = theme_ == i;
      Rounded(dc, theme_rects_[i], selected ? pal.surface_hover : pal.surface, selected ? kBlue : pal.border, Scale(dpi_, 8));
      RECT preview{theme_rects_[i].left + Scale(dpi_, 12), theme_rects_[i].top + Scale(dpi_, 9), theme_rects_[i].left + Scale(dpi_, 112), theme_rects_[i].bottom - Scale(dpi_, 9)};
      const COLORREF preview_fill = i == 1 ? RGB(246, 244, 239) : (i == 2 ? RGB(21, 23, 28) : RGB(17, 27, 46));
      const COLORREF preview_ink = i == 1 ? RGB(26, 27, 30) : kOnAccent;
      Rounded(dc, preview, preview_fill, selected ? kBlue : pal.border, Scale(dpi_, 5));
      Text(dc, L"GY   1   2   3", RECT{preview.left + Scale(dpi_, 7), preview.top, preview.right - Scale(dpi_, 5), preview.bottom}, preview_ink, DT_LEFT, tiny);
      Text(dc, themes[i], RECT{preview.right + Scale(dpi_, 16), theme_rects_[i].top, theme_rects_[i].right - Scale(dpi_, 46), theme_rects_[i].bottom}, pal.text, DT_LEFT, medium);
      Text(dc, selected ? L"●" : L"○", RECT{theme_rects_[i].right - Scale(dpi_, 34), theme_rects_[i].top, theme_rects_[i].right - Scale(dpi_, 14), theme_rects_[i].bottom}, selected ? kBlue : pal.muted, DT_CENTER, medium);
    }
    Text(dc, L"候选字大小", RECT{size_rects_[0].left, size_rects_[0].top - Scale(dpi_, 22), size_rects_[2].right, size_rects_[0].top - Scale(dpi_, 3)}, pal.muted, DT_LEFT, tiny);
    const wchar_t* sizes[] = {L"紧凑", L"默认", L"大"};
    DrawSegmentedChoices(dc, size_rects_, sizes, size_index_, pal, dpi_, medium);
    Rounded(dc, ai_preview_rect_, pal.surface, pal.border, Scale(dpi_, 10));
    Text(dc, L"AI 外观预览助手", RECT{ai_preview_rect_.left + Scale(dpi_, 16), ai_preview_rect_.top + Scale(dpi_, 12), ai_preview_rect_.right - Scale(dpi_, 16), ai_preview_rect_.top + Scale(dpi_, 36)}, pal.text, DT_LEFT, medium);
    Text(dc, L"可根据你的描述生成预览；确认前不会更改任何设置。", RECT{ai_preview_rect_.left + Scale(dpi_, 16), ai_preview_rect_.top + Scale(dpi_, 34), ai_preview_rect_.right - Scale(dpi_, 16), ai_preview_rect_.top + Scale(dpi_, 54)}, pal.muted, DT_LEFT, tiny);
    RECT preview_input{ai_preview_rect_.left + Scale(dpi_, 16), ai_preview_rect_.top + Scale(dpi_, 66), ai_preview_rect_.right - Scale(dpi_, 16), ai_preview_rect_.top + Scale(dpi_, 100)};
    Rounded(dc, preview_input, pal.ink, pal.border, Scale(dpi_, 7));
    Text(dc, L"例如：更安静一点，字稍微大一点", RECT{preview_input.left + Scale(dpi_, 12), preview_input.top, preview_input.right - Scale(dpi_, 12), preview_input.bottom}, pal.muted, DT_LEFT, tiny);
    Text(dc, L"只可建议主题、字号与对比度；不会修改 Logo、候选窗箭头、布局或输入交互。", RECT{ai_preview_rect_.left + Scale(dpi_, 16), ai_preview_rect_.top + Scale(dpi_, 110), ai_preview_rect_.right - Scale(dpi_, 16), ai_preview_rect_.bottom - Scale(dpi_, 10)}, pal.muted, DT_LEFT, tiny);
  } else if (page_ == Page::Account) {
    Rounded(dc, account_rect_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"账号", RECT{account_rect_.left + Scale(dpi_, 16), account_rect_.top + Scale(dpi_, 5), account_rect_.left + Scale(dpi_, 112), account_rect_.bottom - Scale(dpi_, 8)}, pal.text, DT_LEFT, medium);
    Text(dc, L"本地标识", RECT{account_rect_.left + Scale(dpi_, 16), account_rect_.top + Scale(dpi_, 25), account_rect_.left + Scale(dpi_, 112), account_rect_.bottom}, pal.muted, DT_LEFT, tiny);
    // The account edit is a borderless EDIT child; without a visible frame it
    // blends into the card and users cannot discover where to type.
    const RECT account_input{account_rect_.left + Scale(dpi_, 116), account_rect_.top + Scale(dpi_, 10), account_rect_.right - Scale(dpi_, 16), account_rect_.bottom - Scale(dpi_, 10)};
    Rounded(dc, account_input, pal.ink, pal.border, Scale(dpi_, 7));
    Rounded(dc, phrases_rect_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"GY 账户", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 10), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 32)}, pal.text, DT_LEFT, medium);
    Text(dc, L"同步、跨设备词库和 AI 权益将在账户接入后开放。", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 31), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.bottom - Scale(dpi_, 8)}, pal.muted, DT_LEFT, tiny);
  } else {
    // Page::Clipboard：纯历史卡片列表（开关在通用页）。每条历史一张圆角卡片。
    const int head_y = clip_history_clear_.top - Scale(dpi_, 2);
    Text(dc, L"本机历史", RECT{content_left, head_y, clip_history_clear_.left - Scale(dpi_, 16), head_y + Scale(dpi_, 24)}, pal.text, DT_LEFT, medium);
    Text(dc, L"清空", clip_history_clear_, kBlue, DT_CENTER, medium);
    Text(dc, L"保留最近 20 条，先进后出；敏感内容仅保存在本机", RECT{content_left, head_y + Scale(dpi_, 24), clip_history_list_.right, head_y + Scale(dpi_, 40)}, pal.muted, DT_LEFT, tiny);
    const int entry_stride = Scale(dpi_, 54);
    const int card_h = Scale(dpi_, 46);
    const int visible_rows = std::max(1, static_cast<int>(clip_history_list_.bottom - clip_history_list_.top) / entry_stride);
    const int overflow = static_cast<int>(history_entries_.size()) - visible_rows;
    if (history_entries_.empty()) {
      Text(dc, L"还没有剪贴板历史，复制一段文字试试", clip_history_list_, pal.muted, DT_CENTER, tiny);
    } else {
      for (int row = 0; row < visible_rows; ++row) {
        const int index = history_scroll_ + row;
        if (index >= static_cast<int>(history_entries_.size())) break;
        const auto& entry = history_entries_[static_cast<size_t>(index)];
        const int top = clip_history_list_.top + row * entry_stride;
        RECT card{clip_history_list_.left, top, clip_history_list_.right - Scale(dpi_, overflow > 0 ? 10 : 0), top + card_h};
        Rounded(dc, card, pal.surface, pal.border, Scale(dpi_, 9));
        std::wstring first_line = entry.text.substr(0, entry.text.find_first_of(L"\r\n"));
        std::replace(first_line.begin(), first_line.end(), L'\t', L' ');
        Text(dc, first_line, RECT{card.left + Scale(dpi_, 12), card.top + Scale(dpi_, 6), card.right - Scale(dpi_, 12), card.top + Scale(dpi_, 26)}, pal.text, DT_LEFT, tiny);
        Text(dc, FormatEntryTime(entry.unix_time), RECT{card.left + Scale(dpi_, 12), card.top + Scale(dpi_, 27), card.right - Scale(dpi_, 12), card.bottom - Scale(dpi_, 5)}, pal.muted, DT_LEFT, tiny);
      }
      if (overflow > 0) {
        RECT track{clip_history_list_.right - Scale(dpi_, 4), clip_history_list_.top + Scale(dpi_, 2),
                   clip_history_list_.right, clip_history_list_.bottom - Scale(dpi_, 2)};
        Fill(dc, track, pal.border);
        const int track_h = track.bottom - track.top;
        const int thumb_h = std::max(Scale(dpi_, 20), track_h * visible_rows / static_cast<int>(history_entries_.size()));
        const int thumb_y = track.top + (track_h - thumb_h) * history_scroll_ / std::max(1, overflow);
        RECT thumb{track.left, thumb_y, track.right, thumb_y + thumb_h};
        Fill(dc, thumb, pal.muted);
      }
    }
  }

  Rounded(dc, done_rect_, kBlue, kBlue, Scale(dpi_, 8));
  Text(dc, L"完成", done_rect_, kOnAccent, DT_CENTER, medium);
  Text(dc, L"所有基础输入设置仅保存在本机", RECT{content_left, done_rect_.top, done_rect_.left - Scale(dpi_, 16), done_rect_.bottom}, pal.muted, DT_LEFT, tiny);
  DeleteObject(title); DeleteObject(medium); DeleteObject(tiny);
}

void SettingsWindow::Load() {
  input_mode_ = gy::input_mode::Read();
  const std::wstring path = SettingsPath(); if (path.empty()) return;
  wchar_t account[128]{}; GetPrivateProfileStringW(L"Account", L"Name", L"", account, static_cast<DWORD>(std::size(account)), path.c_str());
  SetWindowTextW(account_edit_, account);
  theme_ = std::clamp(static_cast<int>(GetPrivateProfileIntW(L"Appearance", L"Theme", 0, path.c_str())), 0, 2);
  const int points = GetPrivateProfileIntW(L"Appearance", L"CandidateSize", 15, path.c_str());
  size_index_ = points <= 13 ? 0 : points >= 17 ? 2 : 1;
  warm_start_ = GetPrivateProfileIntW(L"Performance", L"WarmStart", 1, path.c_str()) != 0;
  // CLIPBOARD-PAGE-DESIGN §4：跨设备剪贴板与即时粘贴均默认开。
  clip_enabled_ = GetPrivateProfileIntW(L"Clipboard", L"Enabled", 1, path.c_str()) != 0;
  clip_instant_ = GetPrivateProfileIntW(L"Clipboard", L"InstantPaste", 1, path.c_str()) != 0;

  std::vector<wchar_t> phrases(4096, L'\0'); GetPrivateProfileSectionW(L"Phrases", phrases.data(), static_cast<DWORD>(phrases.size()), path.c_str());
  std::wstring text;
  for (const wchar_t* current = phrases.data(); *current; current += wcslen(current) + 1) { if (!text.empty()) text += L"\r\n"; text += current; }
  SetWindowTextW(phrases_edit_, text.c_str());
}
void SettingsWindow::Save() {
  const std::wstring path = SettingsPath(); if (path.empty() || !EnsureUnicodeSettingsFile(path)) return;
  wchar_t account[128]{}; GetWindowTextW(account_edit_, account, static_cast<int>(std::size(account)));
  const int points[] = {13, 15, 17};
  WritePrivateProfileStringW(L"Account", L"Name", account, path.c_str());
  WritePrivateProfileStringW(L"Appearance", L"Theme", std::to_wstring(theme_).c_str(), path.c_str());
  WritePrivateProfileStringW(L"Appearance", L"CandidateSize", std::to_wstring(points[size_index_]).c_str(), path.c_str());
  WritePrivateProfileStringW(L"Performance", L"WarmStart", warm_start_ ? L"1" : L"0", path.c_str());
  WritePrivateProfileStringW(L"Clipboard", L"Enabled", clip_enabled_ ? L"1" : L"0", path.c_str());
  WritePrivateProfileStringW(L"Clipboard", L"InstantPaste", clip_instant_ ? L"1" : L"0", path.c_str());
  gy::input_mode::Write(input_mode_);
  const int length = GetWindowTextLengthW(phrases_edit_); std::vector<wchar_t> raw(static_cast<size_t>(length) + 1, L'\0'); GetWindowTextW(phrases_edit_, raw.data(), static_cast<int>(raw.size()));
  std::wstring section; const std::wstring input(raw.data()); size_t begin = 0;
  while (begin <= input.size()) {
    const size_t end = input.find_first_of(L"\r\n", begin); const std::wstring line = Trim(input.substr(begin, end == std::wstring::npos ? std::wstring::npos : end - begin)); const size_t separator = line.find(L'=');
    const std::wstring code = separator == std::wstring::npos ? std::wstring{} : Trim(line.substr(0, separator)); const std::wstring phrases = separator == std::wstring::npos ? std::wstring{} : Trim(line.substr(separator + 1));
    if (!code.empty() && !phrases.empty()) { section += code + L"=" + phrases; section.push_back(L'\0'); }
    if (end == std::wstring::npos) break; begin = input.find_first_not_of(L"\r\n", end); if (begin == std::wstring::npos) break;
  }
  section.push_back(L'\0'); WritePrivateProfileSectionW(L"Phrases", section.c_str(), path.c_str());
}
void SettingsWindow::ClearLearning() {
  if (MessageBoxW(hwnd_, L"清空本机的所有候选学习记录？常用短语不会受影响。", L"GY 输入法", MB_YESNO | MB_ICONQUESTION) != IDYES) return;
  const std::wstring path = SettingsPath(); if (EnsureUnicodeSettingsFile(path)) WritePrivateProfileStringW(L"Learning", nullptr, nullptr, path.c_str());
}
void SettingsWindow::ClearHistory() {
  // 确认文案逐字来自 CLIPBOARD-PAGE-DESIGN §2 卡片 3。
  if (MessageBoxW(hwnd_, L"清空本机剪贴板历史？不影响其他设备。", L"GY 输入法", MB_YESNO | MB_ICONQUESTION) != IDYES) return;
  gy::clipboard_history::Clear();
  history_entries_.clear();
  history_scroll_ = 0;
  InvalidateRect(hwnd_, nullptr, FALSE);
}
void SettingsWindow::ExportBackup() {
  const std::wstring source = SettingsPath(); if (source.empty() || !EnsureUnicodeSettingsFile(source)) return; std::wstring destination;
  if (!PickSettingsFile(hwnd_, true, &destination)) return;
  if (!CopyFileW(source.c_str(), destination.c_str(), FALSE)) MessageBoxW(hwnd_, L"无法导出设置文件。", L"GY 输入法", MB_OK | MB_ICONERROR);
}
void SettingsWindow::ImportBackup() {
  std::wstring source; if (!PickSettingsFile(hwnd_, false, &source)) return;
  if (!IsPortableSettingsFile(source)) { MessageBoxW(hwnd_, L"设置备份无效或过大。仅接受不超过 64 KB 的 GY 设置文件。", L"GY 输入法", MB_OK | MB_ICONWARNING); return; }
  const std::wstring destination = SettingsPath(); if (destination.empty() || !EnsureUnicodeSettingsFile(destination)) return;
  CopyFileW(destination.c_str(), (destination + L".bak").c_str(), FALSE);
  if (!CopyFileW(source.c_str(), destination.c_str(), FALSE)) { MessageBoxW(hwnd_, L"无法导入设置文件。原来的设置已保留。", L"GY 输入法", MB_OK | MB_ICONERROR); return; }
  const int imported_mode = static_cast<int>(GetPrivateProfileIntW(L"Input", L"Mode", gy::input_mode::kSimplified, destination.c_str()));
  gy::input_mode::Write(imported_mode);
  Load(); InvalidateRect(hwnd_, nullptr, TRUE);
}

LRESULT CALLBACK SettingsWindow::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<SettingsWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) { self = reinterpret_cast<SettingsWindow*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams); SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self)); }
  if (!self) return DefWindowProcW(hwnd, message, wparam, lparam);
  switch (message) {
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint{}; HDC dc = BeginPaint(hwnd, &paint); RECT client{}; GetClientRect(hwnd, &client);
      HDC buffer = CreateCompatibleDC(dc); HBITMAP bitmap = CreateCompatibleBitmap(dc, client.right, client.bottom);
      HGDIOBJ previous = SelectObject(buffer, bitmap);
      self->Paint(buffer);
      BitBlt(dc, 0, 0, client.right, client.bottom, buffer, 0, 0, SRCCOPY);
      SelectObject(buffer, previous); DeleteObject(bitmap); DeleteDC(buffer);
      EndPaint(hwnd, &paint); return 0;
    }
    case WM_CTLCOLOREDIT: {
      const Palette pal = PaletteForTheme(self->theme_);
      SetTextColor(reinterpret_cast<HDC>(wparam), pal.text);
      SetBkColor(reinterpret_cast<HDC>(wparam), pal.surface);
      return reinterpret_cast<LRESULT>(self->edit_brush_);
    }
    case WM_MOUSEMOVE: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      bool hand = self->Hit(self->done_rect_, point) || self->Hit(self->close_rect_, point);
      for (const RECT& rect : self->nav_rects_) hand = hand || self->Hit(rect, point);
      if (self->page_ == Page::General) hand = hand || self->Hit(self->phrases_rect_, point) || self->Hit(self->clear_rect_, point) || self->Hit(self->export_rect_, point) || self->Hit(self->import_rect_, point) || self->Hit(self->clip_sync_switch_, point) || self->Hit(self->clip_instant_switch_, point);
      if (self->page_ == Page::Input) { for (const RECT& rect : self->input_mode_rects_) hand = hand || self->Hit(rect, point); hand = hand || self->Hit(self->warm_rect_, point); }
      if (self->page_ == Page::Appearance) { for (const RECT& rect : self->theme_rects_) hand = hand || self->Hit(rect, point); for (const RECT& rect : self->size_rects_) hand = hand || self->Hit(rect, point); }
      if (self->page_ == Page::Clipboard) hand = hand || self->Hit(self->clip_history_clear_, point);
      SetCursor(LoadCursorW(nullptr, hand ? IDC_HAND : IDC_ARROW)); return 0;
    }
    case WM_SETCURSOR: {
      POINT point{}; GetCursorPos(&point); ScreenToClient(hwnd, &point);
      bool hand = self->Hit(self->done_rect_, point) || self->Hit(self->close_rect_, point);
      for (const RECT& rect : self->nav_rects_) hand = hand || self->Hit(rect, point);
      if (self->page_ == Page::General) hand = hand || self->Hit(self->phrases_rect_, point) || self->Hit(self->clear_rect_, point) || self->Hit(self->export_rect_, point) || self->Hit(self->import_rect_, point) || self->Hit(self->clip_sync_switch_, point) || self->Hit(self->clip_instant_switch_, point);
      if (self->page_ == Page::Input) { for (const RECT& rect : self->input_mode_rects_) hand = hand || self->Hit(rect, point); hand = hand || self->Hit(self->warm_rect_, point); }
      if (self->page_ == Page::Appearance) { for (const RECT& rect : self->theme_rects_) hand = hand || self->Hit(rect, point); for (const RECT& rect : self->size_rects_) hand = hand || self->Hit(rect, point); }
      if (self->page_ == Page::Clipboard) hand = hand || self->Hit(self->clip_history_clear_, point);
      if (hand) { SetCursor(LoadCursorW(nullptr, IDC_HAND)); return TRUE; } break;
    }
    case WM_LBUTTONUP: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      for (int i = 0; i < 5; ++i) if (self->Hit(self->nav_rects_[i], point)) { self->page_ = static_cast<Page>(i); self->Layout(); return 0; }
      if (self->page_ == Page::Input) for (int i = 0; i < 3; ++i) if (self->Hit(self->input_mode_rects_[i], point)) { self->input_mode_ = i; self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::Input && self->Hit(self->warm_rect_, point)) { self->warm_start_ = !self->warm_start_; self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::Appearance) for (int i = 0; i < 3; ++i) if (self->Hit(self->theme_rects_[i], point)) { self->theme_ = i; self->Save(); self->ApplyThemeBrush(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::Appearance) for (int i = 0; i < 3; ++i) if (self->Hit(self->size_rects_[i], point)) { self->size_index_ = i; self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      // 剪贴板开关在通用页：拨动即写入（不等“完成”）；剪贴板页只剩清空。
      if (self->page_ == Page::General && self->Hit(self->clip_sync_switch_, point)) { self->clip_enabled_ = !self->clip_enabled_; self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::General && self->Hit(self->clip_instant_switch_, point)) { self->clip_instant_ = !self->clip_instant_; self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::Clipboard && self->Hit(self->clip_history_clear_, point)) { self->ClearHistory(); return 0; }
      if (self->page_ == Page::General && self->Hit(self->phrases_rect_, point)) { self->TogglePhrases(); return 0; }
      if (self->page_ == Page::General && self->Hit(self->clear_rect_, point)) { self->ClearLearning(); return 0; }
      if (self->page_ == Page::General && self->Hit(self->export_rect_, point)) { self->Save(); self->ExportBackup(); return 0; }
      if (self->page_ == Page::General && self->Hit(self->import_rect_, point)) { self->ImportBackup(); return 0; }
      if (self->Hit(self->done_rect_, point)) { self->Save(); DestroyWindow(hwnd); return 0; }
      if (self->Hit(self->close_rect_, point)) { DestroyWindow(hwnd); return 0; }
      return 0;
    }    case WM_NCHITTEST: {
      const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      POINT client = point;
      ScreenToClient(hwnd, &client);
      // The close control lives in the visual header but must remain a real
      // client click; otherwise Windows treats it as a title-bar drag.
      if (self->Hit(self->close_rect_, client)) return HTCLIENT;
      if (client.y < Scale(self->dpi_, 76)) return HTCAPTION;
      break;
    }
    case WM_MOUSEWHEEL: {
      if (self->page_ != Page::Clipboard) break;
      const int entry_h = Scale(self->dpi_, 54);
      const int visible = std::max(1, static_cast<int>(self->clip_history_list_.bottom - self->clip_history_list_.top) / entry_h);
      const int max_scroll = std::max(0, static_cast<int>(self->history_entries_.size()) - visible);
      if (max_scroll == 0) return 0;
      const int step = 3;
      self->history_scroll_ = std::clamp(self->history_scroll_ + (GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? -step : step), 0, max_scroll);
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }
    case WM_DPICHANGED: {
      self->dpi_ = std::min<UINT>(HIWORD(wparam), kMaxSettingsDpi);
      const RECT* suggested = reinterpret_cast<const RECT*>(lparam);
      HMONITOR monitor = MonitorFromRect(suggested, MONITOR_DEFAULTTONEAREST);
      MONITORINFO info{sizeof(info)}; GetMonitorInfoW(monitor, &info);
      self->width_ = std::min(Scale(self->dpi_, 520), std::max(Scale(self->dpi_, 360), static_cast<int>(info.rcWork.right - info.rcWork.left) - Scale(self->dpi_, 32)));
      self->height_ = std::min(Scale(self->dpi_, 680), std::max(Scale(self->dpi_, 460), static_cast<int>(info.rcWork.bottom - info.rcWork.top) - Scale(self->dpi_, 32)));
      SetWindowPos(hwnd, nullptr, suggested->left, suggested->top, self->width_, self->height_, SWP_NOZORDER | SWP_NOACTIVATE);
      self->Layout(); return 0;
    }
    case WM_DESTROY: if (self->edit_brush_) { DeleteObject(self->edit_brush_); self->edit_brush_ = nullptr; } self->hwnd_ = nullptr; return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
