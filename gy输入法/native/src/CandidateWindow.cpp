#include "CandidateWindow.h"
#include "CandidateLayout.h"

#include <algorithm>
#include <iterator>
#include <windowsx.h>

namespace {
constexpr wchar_t kWindowClass[] = L"GyImeCandidateWindow";
constexpr COLORREF kBrandInk = RGB(17, 19, 24);       // Homepage black #111318
constexpr COLORREF kBrandPaper = RGB(250, 250, 248);  // Warm off-white
constexpr COLORREF kGyBlue = RGB(40, 99, 235);           // Candidate selection accent
constexpr COLORREF kDisclosureBlue = RGB(82, 128, 226);  // Quiet disclosure accent
constexpr int kDisclosureInsetX = 8;                         // Locked collapsed control anchor
constexpr int kDisclosureInsetBottom = 8;                    // Locked collapsed control anchor

int Scale(UINT dpi, int value) { return MulDiv(value, static_cast<int>(dpi), 96); }

UINT WindowDpi(HWND hwnd) {
  const UINT dpi = hwnd ? GetDpiForWindow(hwnd) : GetDpiForSystem();
  return dpi ? dpi : 96;
}

std::wstring SettingsPath() {
  wchar_t root[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", root, MAX_PATH)) return {};
  return std::wstring(root) + L"\\GYInput\\settings.ini";
}

bool IsSystemDark() {
  DWORD light = 1;
  DWORD size = sizeof(light);
  const LSTATUS status = RegGetValueW(HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size);
  return status == ERROR_SUCCESS && light == 0;
}

int CandidateStyle() {
  const std::wstring path = SettingsPath();
  return std::clamp(path.empty() ? 0 : static_cast<int>(GetPrivateProfileIntW(L"Appearance", L"Theme", 0, path.c_str())), 0, 2);
}

int CandidatePointSize() {
  const std::wstring path = SettingsPath();
  const int size = path.empty() ? 15 : static_cast<int>(GetPrivateProfileIntW(L"Appearance", L"CandidateSize", 15, path.c_str()));
  return std::clamp(size, 13, 17);
}

int CandidateInputMode() {
  const std::wstring path = SettingsPath();
  return std::clamp(path.empty() ? 0 : static_cast<int>(GetPrivateProfileIntW(L"Input", L"Mode", 0, path.c_str())), 0, 2);
}

const wchar_t* ModeLabel(int input_mode) {
  return input_mode == 1 ? L"繁" : input_mode == 2 ? L"EN" : L"简";
}

ATOM RegisterCandidateClass() {
  static const ATOM atom = [] {
    WNDCLASSEXW wc{sizeof(wc)};
    wc.style = CS_DROPSHADOW;
    wc.lpfnWndProc = CandidateWindow::WindowProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kWindowClass;
    return RegisterClassExW(&wc);
  }();
  return atom;
}

void Fill(HDC dc, const RECT& rect, COLORREF color) {
  const HBRUSH brush = CreateSolidBrush(color);
  FillRect(dc, &rect, brush);
  DeleteObject(brush);
}

void Text(HDC dc, const std::wstring& value, RECT rect, COLORREF color, UINT format, HFONT font,
          bool allow_ellipsis = true) {
  SelectObject(dc, font);
  SetTextColor(dc, color);
  DrawTextW(dc, value.c_str(), -1, &rect,
            format | DT_SINGLELINE | DT_VCENTER | (allow_ellipsis ? DT_END_ELLIPSIS : 0));
}

// The disclosure control is drawn as a fine, rounded chevron rather than a
// glyph so it stays balanced at every Windows DPI scale and font fallback.
void DrawDisclosureChevron(HDC dc, const RECT& rect, bool expanded, COLORREF color, UINT dpi) {
  // Position invariant: in the collapsed strip the disclosure stays at the
  // lower-left of its own cell, before the mode indicator. Style changes must
  // not alter these coordinates.
  const int center_x = expanded ? (rect.left + rect.right) / 2 : rect.left + Scale(dpi, kDisclosureInsetX);
  const int center_y = expanded ? (rect.top + rect.bottom) / 2 : rect.bottom - Scale(dpi, kDisclosureInsetBottom);
  const int half_width = Scale(dpi, 5);
  const int half_height = Scale(dpi, 3);
  LOGBRUSH brush{BS_SOLID, color, 0};
  const HPEN pen = ExtCreatePen(PS_GEOMETRIC | PS_SOLID | PS_ENDCAP_ROUND | PS_JOIN_ROUND,
                                std::max(1, Scale(dpi, 1)), &brush, 0, nullptr);
  const HGDIOBJ old_pen = SelectObject(dc, pen);
  POINT points[3]{};
  if (expanded) {
    points[0] = POINT{center_x - half_width, center_y + half_height};
    points[1] = POINT{center_x, center_y - half_height};
    points[2] = POINT{center_x + half_width, center_y + half_height};
  } else {
    points[0] = POINT{center_x - half_width, center_y - half_height};
    points[1] = POINT{center_x, center_y + half_height};
    points[2] = POINT{center_x + half_width, center_y - half_height};
  }
  Polyline(dc, points, 3);
  SelectObject(dc, old_pen);
  DeleteObject(pen);
}
int Measure(HDC dc, HFONT font, const std::wstring& text) {
  SelectObject(dc, font);
  SIZE size{};
  GetTextExtentPoint32W(dc, text.c_str(), static_cast<int>(text.size()), &size);
  return size.cx;
}

HFONT Font(UINT dpi, int points, int weight) {
  return CreateFontW(-Scale(dpi, points), 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                     OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                     DEFAULT_PITCH, L"Microsoft YaHei UI");
}

// Compact master wordmark, traced directly from the approved GY brand SVG.
void DrawGyWordmark(HDC dc, const RECT& bounds, COLORREF color) {
  const float sx = static_cast<float>(bounds.right - bounds.left) / 156.0f;
  const float sy = static_cast<float>(bounds.bottom - bounds.top) / 100.0f;
  const auto x = [&](float value) { return bounds.left + static_cast<int>(value * sx + 0.5f); };
  const auto y = [&](float value) { return bounds.top + static_cast<int>(value * sy + 0.5f); };
  const HBRUSH brush = CreateSolidBrush(color);
  const HGDIOBJ old_brush = SelectObject(dc, brush);

  BeginPath(dc);
  MoveToEx(dc, x(72), y(26), nullptr);
  POINT g[] = {{x(65), y(18)}, {x(54), y(13)}, {x(40), y(13)},
               {x(21), y(13)}, {x(8), y(28)}, {x(8), y(50)},
               {x(8), y(72)}, {x(21), y(87)}, {x(40), y(87)},
               {x(56), y(87)}, {x(68), y(77)}, {x(72), y(63)}};
  PolyBezierTo(dc, g, static_cast<DWORD>(std::size(g)));
  LineTo(dc, x(72), y(52));
  LineTo(dc, x(40), y(52));
  LineTo(dc, x(40), y(66));
  LineTo(dc, x(57), y(66));
  POINT g_tail[] = {{x(54), y(72)}, {x(48), y(74)}, {x(40), y(74)},
                    {x(28), y(74)}, {x(21), y(64)}, {x(21), y(50)},
                    {x(21), y(36)}, {x(28), y(26)}, {x(40), y(26)},
                    {x(49), y(26)}, {x(56), y(31)}, {x(60), y(37)}};
  PolyBezierTo(dc, g_tail, static_cast<DWORD>(std::size(g_tail)));
  LineTo(dc, x(72), y(26));
  CloseFigure(dc);
  EndPath(dc);
  FillPath(dc);

  BeginPath(dc);
  MoveToEx(dc, x(80), y(15), nullptr);
  LineTo(dc, x(94), y(15));
  LineTo(dc, x(114), y(50));
  LineTo(dc, x(134), y(15));
  LineTo(dc, x(148), y(15));
  LineTo(dc, x(121), y(60));
  LineTo(dc, x(121), y(87));
  LineTo(dc, x(107), y(87));
  LineTo(dc, x(107), y(60));
  LineTo(dc, x(80), y(15));
  CloseFigure(dc);
  EndPath(dc);
  FillPath(dc);

  SelectObject(dc, old_brush);
  DeleteObject(brush);
}}  // namespace

CandidateWindow::CandidateWindow(std::function<bool(unsigned)> choose, std::function<void(const RECT&)> open_settings)
    : choose_(std::move(choose)), open_settings_(std::move(open_settings)) {}
CandidateWindow::~CandidateWindow() { Hide(); }

void CandidateWindow::Layout(UINT dpi, int available_width) {
  dpi_ = dpi;
  candidate_rects_.clear();
  const int padding = Scale(dpi, 6);
  const int gap = Scale(dpi, 3);
  const int chip_height = Scale(dpi, candidate_point_size_ + 14);
  const int max_width = std::max(Scale(dpi, 180), available_width);
  const HFONT candidate_font = Font(dpi, candidate_point_size_, FW_SEMIBOLD);
  const HFONT status_font = Font(dpi, 12, FW_SEMIBOLD);
  HDC dc = GetDC(nullptr);

  const std::wstring mode_label = ModeLabel(input_mode_);
  const int mode_width = Measure(dc, status_font, mode_label) + Scale(dpi, 18);
  const int page_button_width = Scale(dpi, 26);
  const int page_indicator_width = Scale(dpi, 42);
  const int expand_width = Scale(dpi, 24);
  const bool expanded_grid = expanded_ && !mode_popup_;
  const unsigned capacity = expanded_grid ? kExpandedColumns * kExpandedMaxRows : kCandidatesPerPage;
  const unsigned visible_count = mode_popup_ || page_start_ >= candidates_.size() ? 0 : std::min<unsigned>(capacity,
      static_cast<unsigned>(candidates_.size()) - page_start_);
  const bool can_expand = !mode_popup_ && candidates_.size() > kCandidatesPerPage;
  int x = std::max(0, padding - 1);
  int right_edge = padding;
  const int non_word_width = Scale(dpi, 24);
  const int collapsed_controls = mode_popup_ ? 0 : mode_width + (can_expand ? gap + expand_width : 0);
  const int total_gap = gap * static_cast<int>(visible_count > 0 ? visible_count - 1 : 0);
  // Four Han characters are a normal Chinese word, not an overflow case. Grow
  // the compact row to fit that minimum before considering long-word clipping.
  const int four_character_word_width = Measure(dc, candidate_font, L"输入法候");
  const int word_room = std::max(four_character_word_width,
      std::max(Scale(dpi, 22),
          (max_width - x - padding - collapsed_controls - total_gap) /
              std::max(1, static_cast<int>(visible_count)) - non_word_width));

  if (expanded_grid) {
    grid_columns_ = expanded_column_target_;
  } else {
    grid_columns_ = kCandidatesPerPage;
  }
  // Expanded mode is a fixed five-column matrix. Do not shrink it to the
  // visible candidate count: six candidates must render as 5 + 1, never 3 x 2.
  const unsigned grid_columns = expanded_grid ? kExpandedColumns
                                              : std::min<unsigned>(grid_columns_, std::max(1u, visible_count));
  const int fitted_grid_cell_width = std::max(Scale(dpi, 54),
      (max_width - 2 * padding - gap * static_cast<int>(grid_columns - 1)) / static_cast<int>(grid_columns));
  // Keep the approved five-column geometry, but make the expanded matrix a
  // little denser on 13/14-inch screens. This only reduces horizontal air:
  // row rhythm, footer placement, disclosure-arrow geometry and VI colors
  // intentionally remain untouched.
  const int comfortable_grid_cell_width = Scale(dpi, grid_columns >= 6 ? 118 : grid_columns == 4 ? 102 : 110);
  // Five columns are locked, but cell width follows the widest candidate on
  // the current page: a page of single characters must not inherit the full
  // comfortable cell width and inflate the panel with empty air. The approved
  // comfortable width remains the ceiling; the compact minimum is the floor.
  const int grid_cell_cap = std::min(comfortable_grid_cell_width, fitted_grid_cell_width);
  int content_grid_cell_width = Scale(dpi, 54);
  if (expanded_grid) {
    const int cell_insets = Scale(dpi, 21) + Scale(dpi, 5) + Scale(dpi, 8);
    for (unsigned i = 0; i < visible_count; ++i) {
      content_grid_cell_width = std::max(content_grid_cell_width,
          Measure(dc, candidate_font, candidates_[page_start_ + i]) + cell_insets);
    }
  }
  const int grid_cell_width = expanded_grid
      ? std::clamp(content_grid_cell_width, (Scale(dpi, 54) + grid_cell_cap) / 2, grid_cell_cap)
      : fitted_grid_cell_width;
  // Candidate text is an input decision, not decoration: when the natural row
  // fits the panel cap, every chip gets its full measured width and nothing is
  // clipped. Only a genuinely overflowing row falls back to the shared
  // word_room cap, where Paint then marks the cut with an ellipsis instead of
  // silently dropping the tail of a long candidate.
  clip_overflow_ = false;
  if (visible_count > 0) {
    if (expanded_grid) {
      const int word_area = grid_cell_width - Scale(dpi, 21) - Scale(dpi, 5);
      for (unsigned i = 0; i < visible_count; ++i) {
        if (Measure(dc, candidate_font, candidates_[page_start_ + i]) > word_area) { clip_overflow_ = true; break; }
      }
    } else {
      int natural_width = x + total_gap + gap + collapsed_controls + padding;
      for (unsigned i = 0; i < visible_count; ++i) {
        natural_width += non_word_width + Measure(dc, candidate_font, candidates_[page_start_ + i]) + Scale(dpi, 8);
      }
      clip_overflow_ = natural_width > max_width;
    }
  }

  for (unsigned i = 0; i < visible_count; ++i) {
    const int measured_word_width = Measure(dc, candidate_font, candidates_[page_start_ + i]);
    const int word_width = clip_overflow_ ? std::min(measured_word_width, word_room) : measured_word_width;
    const int chip_width = expanded_grid ? grid_cell_width : non_word_width + word_width + Scale(dpi, 8);
    const unsigned row = expanded_grid ? i / grid_columns : 0;
    const unsigned column = expanded_grid ? i % grid_columns : 0;
    const int left = expanded_grid ? padding + static_cast<int>(column) * (chip_width + gap) : x;
    const int top = expanded_grid ? padding + static_cast<int>(row) * (chip_height + gap) : padding;
    candidate_rects_.push_back(RECT{left, top, left + chip_width, top + chip_height});
    if (!expanded_grid) x += chip_width + gap;
    right_edge = expanded_grid ? left + chip_width : std::max(right_edge, x - gap);
  }
  // A five-column grid owns all five columns even when the current page only
  // has one, six, or twenty candidates. Deriving the window width from the
  // final visible candidate clipped columns 4–5 whenever that candidate was
  // in an earlier column (for example 6 candidates used to look like 3 × 2).
  // Keep the fixed grid boundary independent from the candidate count.
  const int grid_right = expanded_grid
      ? gy::candidate_layout::GridRight(padding, grid_cell_width, gap, grid_columns)
      : right_edge;
  mode_rect_ = RECT{};
  previous_page_rect_ = RECT{};
  next_page_rect_ = RECT{};
  page_indicator_rect_ = RECT{};
  expand_rect_ = RECT{};
  if (!mode_popup_) {
    const int control_top = expanded_grid ? (candidate_rects_.empty() ? padding : candidate_rects_.back().bottom + gap) : padding;
    if (expanded_grid) {
      // Locked order: disclosure first, then mode label.
      expand_rect_ = RECT{padding, control_top, padding + expand_width, control_top + chip_height};
      const int mode_left = expand_rect_.right + gap;
      mode_rect_ = RECT{mode_left, control_top, mode_left + mode_width, control_top + chip_height};
      const bool has_more_pages = page_start_ > 0 || page_start_ + capacity < candidates_.size();
      if (has_more_pages) {
        const int next_left = grid_right - page_button_width;
        next_page_rect_ = RECT{next_left, control_top, next_left + page_button_width, control_top + chip_height};
        const int indicator_left = next_page_rect_.left - gap - page_indicator_width;
        page_indicator_rect_ = RECT{indicator_left, control_top, indicator_left + page_indicator_width, control_top + chip_height};
        const int previous_left = page_indicator_rect_.left - gap - page_button_width;
        previous_page_rect_ = RECT{previous_left, control_top, previous_left + page_button_width, control_top + chip_height};
      }
    } else {
      // Locked order: candidates → disclosure → divider → 中 / 繁 / EN.
      if (can_expand) {
        const int expand_left = right_edge + gap;
        expand_rect_ = RECT{expand_left, control_top, expand_left + expand_width, control_top + chip_height};
        right_edge = expand_rect_.right;
      }
      const int mode_left = right_edge + gap;
      mode_rect_ = RECT{mode_left, control_top, mode_left + mode_width, control_top + chip_height};
      right_edge = mode_rect_.right;
    }
  } else {
    mode_rect_ = RECT{padding, padding, padding + mode_width, padding + chip_height};
    right_edge = mode_rect_.right;
  }
  ReleaseDC(nullptr, dc);
  DeleteObject(candidate_font);
  DeleteObject(status_font);

  // Do not clamp a normal four-character candidate back into an ellipsis.
  content_width_ = expanded_grid ? grid_right + padding : std::max(Scale(dpi, 48), right_edge + padding);
  content_height_ = expanded_grid ? mode_rect_.bottom + padding : chip_height + 2 * padding;
  pinyin_rect_ = RECT{};
  candidate_strip_rect_ = RECT{0, 0, content_width_, content_height_};
}
void CandidateWindow::Show(const RECT& caret, const std::wstring& pinyin,
                            const std::vector<std::wstring>& candidates, unsigned selected,
                            unsigned page_start, int input_mode, bool expanded) {
  mode_popup_ = false;
  input_mode_ = std::clamp(input_mode, 0, 2);
  english_mode_ = input_mode_ == 2;
  // The TSF DLL owns the state. Never let Host-local click state override a
  // keyboard ↓ expansion requested by the active application.
  expanded_ = expanded;
  ShowInternal(caret, pinyin, candidates, selected, page_start);
}

void CandidateWindow::ShowInternal(const RECT& caret, const std::wstring& pinyin,
                                   const std::vector<std::wstring>& candidates, unsigned selected,
                                   unsigned page_start) {
  caret_rect_ = caret;
  if (hwnd_) KillTimer(hwnd_, 1);
  pinyin_ = pinyin;
  candidates_ = candidates;
  if (candidates_.empty() && !mode_popup_) return Hide();
  if (candidates_.empty()) {
    page_start_ = 0;
    selected_ = 0;
  } else {
    const unsigned page_size = expanded_ ? kExpandedColumns * kExpandedMaxRows : kCandidatesPerPage;
    const unsigned last_page = static_cast<unsigned>((candidates_.size() - 1) / page_size) * page_size;
    page_start_ = std::min(page_start, last_page);
    selected_ = std::min<unsigned>(selected, static_cast<unsigned>(candidates_.size() - 1));
    if (selected_ < page_start_ || selected_ >= page_start_ + page_size) {
      page_start_ = selected_ / page_size * page_size;
    }
  }
  candidate_point_size_ = CandidatePointSize();
  visual_style_ = CandidateStyle();
  dark_theme_ = visual_style_ != 1;

  MONITORINFO monitor_info{sizeof(monitor_info)};
  RECT work_area{caret.left, caret.top, caret.left + Scale(96, 520), caret.top + Scale(96, 60)};
  const HMONITOR monitor = MonitorFromRect(&caret, MONITOR_DEFAULTTONEAREST);
  if (monitor) GetMonitorInfoW(monitor, &monitor_info), work_area = monitor_info.rcWork;
  RegisterCandidateClass();
  const bool creating = !hwnd_;
  if (creating) {
    hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
                            kWindowClass, L"GY 输入法", WS_POPUP,
                            caret.left, caret.bottom, 1, 1, nullptr, nullptr,
                            GetModuleHandleW(nullptr), this);
    // Opaque windows preserve ClearType; layered alpha makes 175% text soft.
  }
  if (!hwnd_) return;
  // Never expose an unpainted 1x1 popup. It was responsible for the black
  // first frame on a cold candidate window.
  if (creating) SetWindowPos(hwnd_, HWND_TOPMOST, caret.left, caret.bottom, 1, 1, SWP_NOACTIVATE | SWP_NOREDRAW);
  const UINT dpi = WindowDpi(hwnd_);
  const int monitor_width = static_cast<int>(work_area.right - work_area.left);
  // Product rule: expanded candidates always use a fixed 5 × 5 grid. Screen
  // size may constrain total width, never the number of columns.
  expanded_column_target_ = kExpandedColumns;
  // Expanded mode must stay visually compact. The previous monitor-wide cap
  // made a 5 × 5 grid stretch across a large display after high-DPI scaling.
  // Keep five columns, but cap the panel at a comfortable physical width so
  // the confirmed GY layout is the same on laptop and desktop screens.
  const int monitor_available = std::max(Scale(dpi, 180), monitor_width - Scale(dpi, 20));
  const int compact_panel_cap = expanded_ ? Scale(dpi, 820) : Scale(dpi, 720);
  const int available_width = std::min(monitor_available, compact_panel_cap);
  Layout(dpi, available_width);
  const int width = content_width_;
  const int height = content_height_;
  int x = std::clamp(static_cast<int>(caret.left), static_cast<int>(work_area.left),
                     std::max(static_cast<int>(work_area.left), static_cast<int>(work_area.right) - width));
  int y = caret.bottom + Scale(dpi, 5);
  if (y + height > work_area.bottom && caret.top - height - Scale(dpi, 5) >= work_area.top) y = caret.top - height - Scale(dpi, 5);
  y = std::clamp(y, static_cast<int>(work_area.top),
                 std::max(static_cast<int>(work_area.top), static_cast<int>(work_area.bottom) - height));
  if (width != window_width_ || height != window_height_) {
    HRGN rounded = CreateRoundRectRgn(0, 0, width + 1, height + 1, Scale(dpi, 9), Scale(dpi, 9));
    SetWindowRgn(hwnd_, rounded, TRUE);
    window_width_ = width;
    window_height_ = height;
  }
  const bool visible = IsWindowVisible(hwnd_) != FALSE;
  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, width, height,
               SWP_NOACTIVATE | (visible ? SWP_NOREDRAW : SWP_SHOWWINDOW));
  RedrawWindow(hwnd_, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW);
}

void CandidateWindow::ShowMode(const RECT& caret, int input_mode) {
  mode_popup_ = true;
  input_mode_ = std::clamp(input_mode, 0, 2);
  english_mode_ = input_mode_ == 2;
  ShowInternal(caret, L"", {}, 0, 0);
  if (hwnd_) SetTimer(hwnd_, 1, 700, nullptr);
}
void CandidateWindow::OpenSettings() {
  if (!open_settings_ || !hwnd_) return;
  RECT anchor{};
  GetWindowRect(hwnd_, &anchor);
  open_settings_(anchor);
}
void CandidateWindow::Hide() {
  if (hwnd_) {
    KillTimer(hwnd_, 1);
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  mode_popup_ = false;
  expanded_ = false;
  window_width_ = 0;
  window_height_ = 0;
}

LRESULT CALLBACK CandidateWindow::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<CandidateWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = reinterpret_cast<CandidateWindow*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (!self) return DefWindowProcW(hwnd, message, 0, lparam);
  // This window belongs to the Host, not the target application.  Set the
  // pointer on both WM_SETCURSOR and WM_MOUSEMOVE so a busy cursor inherited
  // from a slow target app can never leak onto a selectable candidate.
  if ((message == WM_SETCURSOR && LOWORD(lparam) == HTCLIENT) || message == WM_MOUSEMOVE) {
    POINT point{};
    if (message == WM_MOUSEMOVE) {
      point = POINT{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    } else {
      GetCursorPos(&point);
      ScreenToClient(hwnd, &point);
    }
    const bool selectable = !self->mode_popup_ &&
        (PtInRect(&self->mode_rect_, point) ||
         (!IsRectEmpty(&self->previous_page_rect_) && PtInRect(&self->previous_page_rect_, point)) ||
         (!IsRectEmpty(&self->next_page_rect_) && PtInRect(&self->next_page_rect_, point)) ||
          (!IsRectEmpty(&self->expand_rect_) && PtInRect(&self->expand_rect_, point)) ||
         std::any_of(self->candidate_rects_.begin(), self->candidate_rects_.end(),
                     [&point](const RECT& rect) { return PtInRect(&rect, point); }));
    SetCursor(LoadCursorW(nullptr, selectable ? IDC_HAND : IDC_ARROW));
    if (message == WM_SETCURSOR) return TRUE;
  }
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_TIMER && wparam == 1) { self->Hide(); return 0; }
  if (message == WM_PAINT) {
    PAINTSTRUCT ps{};
    HDC dc = BeginPaint(hwnd, &ps); RECT client{}; GetClientRect(hwnd, &client);
    HDC buffer = CreateCompatibleDC(dc); HBITMAP bitmap = CreateCompatibleBitmap(dc, client.right, client.bottom);
    HGDIOBJ previous = SelectObject(buffer, bitmap);
    self->Paint(buffer);
    BitBlt(dc, 0, 0, client.right, client.bottom, buffer, 0, 0, SRCCOPY);
    SelectObject(buffer, previous); DeleteObject(bitmap); DeleteDC(buffer);
    EndPaint(hwnd, &ps);
    return 0;
  }
  if (message == WM_LBUTTONUP) {
    if (self->mode_popup_) return 0;
    const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    if (PtInRect(&self->mode_rect_, point)) {
      self->OpenSettings();
      return 0;
    }
    if (!IsRectEmpty(&self->previous_page_rect_) && PtInRect(&self->previous_page_rect_, point)) {
      self->choose_(self->expanded_ ? kPreviousExpandedPageAction : kPreviousPageAction);
      return 0;
    }
    if (!IsRectEmpty(&self->expand_rect_) && PtInRect(&self->expand_rect_, point)) {
      self->expanded_ = !self->expanded_;
      self->ShowInternal(self->caret_rect_, self->pinyin_, self->candidates_, self->selected_, self->page_start_);
      self->choose_(kToggleExpandedAction);
      return 0;
    }
    if (!IsRectEmpty(&self->next_page_rect_) && PtInRect(&self->next_page_rect_, point)) {
      self->choose_(self->expanded_ ? kNextExpandedPageAction : kNextPageAction);
      return 0;
    }
    for (unsigned i = 0; i < self->candidate_rects_.size(); ++i) {
      if (PtInRect(&self->candidate_rects_[i], point)) {
        if (self->choose_(self->page_start_ + i)) {
          self->expanded_ = false;
        }
        break;
      }
    }
    return 0;
  }
  return DefWindowProcW(hwnd, message, 0, lparam);
}

void CandidateWindow::Paint(HDC dc) {
  RECT client{};
  GetClientRect(hwnd_, &client);
  // Match the official GY surface: near-black, quiet neutral dividers, and
  // blue only for the active choice or an interactive affordance.
  const COLORREF background = visual_style_ == 0 ? kBrandInk : dark_theme_ ? kBrandInk : RGB(252, 252, 251);
  const COLORREF border = visual_style_ == 0 ? RGB(49, 53, 61) : dark_theme_ ? RGB(52, 57, 67) : RGB(225, 229, 235);
  const COLORREF muted = visual_style_ == 0 ? RGB(151, 157, 169) : dark_theme_ ? RGB(148, 158, 174) : RGB(96, 108, 122);
  const COLORREF text = dark_theme_ ? RGB(246, 248, 252) : kBrandInk;
  const COLORREF selected_background = visual_style_ == 2 ? RGB(72, 81, 96) : kGyBlue;
  const COLORREF selected_text = RGB(255, 255, 255);
  Fill(dc, client, background);
  const HPEN border_pen = CreatePen(PS_SOLID, 1, border);
  const HGDIOBJ old_pen = SelectObject(dc, border_pen);
  const HGDIOBJ old_brush = SelectObject(dc, GetStockObject(HOLLOW_BRUSH));
  RoundRect(dc, 0, 0, client.right, client.bottom, Scale(dpi_, 9), Scale(dpi_, 9));
  SelectObject(dc, old_pen);
  SelectObject(dc, old_brush);
  DeleteObject(border_pen);
  SetBkMode(dc, TRANSPARENT);

  const HFONT candidate_font = Font(dpi_, candidate_point_size_, FW_SEMIBOLD);
  const HFONT key_font = Font(dpi_, 10, FW_SEMIBOLD);
  const HFONT status_font = Font(dpi_, 12, FW_SEMIBOLD);
  Text(dc, ModeLabel(input_mode_), mode_rect_, kGyBlue, DT_CENTER, status_font);
  if (!mode_popup_ && !IsRectEmpty(&expand_rect_)) {
    const int divider = expand_rect_.right + Scale(dpi_, 1);
    Fill(dc, RECT{divider, expand_rect_.top + Scale(dpi_, 7), divider + 1,
                 expand_rect_.bottom - Scale(dpi_, 7)}, border);
  }
  for (unsigned i = 0; i < candidate_rects_.size(); ++i) {
    const unsigned candidate_index = page_start_ + i;
    const RECT chip_rect = candidate_rects_[i];
    const bool selected = candidate_index == selected_;
    if (selected) {
      const HBRUSH brush = CreateSolidBrush(selected_background);
      const HGDIOBJ old_candidate_brush = SelectObject(dc, brush);
      const HGDIOBJ old_candidate_pen = SelectObject(dc, GetStockObject(NULL_PEN));
      RoundRect(dc, chip_rect.left, chip_rect.top, chip_rect.right, chip_rect.bottom,
                Scale(dpi_, 6), Scale(dpi_, 6));
      SelectObject(dc, old_candidate_brush);
      SelectObject(dc, old_candidate_pen);
      DeleteObject(brush);
    }
    RECT key{chip_rect.left + Scale(dpi_, 6), chip_rect.top, chip_rect.left + Scale(dpi_, 19), chip_rect.bottom};
    const bool has_shortcut = !expanded_ || i < kCandidatesPerPage;
    Text(dc, has_shortcut ? std::to_wstring(i + 1) : L"", key, selected ? selected_text : muted, DT_CENTER, key_font);
    RECT word{chip_rect.left + Scale(dpi_, 21), chip_rect.top, chip_rect.right - Scale(dpi_, 5), chip_rect.bottom};
    // Candidate text is an input decision, not decorative copy. Never turn
    // it into “…”: Layout reserves enough room for the engine's bounded
    // phrases, and users can see exactly what Enter or its numeric shortcut
    // will commit. Ellipsis is the honest last resort for rows that physically
    // overflow the panel (clip_overflow_); Layout guarantees it never triggers
    // for candidates that fit.
    Text(dc, candidates_[candidate_index], word, selected ? selected_text : text, DT_LEFT, candidate_font, clip_overflow_);
  }

  if (!mode_popup_ && !IsRectEmpty(&next_page_rect_)) {
    const bool can_go_previous = page_start_ > 0;
    const unsigned page_size = expanded_ ? kExpandedColumns * kExpandedMaxRows : kCandidatesPerPage;
    const bool can_go_next = page_start_ + page_size < candidates_.size();
    const HFONT pager_font = Font(dpi_, 18, FW_SEMIBOLD);
    const unsigned page = page_start_ / page_size + 1;
    const unsigned pages = static_cast<unsigned>((candidates_.size() + page_size - 1) / page_size);
    Text(dc, L"↑", previous_page_rect_, can_go_previous ? kGyBlue : muted, DT_CENTER, pager_font);
    Text(dc, std::to_wstring(page) + L" / " + std::to_wstring(pages),
         page_indicator_rect_, muted, DT_CENTER, key_font);
    Text(dc, L"↓", next_page_rect_, can_go_next ? kGyBlue : muted, DT_CENTER, pager_font);
    DeleteObject(pager_font);
  }
  if (!mode_popup_ && !IsRectEmpty(&expand_rect_)) {
    DrawDisclosureChevron(dc, expand_rect_, expanded_, kDisclosureBlue, dpi_);
  }

  DeleteObject(candidate_font);
  DeleteObject(key_font);
  DeleteObject(status_font);
}




