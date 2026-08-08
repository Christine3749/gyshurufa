#include "SettingsWindow.h"
#include "GyAccountAuth.h"
#include "GyKeepSync.h"
#include "InputMode.h"
#include "ClipboardHistory.h"
#include "SettingsFile.h"

#include <algorithm>
#include <commdlg.h>
#include <commctrl.h>
#include <objbase.h>
#include <objidl.h>
#include <gdiplus.h>
#include <shellapi.h>
#include <cstdint>
#include <ctime>
#include <windowsx.h>
#include <iterator>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>
#ifndef GY_RELEASE_VERSION
#define GY_RELEASE_VERSION "dev"
#endif

namespace {
constexpr wchar_t kClassName[] = L"GyImeSettingsWindow";
constexpr UINT kAccountRequestComplete = WM_APP + 0x2A1;
constexpr UINT kUpdateMaintenanceComplete = WM_APP + 0x2A2;
constexpr UINT_PTR kClipboardStatusTimer = 0x4759;

struct AccountRequestCompletion {
  std::uint64_t window_instance_id = 0;
  std::uint64_t request_id = 0;
  gy::account_auth::Result result;
};

struct UpdateMaintenanceCompletion {
  std::uint64_t window_instance_id = 0;
  DWORD exit_code = ERROR_GEN_FAILURE;
  bool rollback = false;
};

void SecureErase(std::wstring* value) {
  if (!value || value->empty()) return;
  SecureZeroMemory(value->data(), value->size() * sizeof(wchar_t));
  value->clear();
}

void SecureEraseAccountResult(gy::account_auth::Result* result) {
  if (!result) return;
  SecureErase(&result->session.access_token);
  SecureErase(&result->session.refresh_token);
  result->session.email.clear();
  result->session.expires_at = 0;
}

std::wstring EditText(HWND edit) {
  const int length = edit ? GetWindowTextLengthW(edit) : 0;
  if (length <= 0) return {};
  std::wstring value(static_cast<size_t>(length) + 1, L'\0');
  GetWindowTextW(edit, value.data(), length + 1);
  value.resize(static_cast<size_t>(length));
  return value;
}

void PostAccountCompletion(HWND hwnd, std::uint64_t window_instance_id, std::uint64_t request_id,
                           gy::account_auth::Result result) {
  auto* completion = new AccountRequestCompletion{window_instance_id, request_id, std::move(result)};
  if (!PostMessageW(hwnd, kAccountRequestComplete, 0, reinterpret_cast<LPARAM>(completion))) {
    SecureEraseAccountResult(&completion->result);
    delete completion;
  }
}

bool SameClipboardEntries(const std::vector<gy::clipboard_history::Entry>& left,
                          const std::vector<gy::clipboard_history::Entry>& right) {
  if (left.size() != right.size()) return false;
  for (size_t index = 0; index < left.size(); ++index) {
    const auto& a = left[index];
    const auto& b = right[index];
    if (a.id != b.id || a.pending_upload != b.pending_upload ||
        a.sync_sequence != b.sync_sequence || a.kind != b.kind ||
        a.unix_time != b.unix_time) return false;
  }
  return true;
}

// The settings window follows the candidate-window theme (Appearance\Theme):
// one choice, one palette. GY Blue stays constant across themes because it is
// the VI-locked selection color, and text on accent pills stays near-white.
constexpr COLORREF kBlue = RGB(43, 96, 221);
constexpr COLORREF kOnAccent = RGB(250, 250, 251);

struct Palette {
  COLORREF ink;            // window background
  COLORREF surface;        // card background
  COLORREF surface_alt;    // zebra row: same hue, one whisper lighter/darker
  COLORREF surface_hover;  // selected card background
  COLORREF border;
  COLORREF text;           // primary text
  COLORREF muted;          // secondary text
};

Palette PaletteForTheme(int theme) {
  switch (theme) {
    case 1:  // 暖白: warm light surface matching the candidate strip swatch.
      return {RGB(243, 241, 235), RGB(252, 251, 248), RGB(238, 235, 227), RGB(234, 231, 224), RGB(208, 203, 193), RGB(26, 27, 30), RGB(122, 120, 113)};
    case 2:  // 石墨: neutral graphite without the blue-night cast.
      return {RGB(21, 23, 28), RGB(30, 33, 40), RGB(46, 51, 60), RGB(36, 40, 48), RGB(54, 59, 70), RGB(244, 245, 247), RGB(148, 154, 168)};
    default:  // GY 蓝夜: the original dark palette.
      return {RGB(16, 18, 22), RGB(29, 33, 40), RGB(46, 51, 60), RGB(35, 39, 47), RGB(52, 58, 69), RGB(250, 250, 251), RGB(155, 163, 179)};
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

COLORREF Mix(COLORREF a, COLORREF b, int pct_b) {
  const int r = GetRValue(a) + (GetRValue(b) - GetRValue(a)) * pct_b / 100;
  const int g = GetGValue(a) + (GetGValue(b) - GetGValue(a)) * pct_b / 100;
  const int bl = GetBValue(a) + (GetBValue(b) - GetBValue(a)) * pct_b / 100;
  return RGB(r, g, bl);
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

// Clipboard cards: the content owns as many lines as it needs, capped at four.
// One wrap engine serves measuring (Layout) and painting, so both always agree.
constexpr int kClipboardCardMaxLines = 4;
struct WrappedCard {
  std::vector<std::wstring> lines;
  bool overflow = false;
};
WrappedCard WrapCardText(HDC dc, const std::wstring& value, HFONT font, int max_width) {
  const HGDIOBJ previous = SelectObject(dc, font);
  std::wstring text = value;
  for (auto& ch : text) { if (ch < 32) ch = L' '; }
  WrappedCard out;
  size_t pos = 0;
  while (pos < text.size() && static_cast<int>(out.lines.size()) < kClipboardCardMaxLines) {
    SIZE size{};
    size_t fit = pos, last_space = std::wstring::npos;
    for (size_t i = pos; i < text.size(); ++i) {
      GetTextExtentPoint32W(dc, text.c_str() + pos, static_cast<int>(i - pos + 1), &size);
      if (size.cx > max_width) break;
      fit = i + 1;
      if (text[i] == L' ') last_space = i;
    }
    if (fit == pos) fit = pos + 1;  // never stall on a narrow run
    const bool last_allowed = static_cast<int>(out.lines.size()) + 1 == kClipboardCardMaxLines;
    if (fit < text.size() && !last_allowed && last_space != std::wstring::npos && last_space > pos) {
      fit = last_space;  // do not split a Latin word when another line follows
    }
    out.lines.push_back(text.substr(pos, fit - pos));
    pos = fit;
    while (pos < text.size() && text[pos] == L' ') ++pos;
  }
  out.overflow = pos < text.size();
  SelectObject(dc, previous);
  return out;
}
int ClipboardCardHeight(UINT dpi, int lines) {
  return Scale(dpi, 8) + lines * Scale(dpi, 18) + (lines - 1) * Scale(dpi, 7) +
         Scale(dpi, 8) + Scale(dpi, 15) + Scale(dpi, 7);
}

void PostUpdateMaintenanceCompletion(HWND hwnd, std::uint64_t window_instance_id, DWORD exit_code, bool rollback) {
  auto* completion = new UpdateMaintenanceCompletion{window_instance_id, exit_code, rollback};
  if (!PostMessageW(hwnd, kUpdateMaintenanceComplete, 0, reinterpret_cast<LPARAM>(completion))) {
    delete completion;
  }
}
int ClipboardImageCardHeight(UINT dpi) {
  return Scale(dpi, 8) + Scale(dpi, 72) + Scale(dpi, 8) + Scale(dpi, 15) + Scale(dpi, 7);
}

ULONG_PTR SettingsGdiPlusToken() {
  static const ULONG_PTR token = []() {
    Gdiplus::GdiplusStartupInput startup{};
    ULONG_PTR value = 0;
    return Gdiplus::GdiplusStartup(&value, &startup, nullptr) == Gdiplus::Ok
        ? value : static_cast<ULONG_PTR>(0);
  }();
  return token;
}

HBITMAP DecodeClipboardThumbnail(const gy::clipboard_history::Entry& entry, int max_width,
                                 int max_height, SIZE* size) {
  if (!size || entry.kind != gy::clipboard_history::EntryKind::PngImage ||
      max_width <= 0 || max_height <= 0 || !SettingsGdiPlusToken()) return nullptr;
  size->cx = 0;
  size->cy = 0;
  std::string png;
  if (!gy::clipboard_history::ReadImagePng(entry, &png) || png.empty()) return nullptr;
  IStream* stream = nullptr;
  if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) != S_OK) {
    std::fill(png.begin(), png.end(), '\0');
    return nullptr;
  }
  ULONG written = 0;
  const bool written_all = stream->Write(png.data(), static_cast<ULONG>(png.size()), &written) == S_OK &&
      written == png.size();
  std::fill(png.begin(), png.end(), '\0');
  png.clear();
  LARGE_INTEGER zero{};
  if (!written_all || stream->Seek(zero, STREAM_SEEK_SET, nullptr) != S_OK) {
    stream->Release();
    return nullptr;
  }
  Gdiplus::Image source(stream, FALSE);
  const UINT source_width = source.GetWidth();
  const UINT source_height = source.GetHeight();
  if (source.GetLastStatus() != Gdiplus::Ok || source_width == 0 || source_height == 0) {
    stream->Release();
    return nullptr;
  }
  const double scale = std::min(static_cast<double>(max_width) / source_width,
                                static_cast<double>(max_height) / source_height);
  const int width = std::max(1, static_cast<int>(source_width * scale + 0.5));
  const int height = std::max(1, static_cast<int>(source_height * scale + 0.5));
  Gdiplus::Bitmap thumbnail(width, height, PixelFormat32bppPARGB);
  Gdiplus::Graphics graphics(&thumbnail);
  graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
  graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
  const bool drawn = thumbnail.GetLastStatus() == Gdiplus::Ok &&
      graphics.DrawImage(&source, Gdiplus::Rect(0, 0, width, height), 0, 0,
                         source_width, source_height, Gdiplus::UnitPixel) == Gdiplus::Ok;
  HBITMAP bitmap = nullptr;
  const bool copied = drawn && thumbnail.GetHBITMAP(Gdiplus::Color(255, 255, 255, 255), &bitmap) == Gdiplus::Ok && bitmap;
  stream->Release();
  if (!copied) return nullptr;
  size->cx = width;
  size->cy = height;
  return bitmap;
}

void DrawClipboardThumbnail(HDC dc, HBITMAP bitmap, const SIZE& size, const RECT& bounds) {
  if (!bitmap || size.cx <= 0 || size.cy <= 0) return;
  HDC image_dc = CreateCompatibleDC(dc);
  if (!image_dc) return;
  const HGDIOBJ previous = SelectObject(image_dc, bitmap);
  const int bounds_width = static_cast<int>(bounds.right - bounds.left);
  const int bounds_height = static_cast<int>(bounds.bottom - bounds.top);
  const int image_width = static_cast<int>(size.cx);
  const int image_height = static_cast<int>(size.cy);
  const int x = static_cast<int>(bounds.left) + std::max(0, (bounds_width - image_width) / 2);
  const int y = static_cast<int>(bounds.top) + std::max(0, (bounds_height - image_height) / 2);
  BitBlt(dc, x, y, image_width, image_height, image_dc, 0, 0, SRCCOPY);
  SelectObject(image_dc, previous);
  DeleteDC(image_dc);
}
void DrawCardText(HDC dc, const WrappedCard& card, RECT rect, COLORREF color, HFONT font,
                  int line_height, int line_gap) {
  const HGDIOBJ previous = SelectObject(dc, font);
  SetTextColor(dc, color);
  SetBkMode(dc, TRANSPARENT);
  int y = rect.top;
  for (size_t i = 0; i < card.lines.size(); ++i) {
    UINT flags = DT_LEFT | DT_SINGLELINE | DT_NOPREFIX;
    if (card.overflow && i + 1 == card.lines.size()) flags |= DT_END_ELLIPSIS;
    RECT line_rect{rect.left, y, rect.right, y + line_height};
    DrawTextW(dc, card.lines[i].c_str(), -1, &line_rect, flags);
    y += line_height + line_gap;
  }
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

std::wstring WidenAscii(const char* value) {
  if (!value || !*value) return {};
  const int length = MultiByteToWideChar(CP_ACP, 0, value, -1, nullptr, 0);
  if (length <= 1) return {};
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_ACP, 0, value, -1, result.data(), length);
  result.resize(static_cast<size_t>(length - 1));
  return result;
}
std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, static_cast<DWORD>(std::size(path)));
  if (length == 0 || length >= std::size(path)) return {};
  std::wstring full(path, length);
  const size_t slash = full.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring{} : full.substr(0, slash);
}
std::wstring ReadRegisteredVersion() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\GYInput", 0,
                    KEY_READ | KEY_WOW64_64KEY, &key) != ERROR_SUCCESS) return {};
  wchar_t value[64]{};
  DWORD type = 0, bytes = sizeof(value);
  const LONG status = RegQueryValueExW(key, L"HostVersion", nullptr, &type,
                                       reinterpret_cast<LPBYTE>(value), &bytes);
  RegCloseKey(key);
  return status == ERROR_SUCCESS && (type == REG_SZ || type == REG_EXPAND_SZ)
             ? Trim(value) : std::wstring{};
}

std::wstring ReadRegisteredPath(const wchar_t* subkey, const wchar_t* value_name) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, subkey, 0, KEY_READ | KEY_WOW64_64KEY, &key) != ERROR_SUCCESS) return {};
  wchar_t value[1024]{};
  DWORD type = 0, bytes = sizeof(value);
  const LONG status = RegQueryValueExW(key, value_name, nullptr, &type,
                                       reinterpret_cast<LPBYTE>(value), &bytes);
  RegCloseKey(key);
  return status == ERROR_SUCCESS && (type == REG_SZ || type == REG_EXPAND_SZ)
             ? Trim(value) : std::wstring{};
}

std::wstring ReadRegisteredDllVersion() {
  const std::wstring path = ReadRegisteredPath(
      L"SOFTWARE\\Classes\\CLSID\\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\\InprocServer32", L"");
  const std::wstring marker = L"\\tsf-";
  const size_t begin = path.find(marker);
  const size_t end = begin == std::wstring::npos ? std::wstring::npos : path.find(L"\\GyIme.dll", begin + marker.size());
  return begin == std::wstring::npos || end == std::wstring::npos
             ? std::wstring{} : path.substr(begin + marker.size(), end - begin - marker.size());
}
std::wstring ReadTextFile(const std::wstring& path) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return {};
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 || size.QuadPart > 64 * 1024) {
    CloseHandle(file); return {};
  }
  std::vector<char> bytes(static_cast<size_t>(size.QuadPart));
  DWORD read = 0;
  const bool ok = ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) != FALSE;
  CloseHandle(file);
  if (!ok || read == 0) return {};
  if (read >= 2 && static_cast<unsigned char>(bytes[0]) == 0xFF && static_cast<unsigned char>(bytes[1]) == 0xFE) {
    const wchar_t* wide = reinterpret_cast<const wchar_t*>(bytes.data() + 2);
    const size_t chars = (read - 2) / sizeof(wchar_t);
    return std::wstring(wide, chars);
  }
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data(), static_cast<int>(read), nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data(), static_cast<int>(read), result.data(), length);
  if (!result.empty() && result.front() == 0xFEFF) result.erase(result.begin());
  return result;
}
std::vector<std::wstring> ReadReleaseNotes(const std::wstring& module_directory) {
  std::vector<std::wstring> notes;
  if (module_directory.empty()) return notes;
  const std::wstring raw = ReadTextFile(module_directory + L"\\RELEASE-NOTES.txt");
  size_t begin = 0;
  while (begin <= raw.size() && notes.size() < 8) {
    const size_t end = raw.find_first_of(L"\r\n", begin);
    std::wstring line = Trim(raw.substr(begin, end == std::wstring::npos ? std::wstring::npos : end - begin));
    if (line.rfind(L"- ", 0) == 0 || line.rfind(L"* ", 0) == 0) line = Trim(line.substr(2));
    if (!line.empty() && line[0] != L'#') notes.push_back(line);
    if (end == std::wstring::npos) break;
    begin = raw.find_first_not_of(L"\r\n", end);
    if (begin == std::wstring::npos) break;
  }
  return notes;
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
  ++window_instance_id_;
  hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kClassName, L"GY 设置", WS_POPUP,
                          x, y, width, height, nullptr, nullptr, GetModuleHandleW(nullptr), this);
  if (!hwnd_) return;
  // 设置窗自己监听剪贴板变化：剪贴板页打开时新复制的内容即时上卡。
  AddClipboardFormatListener(hwnd_);
  CreateControls();
  Load();
  ApplyThemeBrush();
  Layout();
  BeginAccountRestore();
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
  if (account_input_brush_) DeleteObject(account_input_brush_);
  edit_brush_ = CreateSolidBrush(PaletteForTheme(theme_).surface);
  account_input_brush_ = CreateSolidBrush(PaletteForTheme(theme_).ink);
}

void SettingsWindow::CreateControls() {
  ApplyThemeBrush();
  account_edit_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | WS_TABSTOP,
      0, 0, 0, 0, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
  account_email_edit_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | ES_AUTOHSCROLL | WS_TABSTOP,
      0, 0, 0, 0, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
  account_password_edit_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | ES_AUTOHSCROLL | ES_PASSWORD | WS_TABSTOP,
      0, 0, 0, 0, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
  phrases_edit_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL | WS_TABSTOP,
      0, 0, 0, 0, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
  const HFONT font = Font(dpi_, 12, FW_NORMAL);
  SendMessageW(account_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  SendMessageW(account_email_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  SendMessageW(account_password_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  SendMessageW(phrases_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  // Placeholder so the borderless account field explains itself before typing.
  SendMessageW(account_edit_, EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(L"输入邮箱，例如 name@example.com"));
  SendMessageW(account_email_edit_, EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(L"电子邮箱"));
  SendMessageW(account_password_edit_, EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(L"密码"));
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
  for (int i = 0; i < 6; ++i) nav_rects_[i] = {nav_left, nav_top + i * nav_step, nav_left + nav_width, nav_top + (i + 1) * nav_step};
  for (int i = 0; i < 3; ++i) { input_mode_rects_[i] = {}; theme_rects_[i] = {}; size_rects_[i] = {}; }
  account_rect_ = {}; account_email_rect_ = {}; account_password_rect_ = {}; account_action_rect_ = {}; account_logout_rect_ = {};
  phrases_rect_ = {}; clear_rect_ = {}; export_rect_ = {}; import_rect_ = {}; ai_preview_rect_ = {}; warm_rect_ = {};
  clip_sync_card_ = {}; clip_sync_switch_ = {}; clip_instant_card_ = {}; clip_instant_switch_ = {};
  clip_history_clear_ = {}; clip_history_list_ = {};
  version_card_ = {}; update_card_ = {}; update_repair_rect_ = {}; update_rollback_rect_ = {}; update_status_rect_ = {};

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
    const bool show_account_form = account_state_ == AccountState::LoggedOut ||
        account_state_ == AccountState::LoggingIn || account_state_ == AccountState::Failed;
    phrases_rect_ = {content_left, account_rect_.bottom + Scale(dpi_, 18), content_left + card_width,
                     account_rect_.bottom + (show_account_form ? Scale(dpi_, 208) : Scale(dpi_, 82))};
    if (show_account_form) {
      account_email_rect_ = {phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 50),
                             phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 80)};
      account_password_rect_ = {phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 88),
                                phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 118)};
      account_action_rect_ = {phrases_rect_.right - Scale(dpi_, 126), phrases_rect_.top + Scale(dpi_, 130),
                              phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 166)};
      MoveWindow(account_email_edit_, account_email_rect_.left + Scale(dpi_, 11), account_email_rect_.top + Scale(dpi_, 3),
                 account_email_rect_.right - account_email_rect_.left - Scale(dpi_, 22), Scale(dpi_, 24), TRUE);
      MoveWindow(account_password_edit_, account_password_rect_.left + Scale(dpi_, 11), account_password_rect_.top + Scale(dpi_, 3),
                 account_password_rect_.right - account_password_rect_.left - Scale(dpi_, 22), Scale(dpi_, 24), TRUE);
    } else if (account_state_ == AccountState::LoggedIn) {
      account_logout_rect_ = {phrases_rect_.right - Scale(dpi_, 102), phrases_rect_.top + Scale(dpi_, 25),
                              phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 55)};
    }
    // 从“通用”页展开短语后切过来，编辑器不能残留在本页。
    ShowWindow(phrases_edit_, SW_HIDE);
    done_y = phrases_rect_.bottom + Scale(dpi_, 22);
  } else if (page_ == Page::Clipboard) {
    // Page::Clipboard：纯历史卡片流——无页头无标题，右上角仅留“清空”。
    const int top = Scale(dpi_, 100);
    done_y = Scale(dpi_, 616);
    clip_history_clear_ = {content_left + card_width - Scale(dpi_, 60), top,
                           content_left + card_width, top + Scale(dpi_, 28)};
    clip_history_list_ = {content_left, top + Scale(dpi_, 34), content_left + card_width, done_y - Scale(dpi_, 10)};
    history_entries_ = gy::clipboard_history::ReadAll();
    PruneClipboardThumbnails();
    MeasureClipboardCards();
    ShowWindow(phrases_edit_, SW_HIDE);
  } else if (page_ == Page::Updates) {
    version_card_ = {content_left, base_y, content_left + card_width, base_y + Scale(dpi_, 106)};
    update_card_ = {content_left, version_card_.bottom + Scale(dpi_, 14), content_left + card_width, version_card_.bottom + Scale(dpi_, 314)};
    // “整备”与“回退”是轻量恢复动作，不与底部的“完成”争夺主操作。
    update_repair_rect_ = {update_card_.right - Scale(dpi_, 64), update_card_.top + Scale(dpi_, 8),
                           update_card_.right - Scale(dpi_, 16), update_card_.top + Scale(dpi_, 36)};
    if (!rollback_version_.empty() && rollback_version_ != registered_version_) {
      update_rollback_rect_ = {update_repair_rect_.left - Scale(dpi_, 80), update_card_.top + Scale(dpi_, 8),
                               update_repair_rect_.left - Scale(dpi_, 8), update_card_.top + Scale(dpi_, 36)};
    }
    update_status_rect_ = {update_card_.left + Scale(dpi_, 16), update_card_.bottom - Scale(dpi_, 54),
                           update_card_.right - Scale(dpi_, 16), update_card_.bottom - Scale(dpi_, 16)};
    ShowWindow(phrases_edit_, SW_HIDE);
    done_y = update_card_.bottom + Scale(dpi_, 22);
  }
  const bool account_page = page_ == Page::Account;
  const bool account_form = account_state_ == AccountState::LoggedOut ||
      account_state_ == AccountState::LoggingIn || account_state_ == AccountState::Failed;
  ShowWindow(account_edit_, account_page ? SW_SHOW : SW_HIDE);
  ShowWindow(account_email_edit_, account_page && account_form ? SW_SHOW : SW_HIDE);
  ShowWindow(account_password_edit_, account_page && account_form ? SW_SHOW : SW_HIDE);
  EnableWindow(account_email_edit_, account_state_ != AccountState::LoggingIn);
  EnableWindow(account_password_edit_, account_state_ != AccountState::LoggingIn);
  done_rect_ = {width - right_pad - Scale(dpi_, 110), done_y, width - right_pad, done_y + Scale(dpi_, 36)};
  close_rect_ = {width - Scale(dpi_, 48), Scale(dpi_, 18), width - Scale(dpi_, 18), Scale(dpi_, 48)};
  // The outer frame is fixed. Changing tabs or expanding phrases must never
  // make the settings dialog jump or change its proportions.
  const HRGN region = CreateRoundRectRgn(0, 0, width + 1, height_ + 1, Scale(dpi_, 14), Scale(dpi_, 14));
  SetWindowRgn(hwnd_, region, FALSE);
  if (page_ == Page::Clipboard) SetTimer(hwnd_, kClipboardStatusTimer, 250, nullptr);
  else KillTimer(hwnd_, kClipboardStatusTimer);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

bool SettingsWindow::Hit(const RECT& rect, POINT point) const { return !IsRectEmpty(&rect) && PtInRect(&rect, point); }
void SettingsWindow::TogglePhrases() { phrases_expanded_ = !phrases_expanded_; Layout(); }

void SettingsWindow::MeasureClipboardCards() {
  history_card_heights_.clear();
  const int list_width = clip_history_list_.right - clip_history_list_.left;
  const int content_width = list_width - Scale(dpi_, 38);  // text insets + scrollbar reserve
  HDC measure_dc = GetDC(nullptr);
  const HFONT body = Font(dpi_, 16, FW_SEMIBOLD);
  for (const auto& entry : history_entries_) {
    if (entry.kind == gy::clipboard_history::EntryKind::PngImage) {
      history_card_heights_.push_back(ClipboardImageCardHeight(dpi_));
    } else {
      const WrappedCard wrapped = WrapCardText(measure_dc, entry.text, body, content_width);
      history_card_heights_.push_back(ClipboardCardHeight(dpi_, std::max(1, static_cast<int>(wrapped.lines.size()))));
    }
  }
  DeleteObject(body);
  ReleaseDC(nullptr, measure_dc);
  // Largest scroll offset whose remaining cards can still fill the list.
  const int list_h = clip_history_list_.bottom - clip_history_list_.top;
  const int gap = Scale(dpi_, 8);
  history_max_scroll_ = 0;
  int acc = 0;
  for (int i = static_cast<int>(history_card_heights_.size()) - 1; i >= 0; --i) {
    acc += history_card_heights_[static_cast<size_t>(i)] + gap;
    if (acc >= list_h) { history_max_scroll_ = i; break; }
  }
  history_scroll_ = std::clamp(history_scroll_, 0, history_max_scroll_);
}

std::wstring ParentDirectory(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring{} : path.substr(0, slash);
}

std::wstring InstalledGyRoot() {
  // Host runs from <Program Files>\\GYInput\\versions\\<version>. Walk only
  // that fixed hierarchy; never derive a maintenance path from settings data
  // or from a registry value controlled outside this product.
  const std::wstring version_root = ModuleDirectory();
  const std::wstring versions_root = ParentDirectory(version_root);
  return ParentDirectory(versions_root);
}

std::wstring InstalledMaintenanceScriptPath(const wchar_t* name) {
  const std::wstring install_root = InstalledGyRoot();
  if (install_root.empty() || !name || !*name) return {};
  return install_root + L"\\" + name;
}

std::wstring ReadJsonVersionField(const std::wstring& path) {
  const std::wstring raw = ReadTextFile(path);
  constexpr std::wstring_view marker = L"\"version\"";
  const size_t marker_pos = raw.find(marker);
  if (marker_pos == std::wstring::npos) return {};
  const size_t colon = raw.find(L':', marker_pos + marker.size());
  const size_t begin = colon == std::wstring::npos ? std::wstring::npos : raw.find(L'\"', colon + 1);
  const size_t end = begin == std::wstring::npos ? std::wstring::npos : raw.find(L'\"', begin + 1);
  if (end == std::wstring::npos || end - begin <= 1 || end - begin > 32) return {};
  const std::wstring version = raw.substr(begin + 1, end - begin - 1);
  int dots = 0;
  for (const wchar_t character : version) {
    if (character == L'.') { ++dots; continue; }
    if (character < L'0' || character > L'9') return {};
  }
  return dots == 2 ? version : std::wstring{};
}

std::wstring InstalledRollbackVersion() {
  const std::wstring install_root = InstalledGyRoot();
  return install_root.empty() ? std::wstring{} : ReadJsonVersionField(install_root + L"\\install-state.previous.json");
}

SettingsWindow::ClipboardThumbnail* SettingsWindow::FindOrCreateThumbnail(
    const gy::clipboard_history::Entry& entry, int max_width, int max_height) {
  if (entry.kind != gy::clipboard_history::EntryKind::PngImage || entry.id.empty()) return nullptr;
  for (auto& thumbnail : history_thumbnails_) {
    if (thumbnail.entry_id == entry.id) return thumbnail.bitmap ? &thumbnail : nullptr;
  }
  ClipboardThumbnail thumbnail;
  thumbnail.entry_id = entry.id;
  thumbnail.bitmap = DecodeClipboardThumbnail(entry, max_width, max_height, &thumbnail.size);
  if (!thumbnail.bitmap) return nullptr;
  history_thumbnails_.push_back(std::move(thumbnail));
  return &history_thumbnails_.back();
}

void SettingsWindow::PruneClipboardThumbnails() {
  for (auto it = history_thumbnails_.begin(); it != history_thumbnails_.end();) {
    const bool still_visible = std::any_of(history_entries_.begin(), history_entries_.end(),
        [&](const gy::clipboard_history::Entry& entry) {
          return entry.kind == gy::clipboard_history::EntryKind::PngImage && entry.id == it->entry_id;
        });
    if (still_visible) {
      ++it;
      continue;
    }
    if (it->bitmap) DeleteObject(it->bitmap);
    it = history_thumbnails_.erase(it);
  }
}

void SettingsWindow::ClearClipboardThumbnails() {
  for (auto& thumbnail : history_thumbnails_) {
    if (thumbnail.bitmap) DeleteObject(thumbnail.bitmap);
  }
  history_thumbnails_.clear();
}

void SettingsWindow::Paint(HDC dc) {
  const Palette pal = PaletteForTheme(theme_);
  RECT client{}; GetClientRect(hwnd_, &client);
  Fill(dc, client, pal.ink);
  const HPEN outline = CreatePen(PS_SOLID, 1, pal.border);
  const HGDIOBJ old_pen = SelectObject(dc, outline); const HGDIOBJ old_brush = SelectObject(dc, GetStockObject(HOLLOW_BRUSH));
  RoundRect(dc, 0, 0, client.right, client.bottom, Scale(dpi_, 14), Scale(dpi_, 14));
  SelectObject(dc, old_pen); SelectObject(dc, old_brush); DeleteObject(outline);
  const HFONT title = Font(dpi_, 17, FW_SEMIBOLD), medium = Font(dpi_, 11, FW_SEMIBOLD), tiny = Font(dpi_, 10, FW_NORMAL), normal = Font(dpi_, 12, FW_NORMAL), large = Font(dpi_, 16, FW_SEMIBOLD);
  DrawGyWordmark(dc, RECT{Scale(dpi_, 24), Scale(dpi_, 25), Scale(dpi_, 76), Scale(dpi_, 58)}, pal.text);
  Text(dc, L"输入法设置", RECT{Scale(dpi_, 90), Scale(dpi_, 23), Scale(dpi_, 300), Scale(dpi_, 56)}, pal.text, DT_LEFT, title);
  Text(dc, L"v" + release_version_ + L" · 基础输入始终离线可用", RECT{Scale(dpi_, 90), Scale(dpi_, 52), Scale(dpi_, 410), Scale(dpi_, 72)}, pal.muted, DT_LEFT, tiny);
  Text(dc, L"×", close_rect_, pal.muted, DT_CENTER, title);

  const wchar_t* nav_labels[] = {L"通用", L"输入", L"外观", L"账户", L"剪贴板", L"更新"};
  for (int i = 0; i < 6; ++i) {
    const bool selected = static_cast<int>(page_) == i;
    if (selected) {
      RECT marker{nav_rects_[i].right - Scale(dpi_, 2), nav_rects_[i].top + Scale(dpi_, 8), nav_rects_[i].right + Scale(dpi_, 7), nav_rects_[i].bottom - Scale(dpi_, 8)};
      Fill(dc, marker, kBlue);
    }
    Text(dc, nav_labels[i], nav_rects_[i], selected ? pal.text : pal.muted, DT_CENTER, medium);
  }

  const int content_left = Scale(dpi_, 112), content_right = width_ - Scale(dpi_, 24);
  const wchar_t* page_titles[] = {L"通用", L"输入", L"外观", L"账户", L"剪贴板", L"版本与更新"};
  const wchar_t* page_subtitles[] = {L"学习、短语与本机备份", L"切换正在使用的输入语言", L"主题、字号与 AI 预览助手", L"本机标识与 GY 账户", L"跨设备复制粘贴与本机历史", L"已激活版本与本次更新内容"};
  // 剪贴板页无页头：卡片列表直接占满内容区。
  if (page_ != Page::Clipboard) {
    Text(dc, page_titles[static_cast<int>(page_)], RECT{content_left, Scale(dpi_, 98), content_right, Scale(dpi_, 122)}, pal.text, DT_LEFT, medium);
    Text(dc, page_subtitles[static_cast<int>(page_)], RECT{content_left, Scale(dpi_, 118), content_right, Scale(dpi_, 137)}, pal.muted, DT_LEFT, tiny);
  }

  if (page_ == Page::General) {
    Rounded(dc, phrases_rect_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"常用短语", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 8), phrases_rect_.left + Scale(dpi_, 190), phrases_rect_.top + Scale(dpi_, 32)}, pal.text, DT_LEFT, medium);
    Text(dc, phrases_expanded_ ? L"完成编辑" : L"管理 ›", RECT{phrases_rect_.right - Scale(dpi_, 100), phrases_rect_.top + Scale(dpi_, 8), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 32)}, kBlue, DT_RIGHT, medium);
    if (!phrases_expanded_) Text(dc, L"例如：dz=地址|电子邮箱", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 31), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.bottom - Scale(dpi_, 7)}, pal.muted, DT_LEFT, tiny);
    const wchar_t* tools[] = {L"清空学习", L"导出", L"导入"};
    DrawSegmentedActions(dc, clear_rect_, export_rect_, import_rect_, tools, pal, dpi_, medium);
    // 剪贴板的两个开关挂在通用页（剪贴板页只留历史卡片列表）。
    Rounded(dc, clip_sync_card_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"Keep 同步", RECT{clip_sync_card_.left + Scale(dpi_, 16), clip_sync_card_.top + Scale(dpi_, 9), clip_sync_card_.right - Scale(dpi_, 76), clip_sync_card_.top + Scale(dpi_, 31)}, pal.text, DT_LEFT, medium);
    Text(dc, L"登录后，复制内容自动写入 Keep", RECT{clip_sync_card_.left + Scale(dpi_, 16), clip_sync_card_.top + Scale(dpi_, 33), clip_sync_card_.right - Scale(dpi_, 76), clip_sync_card_.top + Scale(dpi_, 53)}, pal.muted, DT_LEFT, tiny);
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
    if (account_state_ == AccountState::LoggedIn) {
      Text(dc, account_email_, RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 31), phrases_rect_.right - Scale(dpi_, 118), phrases_rect_.top + Scale(dpi_, 51)}, pal.text, DT_LEFT, normal);
      Text(dc, account_status_.empty() ? L"已登录 · 同步功能将自动使用此账户" : account_status_,
           RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 53), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.bottom - Scale(dpi_, 9)},
           account_status_.empty() ? kBlue : pal.muted, DT_LEFT, tiny);
      Rounded(dc, account_logout_rect_, pal.surface_hover, pal.border, Scale(dpi_, 7));
      Text(dc, L"退出登录", account_logout_rect_, pal.text, DT_CENTER, tiny);
    } else if (account_state_ == AccountState::Restoring) {
      Text(dc, L"正在恢复已保存的登录状态…", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 32), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 52)}, pal.muted, DT_LEFT, normal);
      if (!account_email_.empty()) {
        Text(dc, account_email_, RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 53), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.bottom - Scale(dpi_, 9)}, pal.muted, DT_LEFT, tiny);
      }
    } else {
      Text(dc, L"登录后开启同步、跨设备词库和 AI 权益。", RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 31), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 48)}, pal.muted, DT_LEFT, tiny);
      Rounded(dc, account_email_rect_, pal.ink, pal.border, Scale(dpi_, 7));
      Rounded(dc, account_password_rect_, pal.ink, pal.border, Scale(dpi_, 7));
      const bool logging_in = account_state_ == AccountState::LoggingIn;
      Rounded(dc, account_action_rect_, logging_in ? pal.surface_hover : kBlue, logging_in ? pal.border : kBlue, Scale(dpi_, 7));
      Text(dc, logging_in ? L"登录中…" : L"登录", account_action_rect_, logging_in ? pal.muted : kOnAccent, DT_CENTER, medium);
      const COLORREF status_color = account_state_ == AccountState::Failed ? RGB(210, 80, 80) : pal.muted;
      const std::wstring status = account_status_.empty() ? L"密码仅用于本次登录，不写入本机设置。" : account_status_;
      Text(dc, status, RECT{phrases_rect_.left + Scale(dpi_, 16), phrases_rect_.top + Scale(dpi_, 174), phrases_rect_.right - Scale(dpi_, 16), phrases_rect_.bottom - Scale(dpi_, 8)}, status_color, DT_LEFT, tiny);
    }
  } else if (page_ == Page::Clipboard) {
    // Page::Clipboard：纯历史卡片流（无页头/无标题行），右上角仅保留“清空”。
    Text(dc, L"清空", clip_history_clear_, kBlue, DT_CENTER, medium);
    const int card_gap = Scale(dpi_, 8);
    if (history_entries_.empty()) {Text(dc, L"还没有剪贴板历史，复制一段文字试试", clip_history_list_, pal.muted, DT_CENTER, normal);
    } else {
      const bool scrolling = history_max_scroll_ > 0;
      const int card_right = clip_history_list_.right - (scrolling ? Scale(dpi_, 10) : 0);
      const int line_h = Scale(dpi_, 18);
      int top = clip_history_list_.top;
      int visible_rows = 0;
      for (int index = history_scroll_; index < static_cast<int>(history_entries_.size()); ++index) {
        if (top >= clip_history_list_.bottom) break;
        const int card_h = history_card_heights_[static_cast<size_t>(index)];
        RECT card{clip_history_list_.left, top, card_right, top + card_h};
        // Zebra follows the entry, not the row: colors stay put while scrolling.
        const COLORREF row_fill = (index % 2 == 0) ? pal.surface : pal.surface_alt;
        Rounded(dc, card, row_fill, pal.border, Scale(dpi_, 10));
        const auto& entry = history_entries_[static_cast<size_t>(index)];
        if (entry.kind == gy::clipboard_history::EntryKind::PngImage) {
          const RECT preview{card.left + Scale(dpi_, 14), card.top + Scale(dpi_, 8),
                             card.left + Scale(dpi_, 126), card.top + Scale(dpi_, 80)};
          Rounded(dc, preview, pal.ink, pal.border, Scale(dpi_, 6));
          if (ClipboardThumbnail* thumbnail = FindOrCreateThumbnail(entry, Scale(dpi_, 104), Scale(dpi_, 64))) {
            DrawClipboardThumbnail(dc, thumbnail->bitmap, thumbnail->size, preview);
          } else {
            Text(dc, L"图片不可读取", preview, pal.muted, DT_CENTER, tiny);
          }
          Text(dc, L"图片", RECT{preview.right + Scale(dpi_, 14), card.top + Scale(dpi_, 14),
                                   card.right - Scale(dpi_, 14), card.top + Scale(dpi_, 40)},
               pal.text, DT_LEFT, medium);
          Text(dc, L"PNG · 已保存到 Keep", RECT{preview.right + Scale(dpi_, 14), card.top + Scale(dpi_, 42),
                                                card.right - Scale(dpi_, 14), card.top + Scale(dpi_, 62)},
               pal.muted, DT_LEFT, tiny);
        } else {
          const WrappedCard wrapped = WrapCardText(dc, entry.text, large, card.right - card.left - Scale(dpi_, 28));
          DrawCardText(dc, wrapped, RECT{card.left + Scale(dpi_, 14), card.top + Scale(dpi_, 8),
                                         card.right - Scale(dpi_, 14), card.bottom}, pal.text, large, line_h, Scale(dpi_, 7));
        }
        const std::wstring status = entry.pending_upload ? L"同步中 · " : L"已确认 · ";
        Text(dc, status + FormatEntryTime(entry.unix_time), RECT{card.left + Scale(dpi_, 14), card.bottom - Scale(dpi_, 22),
                                                                  card.right - Scale(dpi_, 14), card.bottom - Scale(dpi_, 7)},
             entry.pending_upload ? kBlue : pal.muted, DT_LEFT, tiny);
        top += card_h + card_gap;
        ++visible_rows;
      }
      if (scrolling) {
        RECT track{clip_history_list_.right - Scale(dpi_, 4), clip_history_list_.top + Scale(dpi_, 2),
                   clip_history_list_.right, clip_history_list_.bottom - Scale(dpi_, 2)};
        Fill(dc, track, pal.border);
        const int track_h = track.bottom - track.top;
        const int thumb_h = std::max(Scale(dpi_, 20), track_h * std::max(1, visible_rows) / static_cast<int>(history_entries_.size()));
        const int thumb_y = track.top + (track_h - thumb_h) * history_scroll_ / std::max(1, history_max_scroll_);
        Fill(dc, RECT{track.left, thumb_y, track.right, thumb_y + thumb_h}, pal.muted);
      }
    }
  } else if (page_ == Page::Updates) {
    Rounded(dc, version_card_, pal.surface, pal.border, Scale(dpi_, 9));
    Text(dc, L"当前运行版本", RECT{version_card_.left + Scale(dpi_, 16), version_card_.top + Scale(dpi_, 10), version_card_.right - Scale(dpi_, 16), version_card_.top + Scale(dpi_, 32)}, pal.muted, DT_LEFT, tiny);
    Text(dc, L"v" + release_version_, RECT{version_card_.left + Scale(dpi_, 16), version_card_.top + Scale(dpi_, 29), version_card_.right - Scale(dpi_, 16), version_card_.top + Scale(dpi_, 60)}, pal.text, DT_LEFT, large);
    const std::wstring activation = registered_version_.empty()
        ? L"注册表激活版本暂不可读"
        : (registered_version_ == release_version_ ? L"已激活 · Host / DLL / TSF 版本一致"
                                                     : L"系统激活 v" + registered_version_ + L" · 当前 Host v" + release_version_);
    Text(dc, activation, RECT{version_card_.left + Scale(dpi_, 16), version_card_.top + Scale(dpi_, 61), version_card_.right - Scale(dpi_, 16), version_card_.top + Scale(dpi_, 80)}, versions_consistent_ ? pal.muted : RGB(210, 80, 80), DT_LEFT, tiny);
    const std::wstring tsf_detail = registered_core_version_.empty()
        ? L"TSF / DLL 注册版本暂不可读"
        : L"注册表 Host v" + registered_version_ + L" · TSF / DLL v" + registered_core_version_;
    Text(dc, tsf_detail, RECT{version_card_.left + Scale(dpi_, 16), version_card_.top + Scale(dpi_, 80), version_card_.right - Scale(dpi_, 16), version_card_.bottom - Scale(dpi_, 8)}, versions_consistent_ ? pal.muted : RGB(210, 80, 80), DT_LEFT, tiny);
    Rounded(dc, update_card_, pal.surface, pal.border, Scale(dpi_, 9));
    const int update_actions_left = update_rollback_rect_.right > update_rollback_rect_.left
        ? update_rollback_rect_.left : update_repair_rect_.left;
    Text(dc, L"本次更新", RECT{update_card_.left + Scale(dpi_, 16), update_card_.top + Scale(dpi_, 12), update_actions_left - Scale(dpi_, 12), update_card_.top + Scale(dpi_, 36)}, pal.text, DT_LEFT, medium);
    if (release_notes_.empty()) {
      Text(dc, L"此版本没有附带更新说明。", RECT{update_card_.left + Scale(dpi_, 16), update_card_.top + Scale(dpi_, 52), update_card_.right - Scale(dpi_, 16), update_card_.top + Scale(dpi_, 78)}, pal.muted, DT_LEFT, tiny);
    } else {
      int note_y = update_card_.top + Scale(dpi_, 50);
      for (const auto& note : release_notes_) {
        if (note_y + Scale(dpi_, 26) > update_status_rect_.top - Scale(dpi_, 10)) break;
        Text(dc, L"• " + note, RECT{update_card_.left + Scale(dpi_, 16), note_y, update_card_.right - Scale(dpi_, 16), note_y + Scale(dpi_, 26)}, pal.muted, DT_LEFT, tiny);
        note_y += Scale(dpi_, 29);
      }
    }
    std::wstring default_repair_status = versions_consistent_
        ? L"整备会核验当前安装，并清理旧版本与失效安装临时文件；不会影响输入设置、剪贴板或登录信息。"
        : L"检测到激活版本不一致；可整备当前安装并安全清理旧版本残留。";
    if (update_rollback_rect_.right > update_rollback_rect_.left) {
      default_repair_status += L" 可回退至 v" + rollback_version_ + L"。";
    }
    const std::wstring& repair_status = update_repair_status_.empty() ? default_repair_status : update_repair_status_;
    // A failed housekeeping pass is not the same thing as a broken input
    // method. Keep red for a real version mismatch; use calm amber when the
    // active Host / DLL / TSF trio is already healthy and only cleanup waits.
    const COLORREF repair_status_color = update_repair_failed_
        ? (versions_consistent_ ? RGB(191, 151, 83) : RGB(210, 80, 80))
        : pal.muted;
    Text(dc, repair_status, update_status_rect_, repair_status_color, DT_LEFT | DT_WORDBREAK, tiny);
    if (update_rollback_rect_.right > update_rollback_rect_.left) {
      Text(dc, update_repair_in_progress_ ? L"处理中…" : L"回退", update_rollback_rect_,
           update_repair_in_progress_ ? pal.muted : kBlue, DT_RIGHT, medium);
    }
    Text(dc, update_repair_in_progress_ ? L"处理中…" : L"整备", update_repair_rect_,
         update_repair_in_progress_ ? pal.muted : kBlue, DT_RIGHT, medium);
  }

  Rounded(dc, done_rect_, kBlue, kBlue, Scale(dpi_, 8));
  Text(dc, L"完成", done_rect_, kOnAccent, DT_CENTER, medium);
  Text(dc, page_ == Page::Account ? L"登录会话仅保存在当前 Windows 用户的加密存储内" : L"所有基础输入设置仅保存在本机", RECT{content_left, done_rect_.top, done_rect_.left - Scale(dpi_, 16), done_rect_.bottom}, pal.muted, DT_LEFT, tiny);
  DeleteObject(title); DeleteObject(medium); DeleteObject(tiny); DeleteObject(normal); DeleteObject(large);
}

void SettingsWindow::Load() {
  release_version_ = WidenAscii(GY_RELEASE_VERSION);
  registered_version_ = ReadRegisteredVersion();
  registered_core_version_ = ReadRegisteredDllVersion();
  rollback_version_ = InstalledRollbackVersion();
  // The update page's own compiled release is part of the truth.  A Host
  // executable from 0.10.64 with the registry still on 0.10.61 must be shown
  // as repairable instead of pretending that the old Host/DLL pair is healthy.
  versions_consistent_ = !release_version_.empty() && !registered_version_.empty() &&
      release_version_ == registered_version_ && registered_version_ == registered_core_version_;
  if (!update_repair_in_progress_) {
    update_repair_status_.clear();
    update_repair_failed_ = false;
  }
  release_notes_ = ReadReleaseNotes(ModuleDirectory());
  if (release_notes_.empty()) {
    release_notes_ = {L"版本独立目录：Host、核心 DLL 与词库按版本隔离。", L"安装后自动校验注册、Logo 与离线引擎状态。"};
  }
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
  gy::keep_sync::SetEnabled(clip_enabled_);
  gy::keep_sync::SetInstantPasteEnabled(clip_instant_);

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
  ClearClipboardThumbnails();
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

void SettingsWindow::BeginUpdateRepair() {
  BeginUpdateMaintenance(false);
}

void SettingsWindow::BeginUpdateRollback() {
  BeginUpdateMaintenance(true);
}

void SettingsWindow::BeginUpdateMaintenance(bool rollback) {
  if (!hwnd_ || update_repair_in_progress_) return;

  const wchar_t* const script_name = rollback ? L"Rollback-GYInput.ps1" : L"Repair-GYInput.ps1";
  const std::wstring maintenance_script = InstalledMaintenanceScriptPath(script_name);
  if (maintenance_script.empty() || GetFileAttributesW(maintenance_script.c_str()) == INVALID_FILE_ATTRIBUTES) {
    update_repair_failed_ = true;
    update_repair_status_ = rollback
        ? L"当前安装缺少回退组件；请先安装同版本或更高版本的 GY 安装包。"
        : L"当前安装缺少整备组件；请先安装同版本或更高版本的 GY 安装包。";
    InvalidateRect(hwnd_, nullptr, FALSE);
    return;
  }

  // Resolve the System32 PowerShell path directly so an unusual PATH value
  // cannot redirect this maintenance action to an untrusted executable.
  wchar_t windows_directory[MAX_PATH]{};
  const UINT windows_length = GetWindowsDirectoryW(windows_directory, static_cast<UINT>(std::size(windows_directory)));
  if (windows_length == 0 || windows_length >= std::size(windows_directory)) {
    update_repair_failed_ = true;
    update_repair_status_ = L"无法定位 Windows PowerShell；未执行任何整备操作。";
    InvalidateRect(hwnd_, nullptr, FALSE);
    return;
  }
  const std::wstring powershell_path = std::wstring(windows_directory, windows_length) +
      L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
  const std::wstring parameters = L"-NoProfile -ExecutionPolicy Bypass -File \"" + maintenance_script + L"\" -Elevated";

  SHELLEXECUTEINFOW execute{};
  execute.cbSize = sizeof(execute);
  execute.fMask = SEE_MASK_NOCLOSEPROCESS;
  execute.hwnd = hwnd_;
  execute.lpVerb = L"runas";
  execute.lpFile = powershell_path.c_str();
  execute.lpParameters = parameters.c_str();
  execute.nShow = SW_HIDE;
  if (!ShellExecuteExW(&execute) || !execute.hProcess) {
    const DWORD error = GetLastError();
    update_repair_failed_ = true;
    update_repair_status_ = error == ERROR_CANCELLED
        ? L"未授予管理员权限，未修改任何内容。"
        : (rollback ? L"无法启动回退；未修改任何内容，请稍后重试。"
                    : L"无法启动整备；未修改任何内容，请稍后重试。");
    InvalidateRect(hwnd_, nullptr, FALSE);
    return;
  }

  update_repair_in_progress_ = true;
  update_repair_failed_ = false;
  update_repair_status_ = rollback
      ? L"正在回退至上一健康版本，并验证 DLL、Host 与离线引擎…"
      : L"正在整备当前安装并清理旧版本…";
  InvalidateRect(hwnd_, nullptr, FALSE);
  const HWND target = hwnd_;
  const std::uint64_t instance = window_instance_id_;
  const HANDLE process = execute.hProcess;
  try {
    std::thread([target, instance, process, rollback]() {
      WaitForSingleObject(process, INFINITE);
      DWORD exit_code = ERROR_GEN_FAILURE;
      GetExitCodeProcess(process, &exit_code);
      CloseHandle(process);
      PostUpdateMaintenanceCompletion(target, instance, exit_code, rollback);
    }).detach();
  } catch (...) {
    CloseHandle(process);
    update_repair_in_progress_ = false;
    update_repair_failed_ = true;
    update_repair_status_ = rollback
        ? L"无法监控回退进程；请运行开始菜单中的“回退到上一版 GY 输入法”。"
        : L"无法监控整备进程；请运行开始菜单中的“整备 GY 输入法”。";
    InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

void SettingsWindow::FinishUpdateMaintenance(std::uint64_t window_instance_id, DWORD exit_code, bool rollback) {
  if (window_instance_id != window_instance_id_) return;
  update_repair_in_progress_ = false;
  Load();
  if (exit_code == 0) {
    update_repair_failed_ = false;
    update_repair_status_ = rollback
        ? L"已回退至 v" + registered_version_ + L"；DLL、Host 与离线引擎已重新验证。"
        : L"已整备当前安装，并清理旧版本与失效临时安装文件。";
  } else {
    update_repair_failed_ = true;
    if (rollback) {
      update_repair_status_ = L"回退未执行；当前注册与诊断信息已保留，可关闭占用程序后重试。";
    } else {
      update_repair_status_ = versions_consistent_
          ? L"待整备 · 输入法仍可用；关闭占用程序后可再次尝试。"
          : L"整备未完成；已保留回滚与诊断信息，可在关闭占用程序后再次尝试。";
    }
  }
  InvalidateRect(hwnd_, nullptr, FALSE);
}

void SettingsWindow::BeginAccountLogin() {
  if (!hwnd_ || account_state_ == AccountState::LoggingIn || account_state_ == AccountState::Restoring) return;
  std::wstring email = Trim(EditText(account_email_edit_));
  std::wstring password = EditText(account_password_edit_);
  if (email.empty() || password.empty()) {
    SecureErase(&password);
    account_state_ = AccountState::Failed;
    account_status_ = L"请输入电子邮箱和密码。";
    Layout();
    return;
  }

  account_email_ = email;
  account_state_ = AccountState::LoggingIn;
  account_status_.clear();
  SetWindowTextW(account_password_edit_, L"");
  Layout();
  const HWND target = hwnd_;
  const std::uint64_t instance = window_instance_id_;
  const std::uint64_t request = ++account_request_id_;
  try {
    std::thread([target, instance, request, email = std::move(email), password = std::move(password)]() mutable {
      gy::account_auth::Result result = gy::account_auth::Login(email, password);
      SecureErase(&password);
      PostAccountCompletion(target, instance, request, std::move(result));
    }).detach();
  } catch (...) {
    SecureErase(&password);
    account_state_ = AccountState::Failed;
    account_status_ = L"无法启动登录请求，请重试。";
    Layout();
  }
}

void SettingsWindow::BeginAccountRestore() {
  if (!hwnd_ || account_state_ == AccountState::Restoring || account_state_ == AccountState::LoggingIn) return;
  gy::account_auth::StoredSession stored;
  if (!gy::account_auth::LoadStoredSession(&stored)) return;
  account_email_ = stored.email;
  SetWindowTextW(account_email_edit_, account_email_.c_str());
  account_state_ = AccountState::Restoring;
  account_status_.clear();
  Layout();
  const HWND target = hwnd_;
  const std::uint64_t instance = window_instance_id_;
  const std::uint64_t request = ++account_request_id_;
  std::wstring refresh_token = std::move(stored.refresh_token);
  try {
    std::thread([target, instance, request, refresh_token = std::move(refresh_token)]() mutable {
      gy::account_auth::Result result = gy::account_auth::Restore(refresh_token);
      SecureErase(&refresh_token);
      PostAccountCompletion(target, instance, request, std::move(result));
    }).detach();
  } catch (...) {
    SecureErase(&refresh_token);
    account_state_ = AccountState::Failed;
    account_status_ = L"无法恢复登录，请重试。";
    Layout();
  }
}

void SettingsWindow::BeginAccountLogout() {
  ++account_request_id_;  // ignore a late restore/login completion after sign-out
  gy::account_auth::StoredSession stored;
  const bool had_stored_session = gy::account_auth::LoadStoredSession(&stored);
  const bool cleared = gy::account_auth::ClearStoredSession();
  SecureErase(&account_access_token_);
  account_token_expiry_ = 0;
  account_email_.clear();
  account_state_ = cleared ? AccountState::LoggedOut : AccountState::Failed;
  account_status_ = cleared ? L"已退出 GY 账户。" : L"无法移除本机登录信息。";
  SetWindowTextW(account_email_edit_, L"");
  SetWindowTextW(account_password_edit_, L"");
  Layout();
  gy::keep_sync::NotifyAccountChanged();
  if (!had_stored_session) return;

  std::wstring refresh_token = std::move(stored.refresh_token);
  try {
    std::thread([refresh_token = std::move(refresh_token)]() mutable {
      gy::account_auth::Logout(refresh_token);  // best effort; local sign-out already completed
      SecureErase(&refresh_token);
    }).detach();
  } catch (...) {
    SecureErase(&refresh_token);
  }
}

void SettingsWindow::FinishAccountRequest(std::uint64_t request_id, gy::account_auth::Result* result) {
  if (!result) return;
  if (request_id != account_request_id_) {
    SecureEraseAccountResult(result);
    return;
  }

  const bool restoring = account_state_ == AccountState::Restoring;
  if (result->status == gy::account_auth::Status::Success) {
    gy::account_auth::StoredSession stored{result->session.email, result->session.refresh_token};
    const bool persisted = gy::account_auth::SaveStoredSession(stored);
    SecureErase(&stored.refresh_token);
    SecureErase(&account_access_token_);
    account_email_ = result->session.email;
    account_access_token_ = std::move(result->session.access_token);
    account_token_expiry_ = result->session.expires_at;
    account_state_ = AccountState::LoggedIn;
    account_status_ = persisted ? L"已登录 · 同步功能将自动使用此账户" : L"已登录，但无法保存本机登录状态。";
    SetWindowTextW(account_email_edit_, account_email_.c_str());
    SetWindowTextW(account_password_edit_, L"");
    gy::keep_sync::NotifyAccountChanged();
  } else {
    SecureErase(&result->session.access_token);
    SecureErase(&result->session.refresh_token);
    if (restoring && result->status == gy::account_auth::Status::Unauthorized) {
      gy::account_auth::ClearStoredSession();
      SecureErase(&account_access_token_);
      account_token_expiry_ = 0;
      account_status_ = L"登录已失效，请重新登录。";
    } else if (result->status == gy::account_auth::Status::Unauthorized) {
      account_status_ = L"电子邮箱或密码不正确。";
    } else if (result->status == gy::account_auth::Status::NetworkError) {
      account_status_ = restoring ? L"网络不可用，已保留登录信息。" : L"网络不可用，请检查连接后重试。";
    } else if (result->status == gy::account_auth::Status::ServerError) {
      account_status_ = L"账户服务暂不可用，请稍后重试。";
    } else {
      account_status_ = L"账户服务返回了无效响应，请稍后重试。";
    }
    account_state_ = AccountState::Failed;
    SetWindowTextW(account_email_edit_, account_email_.c_str());
  }
  SecureEraseAccountResult(result);
  Layout();
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
      const HWND control = reinterpret_cast<HWND>(lparam);
      const bool account_auth_edit = control == self->account_email_edit_ || control == self->account_password_edit_;
      SetTextColor(reinterpret_cast<HDC>(wparam), pal.text);
      SetBkColor(reinterpret_cast<HDC>(wparam), account_auth_edit ? pal.ink : pal.surface);
      return reinterpret_cast<LRESULT>(account_auth_edit ? self->account_input_brush_ : self->edit_brush_);
    }
    case WM_MOUSEMOVE: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      bool hand = self->Hit(self->done_rect_, point) || self->Hit(self->close_rect_, point);
      for (const RECT& rect : self->nav_rects_) hand = hand || self->Hit(rect, point);
      if (self->page_ == Page::General) hand = hand || self->Hit(self->phrases_rect_, point) || self->Hit(self->clear_rect_, point) || self->Hit(self->export_rect_, point) || self->Hit(self->import_rect_, point) || self->Hit(self->clip_sync_switch_, point) || self->Hit(self->clip_instant_switch_, point);
      if (self->page_ == Page::Input) { for (const RECT& rect : self->input_mode_rects_) hand = hand || self->Hit(rect, point); hand = hand || self->Hit(self->warm_rect_, point); }
      if (self->page_ == Page::Appearance) { for (const RECT& rect : self->theme_rects_) hand = hand || self->Hit(rect, point); for (const RECT& rect : self->size_rects_) hand = hand || self->Hit(rect, point); }
      if (self->page_ == Page::Account) hand = hand || self->Hit(self->account_action_rect_, point) || self->Hit(self->account_logout_rect_, point);
      if (self->page_ == Page::Clipboard) hand = hand || self->Hit(self->clip_history_clear_, point);
      if (self->page_ == Page::Updates && !self->update_repair_in_progress_) {
        hand = hand || self->Hit(self->update_repair_rect_, point) || self->Hit(self->update_rollback_rect_, point);
      }
      SetCursor(LoadCursorW(nullptr, hand ? IDC_HAND : IDC_ARROW)); return 0;
    }
    case WM_SETCURSOR: {
      POINT point{}; GetCursorPos(&point); ScreenToClient(hwnd, &point);
      bool hand = self->Hit(self->done_rect_, point) || self->Hit(self->close_rect_, point);
      for (const RECT& rect : self->nav_rects_) hand = hand || self->Hit(rect, point);
      if (self->page_ == Page::General) hand = hand || self->Hit(self->phrases_rect_, point) || self->Hit(self->clear_rect_, point) || self->Hit(self->export_rect_, point) || self->Hit(self->import_rect_, point) || self->Hit(self->clip_sync_switch_, point) || self->Hit(self->clip_instant_switch_, point);
      if (self->page_ == Page::Input) { for (const RECT& rect : self->input_mode_rects_) hand = hand || self->Hit(rect, point); hand = hand || self->Hit(self->warm_rect_, point); }
      if (self->page_ == Page::Appearance) { for (const RECT& rect : self->theme_rects_) hand = hand || self->Hit(rect, point); for (const RECT& rect : self->size_rects_) hand = hand || self->Hit(rect, point); }
      if (self->page_ == Page::Account) hand = hand || self->Hit(self->account_action_rect_, point) || self->Hit(self->account_logout_rect_, point);
      if (self->page_ == Page::Clipboard) hand = hand || self->Hit(self->clip_history_clear_, point);
      if (self->page_ == Page::Updates && !self->update_repair_in_progress_) hand = hand || self->Hit(self->update_repair_rect_, point);
      if (hand) { SetCursor(LoadCursorW(nullptr, IDC_HAND)); return TRUE; } break;
    }
    case WM_LBUTTONUP: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      for (int i = 0; i < 6; ++i) if (self->Hit(self->nav_rects_[i], point)) { self->page_ = static_cast<Page>(i); self->Layout(); return 0; }
      if (self->page_ == Page::Input) for (int i = 0; i < 3; ++i) if (self->Hit(self->input_mode_rects_[i], point)) { self->input_mode_ = i; self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::Input && self->Hit(self->warm_rect_, point)) { self->warm_start_ = !self->warm_start_; self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::Appearance) for (int i = 0; i < 3; ++i) if (self->Hit(self->theme_rects_[i], point)) { self->theme_ = i; self->Save(); self->ApplyThemeBrush(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::Appearance) for (int i = 0; i < 3; ++i) if (self->Hit(self->size_rects_[i], point)) { self->size_index_ = i; self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::Account && self->Hit(self->account_action_rect_, point)) { self->BeginAccountLogin(); return 0; }
      if (self->page_ == Page::Account && self->Hit(self->account_logout_rect_, point)) { self->BeginAccountLogout(); return 0; }
      // 剪贴板开关在通用页：拨动即写入（不等“完成”）；剪贴板页只剩清空。
      if (self->page_ == Page::General && self->Hit(self->clip_sync_switch_, point)) { self->clip_enabled_ = !self->clip_enabled_; gy::keep_sync::SetEnabled(self->clip_enabled_); self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::General && self->Hit(self->clip_instant_switch_, point)) { self->clip_instant_ = !self->clip_instant_; gy::keep_sync::SetInstantPasteEnabled(self->clip_instant_); self->Save(); InvalidateRect(hwnd, nullptr, FALSE); return 0; }
      if (self->page_ == Page::Clipboard && self->Hit(self->clip_history_clear_, point)) { self->ClearHistory(); return 0; }
      if (self->page_ == Page::Updates && !self->update_repair_in_progress_ && self->Hit(self->update_rollback_rect_, point)) { self->BeginUpdateRollback(); return 0; }
      if (self->page_ == Page::Updates && !self->update_repair_in_progress_ && self->Hit(self->update_repair_rect_, point)) { self->BeginUpdateRepair(); return 0; }
      if (self->page_ == Page::General && self->Hit(self->phrases_rect_, point)) { self->TogglePhrases(); return 0; }
      if (self->page_ == Page::General && self->Hit(self->clear_rect_, point)) { self->ClearLearning(); return 0; }
      if (self->page_ == Page::General && self->Hit(self->export_rect_, point)) { self->Save(); self->ExportBackup(); return 0; }
      if (self->page_ == Page::General && self->Hit(self->import_rect_, point)) { self->ImportBackup(); return 0; }
      if (self->Hit(self->done_rect_, point)) { self->Save(); DestroyWindow(hwnd); return 0; }
      if (self->Hit(self->close_rect_, point)) { DestroyWindow(hwnd); return 0; }
      return 0;
    }
    case kAccountRequestComplete: {
      auto* completion = reinterpret_cast<AccountRequestCompletion*>(lparam);
      if (!completion) return 0;
      if (completion->window_instance_id == self->window_instance_id_) {
        self->FinishAccountRequest(completion->request_id, &completion->result);
      } else {
        SecureEraseAccountResult(&completion->result);
      }
      delete completion;
      return 0;
    }
    case kUpdateMaintenanceComplete: {
      auto* completion = reinterpret_cast<UpdateMaintenanceCompletion*>(lparam);
      if (!completion) return 0;
      self->FinishUpdateMaintenance(completion->window_instance_id, completion->exit_code, completion->rollback);
      delete completion;
      return 0;
    }
    case WM_NCHITTEST: {
      const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      POINT client = point;
      ScreenToClient(hwnd, &client);
      // The close control lives in the visual header but must remain a real
      // client click; otherwise Windows treats it as a title-bar drag.
      if (self->Hit(self->close_rect_, client)) return HTCLIENT;
      if (client.y < Scale(self->dpi_, 76)) return HTCAPTION;
      break;
    }
    case WM_TIMER: {
      if (wparam != kClipboardStatusTimer || self->page_ != Page::Clipboard) break;
      std::vector<gy::clipboard_history::Entry> latest = gy::clipboard_history::ReadAll();
      if (!SameClipboardEntries(self->history_entries_, latest)) {
        self->history_entries_ = std::move(latest);
        self->PruneClipboardThumbnails();
        self->MeasureClipboardCards();
        self->history_scroll_ = std::min(self->history_scroll_, self->history_max_scroll_);
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }
    case WM_MOUSEWHEEL: {
      if (self->page_ != Page::Clipboard) break;
      const int max_scroll = self->history_max_scroll_;
      if (max_scroll == 0) return 0;
      const int step = 3;
      self->history_scroll_ = std::clamp(self->history_scroll_ + (GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? -step : step), 0, max_scroll);
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }
    case WM_DPICHANGED: {
      self->dpi_ = std::min<UINT>(HIWORD(wparam), kMaxSettingsDpi);
      self->ClearClipboardThumbnails();
      const RECT* suggested = reinterpret_cast<const RECT*>(lparam);
      HMONITOR monitor = MonitorFromRect(suggested, MONITOR_DEFAULTTONEAREST);
      MONITORINFO info{sizeof(info)}; GetMonitorInfoW(monitor, &info);
      self->width_ = std::min(Scale(self->dpi_, 520), std::max(Scale(self->dpi_, 360), static_cast<int>(info.rcWork.right - info.rcWork.left) - Scale(self->dpi_, 32)));
      self->height_ = std::min(Scale(self->dpi_, 680), std::max(Scale(self->dpi_, 460), static_cast<int>(info.rcWork.bottom - info.rcWork.top) - Scale(self->dpi_, 32)));
      SetWindowPos(hwnd, nullptr, suggested->left, suggested->top, self->width_, self->height_, SWP_NOZORDER | SWP_NOACTIVATE);
      self->Layout(); return 0;
    }
    case WM_CLIPBOARDUPDATE: {
      // 与隐藏监听窗口收到的顺序不定；AppendFromClipboard 连续去重，双写安全。
      if (gy::clipboard_history::AppendFromClipboard()) {
        gy::keep_sync::NotifyLocalClipboardChanged();
      }
      if (self->page_ == Page::Clipboard) {
        self->history_entries_ = gy::clipboard_history::ReadAll();
        self->PruneClipboardThumbnails();
        self->MeasureClipboardCards();
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }
    case WM_DESTROY:
      ++self->account_request_id_;
      SetWindowTextW(self->account_password_edit_, L"");
      KillTimer(hwnd, kClipboardStatusTimer);
      RemoveClipboardFormatListener(hwnd);
      self->ClearClipboardThumbnails();
      if (self->edit_brush_) { DeleteObject(self->edit_brush_); self->edit_brush_ = nullptr; }
      if (self->account_input_brush_) { DeleteObject(self->account_input_brush_); self->account_input_brush_ = nullptr; }
      self->hwnd_ = nullptr;
      return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
