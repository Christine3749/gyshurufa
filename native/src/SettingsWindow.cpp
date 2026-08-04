#include "SettingsWindow.h"
#include "InputMode.h"
#include "SettingsFile.h"

#include <algorithm>
#include <commdlg.h>
#include <windowsx.h>
#include <iterator>
#include <string>
#include <vector>

namespace {
constexpr wchar_t kClassName[] = L"GyImeSettingsWindow";
constexpr COLORREF kInk = RGB(16, 18, 22);
constexpr COLORREF kSurface = RGB(29, 33, 40);
constexpr COLORREF kSurfaceHover = RGB(35, 39, 47);
constexpr COLORREF kBorder = RGB(52, 58, 69);
constexpr COLORREF kWhite = RGB(250, 250, 251);
constexpr COLORREF kMuted = RGB(155, 163, 179);
constexpr COLORREF kBlue = RGB(43, 96, 221);
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
                          int selected, UINT dpi, HFONT font) {
  const RECT group{rects[0].left, rects[0].top, rects[2].right, rects[0].bottom};
  Rounded(dc, group, kSurface, kBorder, Scale(dpi, 9));
  for (int i = 0; i < 3; ++i) {
    if (i > 0) {
      const RECT divider{rects[i].left, group.top + Scale(dpi, 8),
                         rects[i].left + 1, group.bottom - Scale(dpi, 8)};
      Fill(dc, divider, kBorder);
    }
    if (i == selected) {
      RECT pill = rects[i];
      InflateRect(&pill, -Scale(dpi, 3), -Scale(dpi, 3));
      Rounded(dc, pill, kBlue, kBlue, Scale(dpi, 7));
    }
    Text(dc, labels[i], rects[i], kWhite, DT_CENTER, font);
  }
}

// The utility actions are stored as separate members for hit testing. Keep
// that storage explicit instead of relying on an invalid pointer cast.
void DrawSegmentedActions(HDC dc, const RECT& first, const RECT& second, const RECT& third,
                          const wchar_t* const labels[3], UINT dpi, HFONT font) {
  const RECT rects[] = {first, second, third};
  const RECT group{rects[0].left, rects[0].top, rects[2].right, rects[0].bottom};
  Rounded(dc, group, kSurface, kBorder, Scale(dpi, 9));
  for (int i = 0; i < 3; ++i) {
    if (i > 0) {
      const RECT divider{rects[i].left, group.top + Scale(dpi, 8),
                         rects[i].left + 1, group.bottom - Scale(dpi, 8)};
      Fill(dc, divider, kBorder);
    }
    Text(dc, labels[i], rects[i], kWhite, DT_CENTER, font);
  }
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
  const UINT fitting_dpi = static_cast<UINT>(std::max(80, MulDiv(std::max(1, work_height - 16), 96, 525)));
  dpi_ = std::min({native_dpi, fitting_dpi, kMaxSettingsDpi});
  width_ = std::min(Scale(dpi_, 520), std::max(Scale(dpi_, 320), work_width - Scale(dpi_, 16)));
  const int width = width_;
  const int height = std::min(Scale(dpi_, 525), std::max(Scale(dpi_, 360), work_height - Scale(dpi_, 16)));
  const int x = std::clamp(static_cast<int>(anchor.left), static_cast<int>(work.left) + Scale(dpi_, 8), static_cast<int>(work.right) - width - Scale(dpi_, 8));
  int y = anchor.top - height - Scale(dpi_, 12);
  if (y < work.top + Scale(dpi_, 8)) y = std::min(anchor.bottom + Scale(dpi_, 12), work.bottom - height - Scale(dpi_, 8));
  hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kClassName, L"GY 设置", WS_POPUP,
                          x, y, width, height, nullptr, nullptr, GetModuleHandleW(nullptr), this);
  if (!hwnd_) return;
  CreateControls();
  Load();
  Layout();
  RECT actual{}; GetWindowRect(hwnd_, &actual);
  const int final_width = actual.right - actual.left, final_height = actual.bottom - actual.top;
  const int final_x = std::clamp(x, static_cast<int>(work.left) + Scale(dpi_, 8), std::max(static_cast<int>(work.left) + Scale(dpi_, 8), static_cast<int>(work.right) - final_width - Scale(dpi_, 8)));
  const int final_y = std::clamp(y, static_cast<int>(work.top) + Scale(dpi_, 8), std::max(static_cast<int>(work.top) + Scale(dpi_, 8), static_cast<int>(work.bottom) - final_height - Scale(dpi_, 8)));
  SetWindowPos(hwnd_, HWND_TOPMOST, final_x, final_y, final_width, final_height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
  RedrawWindow(hwnd_, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW);
  SetFocus(account_edit_);
}

void SettingsWindow::CreateControls() {
  edit_brush_ = CreateSolidBrush(kSurface);
  account_edit_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | WS_TABSTOP,
      0, 0, 0, 0, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
  phrases_edit_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL | WS_TABSTOP,
      0, 0, 0, 0, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
  const HFONT font = Font(dpi_, 12, FW_NORMAL);
  SendMessageW(account_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  SendMessageW(phrases_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  // The edit controls retain their UI font for the lifetime of this Host.
}

void SettingsWindow::Layout() {
  if (!hwnd_) return;
  const int pad = Scale(dpi_, 32), width = width_;
  const int card_width = width - pad * 2;
  const int account_height = Scale(dpi_, 52), group_height = Scale(dpi_, 42);
  int y = Scale(dpi_, 100);
  account_rect_ = {pad, y, pad + card_width, y + account_height};
  MoveWindow(account_edit_, account_rect_.left + Scale(dpi_, 142), account_rect_.top + Scale(dpi_, 12),
             std::max(Scale(dpi_, 120), card_width - Scale(dpi_, 158)), Scale(dpi_, 27), TRUE);
  y += account_height + Scale(dpi_, 28);
  const int option_width = card_width / 3;
  for (int i = 0; i < 3; ++i) input_mode_rects_[i] = {pad + i * option_width, y, pad + (i + 1) * option_width, y + group_height};
  y += group_height + Scale(dpi_, 16);
  for (int i = 0; i < 3; ++i) theme_rects_[i] = {pad + i * option_width, y, pad + (i + 1) * option_width, y + group_height};
  y += group_height + Scale(dpi_, 16);
  for (int i = 0; i < 3; ++i) size_rects_[i] = {pad + i * option_width, y, pad + (i + 1) * option_width, y + group_height};
  y += group_height + Scale(dpi_, 18);
  phrases_rect_ = {pad, y, pad + card_width, y + (phrases_expanded_ ? Scale(dpi_, 132) : Scale(dpi_, 58))};
  MoveWindow(phrases_edit_, phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 45),
             card_width - Scale(dpi_, 32), Scale(dpi_, 75), TRUE);
  ShowWindow(phrases_edit_, phrases_expanded_ ? SW_SHOW : SW_HIDE);
  y = phrases_rect_.bottom + Scale(dpi_, 14);
  clear_rect_ = {pad, y, pad + option_width, y + group_height};
  export_rect_ = {pad + option_width, y, pad + option_width * 2, y + group_height};
  import_rect_ = {pad + option_width * 2, y, pad + card_width, y + group_height};
  y += Scale(dpi_, 64);
  done_rect_ = {width - pad - Scale(dpi_, 110), y, width - pad, y + Scale(dpi_, 42)};
  close_rect_ = {width - Scale(dpi_, 48), Scale(dpi_, 18), width - Scale(dpi_, 18), Scale(dpi_, 48)};
  const int height = done_rect_.bottom + Scale(dpi_, 20);
  RECT window{}; GetWindowRect(hwnd_, &window);
  SetWindowPos(hwnd_, nullptr, 0, 0, width, height, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
  const HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1, Scale(dpi_, 14), Scale(dpi_, 14));
  SetWindowRgn(hwnd_, region, FALSE);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

bool SettingsWindow::Hit(const RECT& rect, POINT point) const { return !IsRectEmpty(&rect) && PtInRect(&rect, point); }
void SettingsWindow::TogglePhrases() { phrases_expanded_ = !phrases_expanded_; Layout(); }

void SettingsWindow::Paint(HDC dc) {
  RECT client{}; GetClientRect(hwnd_, &client);
  Fill(dc, client, kInk);
  const HPEN outline = CreatePen(PS_SOLID, 1, kBorder);
  const HGDIOBJ old_pen = SelectObject(dc, outline); const HGDIOBJ old_brush = SelectObject(dc, GetStockObject(HOLLOW_BRUSH));
  RoundRect(dc, 0, 0, client.right, client.bottom, Scale(dpi_, 14), Scale(dpi_, 14));
  SelectObject(dc, old_pen); SelectObject(dc, old_brush); DeleteObject(outline);
  const HFONT title = Font(dpi_, 17, FW_SEMIBOLD), body = Font(dpi_, 11, FW_NORMAL), medium = Font(dpi_, 11, FW_SEMIBOLD), tiny = Font(dpi_, 10, FW_NORMAL);
  DrawGyWordmark(dc, RECT{Scale(dpi_, 24), Scale(dpi_, 25), Scale(dpi_, 76), Scale(dpi_, 58)}, kWhite);
  Text(dc, L"输入法设置", RECT{Scale(dpi_, 90), Scale(dpi_, 23), Scale(dpi_, 250), Scale(dpi_, 56)}, kWhite, DT_LEFT, title);
  Text(dc, L"所有内容仅保存在本机", RECT{Scale(dpi_, 90), Scale(dpi_, 52), Scale(dpi_, 270), Scale(dpi_, 72)}, kMuted, DT_LEFT, tiny);
  Text(dc, L"×", close_rect_, kMuted, DT_CENTER, title);

  Rounded(dc, account_rect_, kSurface, kBorder, Scale(dpi_, 9));
  Text(dc, L"账号", RECT{account_rect_.left + Scale(dpi_, 16), account_rect_.top + Scale(dpi_, 5), account_rect_.left + Scale(dpi_, 130), account_rect_.bottom - Scale(dpi_, 8)}, kWhite, DT_LEFT, medium);
  Text(dc, L"本地标识", RECT{account_rect_.left + Scale(dpi_, 16), account_rect_.top + Scale(dpi_, 25), account_rect_.left + Scale(dpi_, 130), account_rect_.bottom}, kMuted, DT_LEFT, tiny);
  Text(dc, L"输入语言", RECT{input_mode_rects_[0].left, input_mode_rects_[0].top - Scale(dpi_, 22), input_mode_rects_[2].right, input_mode_rects_[0].top - Scale(dpi_, 3)}, kMuted, DT_LEFT, tiny);
  const wchar_t* input_modes[] = {L"简体", L"繁体", L"EN"};
  DrawSegmentedChoices(dc, input_mode_rects_, input_modes, input_mode_, dpi_, medium);

  Text(dc, L"候选窗样式", RECT{theme_rects_[0].left, theme_rects_[0].top - Scale(dpi_, 22), theme_rects_[2].right, theme_rects_[0].top - Scale(dpi_, 3)}, kMuted, DT_LEFT, tiny);
  const wchar_t* themes[] = {L"GY 蓝夜", L"暖白", L"石墨"};
  DrawSegmentedChoices(dc, theme_rects_, themes, theme_, dpi_, medium);
  Text(dc, L"候选字大小", RECT{size_rects_[0].left, size_rects_[0].top - Scale(dpi_, 22), size_rects_[2].right, size_rects_[0].top - Scale(dpi_, 3)}, kMuted, DT_LEFT, tiny);
  const wchar_t* sizes[] = {L"紧凑", L"默认", L"大"};
  DrawSegmentedChoices(dc, size_rects_, sizes, size_index_, dpi_, medium);
  Rounded(dc, phrases_rect_, kSurface, kBorder, Scale(dpi_, 9));
  Text(dc, L"常用短语", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 8), phrases_rect_.left + Scale(dpi_, 190), phrases_rect_.top + Scale(dpi_, 32)}, kWhite, DT_LEFT, medium);
  Text(dc, phrases_expanded_ ? L"完成编辑" : L"管理 ›", RECT{phrases_rect_.right - Scale(dpi_, 100), phrases_rect_.top + Scale(dpi_, 8), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 32)}, kBlue, DT_RIGHT, medium);
  if (!phrases_expanded_) Text(dc, L"例如：dz=地址|电子邮箱", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 31), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.bottom - Scale(dpi_, 7)}, kMuted, DT_LEFT, tiny);

  const wchar_t* tools[] = {L"清空学习", L"导出", L"导入"};
  DrawSegmentedActions(dc, clear_rect_, export_rect_, import_rect_, tools, dpi_, medium);
  Rounded(dc, done_rect_, kBlue, kBlue, Scale(dpi_, 8));
  Text(dc, L"完成", done_rect_, kWhite, DT_CENTER, medium);
  Text(dc, L"Shift 快速切换 EN · 上方可切换简体、繁体或 EN", RECT{Scale(dpi_, 32), done_rect_.top, done_rect_.left - Scale(dpi_, 16), done_rect_.bottom}, kMuted, DT_LEFT, tiny);
  DeleteObject(title); DeleteObject(body); DeleteObject(medium); DeleteObject(tiny);
}

void SettingsWindow::Load() {
  input_mode_ = gy::input_mode::Read();
  const std::wstring path = SettingsPath(); if (path.empty()) return;
  wchar_t account[128]{}; GetPrivateProfileStringW(L"Account", L"Name", L"", account, static_cast<DWORD>(std::size(account)), path.c_str());
  SetWindowTextW(account_edit_, account);
  theme_ = std::clamp(static_cast<int>(GetPrivateProfileIntW(L"Appearance", L"Theme", 0, path.c_str())), 0, 2);
  const int points = GetPrivateProfileIntW(L"Appearance", L"CandidateSize", 15, path.c_str());
  size_index_ = points <= 13 ? 0 : points >= 17 ? 2 : 1;

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
    case WM_CTLCOLOREDIT: SetTextColor(reinterpret_cast<HDC>(wparam), kWhite); SetBkColor(reinterpret_cast<HDC>(wparam), kSurface); return reinterpret_cast<LRESULT>(self->edit_brush_);
    case WM_MOUSEMOVE: { POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)}; const bool hand = self->Hit(self->input_mode_rects_[0], point) || self->Hit(self->input_mode_rects_[1], point) || self->Hit(self->input_mode_rects_[2], point) || self->Hit(self->theme_rects_[0], point) || self->Hit(self->theme_rects_[1], point) || self->Hit(self->theme_rects_[2], point) || self->Hit(self->size_rects_[0], point) || self->Hit(self->size_rects_[1], point) || self->Hit(self->size_rects_[2], point) || self->Hit(self->phrases_rect_, point) || self->Hit(self->clear_rect_, point) || self->Hit(self->export_rect_, point) || self->Hit(self->import_rect_, point) || self->Hit(self->done_rect_, point) || self->Hit(self->close_rect_, point); SetCursor(LoadCursorW(nullptr, hand ? IDC_HAND : IDC_ARROW)); return 0; }
    case WM_SETCURSOR: { POINT point{}; GetCursorPos(&point); ScreenToClient(hwnd, &point); if (self->Hit(self->input_mode_rects_[0], point) || self->Hit(self->input_mode_rects_[1], point) || self->Hit(self->input_mode_rects_[2], point) || self->Hit(self->theme_rects_[0], point) || self->Hit(self->theme_rects_[1], point) || self->Hit(self->theme_rects_[2], point) || self->Hit(self->size_rects_[0], point) || self->Hit(self->size_rects_[1], point) || self->Hit(self->size_rects_[2], point) || self->Hit(self->phrases_rect_, point) || self->Hit(self->clear_rect_, point) || self->Hit(self->export_rect_, point) || self->Hit(self->import_rect_, point) || self->Hit(self->done_rect_, point) || self->Hit(self->close_rect_, point)) { SetCursor(LoadCursorW(nullptr, IDC_HAND)); return TRUE; } break; }
    case WM_LBUTTONUP: { POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)}; for (int i = 0; i < 3; ++i) if (self->Hit(self->input_mode_rects_[i], point)) { self->input_mode_ = i; self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; } for (int i = 0; i < 3; ++i) if (self->Hit(self->theme_rects_[i], point)) { self->theme_ = i; InvalidateRect(hwnd, nullptr, FALSE); return 0; } for (int i = 0; i < 3; ++i) if (self->Hit(self->size_rects_[i], point)) { self->size_index_ = i; InvalidateRect(hwnd, nullptr, FALSE); return 0; } if (self->Hit(self->phrases_rect_, point)) { self->TogglePhrases(); return 0; } if (self->Hit(self->clear_rect_, point)) { self->ClearLearning(); return 0; } if (self->Hit(self->export_rect_, point)) { self->Save(); self->ExportBackup(); return 0; } if (self->Hit(self->import_rect_, point)) { self->ImportBackup(); return 0; } if (self->Hit(self->done_rect_, point)) { self->Save(); DestroyWindow(hwnd); return 0; } if (self->Hit(self->close_rect_, point)) { DestroyWindow(hwnd); return 0; } return 0; }
    case WM_NCHITTEST: { const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)}; POINT client = point; ScreenToClient(hwnd, &client); if (client.y < Scale(self->dpi_, 76)) return HTCAPTION; break; }
    case WM_DPICHANGED: { self->dpi_ = std::min<UINT>(HIWORD(wparam), kMaxSettingsDpi); const RECT* suggested = reinterpret_cast<const RECT*>(lparam); SetWindowPos(hwnd, nullptr, suggested->left, suggested->top, suggested->right - suggested->left, suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE); self->Layout(); return 0; }
    case WM_DESTROY: if (self->edit_brush_) { DeleteObject(self->edit_brush_); self->edit_brush_ = nullptr; } self->hwnd_ = nullptr; return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}