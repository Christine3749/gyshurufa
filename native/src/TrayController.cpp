#include "TrayController.h"

#include <shellapi.h>

#include <utility>

namespace {
constexpr wchar_t kTrayClass[] = L"GyImeHostTray";
constexpr UINT kTrayCallback = WM_APP + 83;
constexpr UINT kSettingsCommand = 1;
UINT TaskbarCreatedMessage() {
  static const UINT message = RegisterWindowMessageW(L"TaskbarCreated");
  return message;
}

ATOM RegisterTrayClass() {
  static const ATOM atom = [] {
    WNDCLASSEXW wc{sizeof(wc)};
    wc.lpfnWndProc = TrayController::WindowProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kTrayClass;
    return RegisterClassExW(&wc);
  }();
  return atom;
}

std::wstring InstallIconPath(const std::wstring& host_directory) {
  // Each versioned Host ships its icon beside the executable. Never tie the
  // tray asset to a particular TSF DLL version: that was why upgraded Hosts
  // silently fell back to the generic Windows application icon.
  return host_directory.empty() ? std::wstring{} : host_directory + L"\\gy.ico";
}

NOTIFYICONDATAW MakeIconData(HWND hwnd, HICON icon) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd;
  data.uID = 1;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayCallback;
  data.hIcon = icon;
  wcscpy_s(data.szTip, L"GY 输入法");
  return data;
}
}  // namespace

TrayController::TrayController(std::wstring host_directory, std::function<void()> open_settings)
    : host_directory_(std::move(host_directory)), open_settings_(std::move(open_settings)) {}
TrayController::~TrayController() { Stop(); }

bool TrayController::Start() {
  if (hwnd_) return true;
  if (!RegisterTrayClass()) return false;
  hwnd_ = CreateWindowExW(0, kTrayClass, L"", 0, 0, 0, 0, 0,
                          HWND_MESSAGE, nullptr, GetModuleHandleW(nullptr), this);
  if (!hwnd_) return false;
  const std::wstring icon_path = InstallIconPath(host_directory_);
  icon_ = static_cast<HICON>(LoadImageW(nullptr, icon_path.c_str(), IMAGE_ICON, 0, 0,
                                        LR_LOADFROMFILE | LR_DEFAULTSIZE));
  if (!icon_) icon_ = LoadIconW(nullptr, IDI_APPLICATION);
  NOTIFYICONDATAW data = MakeIconData(hwnd_, icon_);
  icon_added_ = Shell_NotifyIconW(NIM_ADD, &data) == TRUE;
  return icon_added_;
}

void TrayController::Stop() {
  if (icon_added_ && hwnd_) {
    NOTIFYICONDATAW data = MakeIconData(hwnd_, icon_);
    Shell_NotifyIconW(NIM_DELETE, &data);
  }
  icon_added_ = false;
  if (icon_ && icon_ != LoadIconW(nullptr, IDI_APPLICATION)) DestroyIcon(icon_);
  icon_ = nullptr;
  if (hwnd_) { DestroyWindow(hwnd_); hwnd_ = nullptr; }
}

void TrayController::OpenSettings() const {
  if (open_settings_) open_settings_();
}

void TrayController::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, L"GY 输入法");
  AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, L"中 / EN：使用系统“简体”或 Ctrl + Space");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kSettingsCommand, L"输入法设置…");
  POINT point{};
  GetCursorPos(&point);
  SetForegroundWindow(hwnd_);
  const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                      point.x, point.y, 0, hwnd_, nullptr);
  DestroyMenu(menu);
  if (command == kSettingsCommand) OpenSettings();
  PostMessageW(hwnd_, WM_NULL, 0, 0);
}

LRESULT CALLBACK TrayController::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<TrayController*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = reinterpret_cast<TrayController*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (self && message == kTrayCallback && (lparam == WM_LBUTTONUP || lparam == WM_RBUTTONUP)) {
    self->ShowMenu();
    return 0;
  }
  if (self && message == TaskbarCreatedMessage() && self->icon_) {
    NOTIFYICONDATAW data = MakeIconData(hwnd, self->icon_);
    self->icon_added_ = Shell_NotifyIconW(NIM_ADD, &data) == TRUE;
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
