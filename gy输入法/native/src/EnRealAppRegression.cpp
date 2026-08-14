#include <windows.h>
#include <richedit.h>

#include <chrono>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include "InputMode.h"

namespace {

constexpr wchar_t kWindowClass[] = L"GyEnRealAppRegression";
constexpr wchar_t kGyImeModule[] = L"GyIme.dll";

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_CLOSE) {
    DestroyWindow(window);
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

bool RegisterWindowClass(HINSTANCE instance) {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kWindowClass;
  return RegisterClassW(&window_class) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

class InputModeRestoreGuard {
 public:
  explicit InputModeRestoreGuard(int original_mode) : original_mode_(original_mode) {}
  InputModeRestoreGuard(const InputModeRestoreGuard&) = delete;
  InputModeRestoreGuard& operator=(const InputModeRestoreGuard&) = delete;

  // Arm immediately before the real Shift interaction. The regression must
  // prove that Shift returns to this value, but no failed diagnostic may leave
  // a person's next application stuck in a different global input mode.
  void Arm() noexcept { armed_ = true; }
  bool RestoreNow() {
    if (!armed_) return gy::input_mode::Read() == original_mode_;
    gy::input_mode::Write(original_mode_);
    armed_ = false;
    return gy::input_mode::Read() == original_mode_;
  }
  ~InputModeRestoreGuard() {
    if (armed_) gy::input_mode::Write(original_mode_);
  }

 private:
  int original_mode_ = gy::input_mode::kSimplified;
  bool armed_ = false;
};

void PumpMessages(DWORD duration_ms) {
  const ULONGLONG deadline = GetTickCount64() + duration_ms;
  MSG message{};
  while (GetTickCount64() < deadline) {
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
}

bool MakeForegroundAndFocus(HWND window, HWND control) {
  const HWND foreground = GetForegroundWindow();
  const DWORD foreground_thread = foreground ? GetWindowThreadProcessId(foreground, nullptr) : 0;
  const DWORD current_thread = GetCurrentThreadId();
  const bool attached = foreground_thread && foreground_thread != current_thread &&
                        AttachThreadInput(current_thread, foreground_thread, TRUE) != FALSE;
  SetForegroundWindow(window);
  BringWindowToTop(window);
  SetActiveWindow(window);
  SetFocus(control);
  if (attached) AttachThreadInput(current_thread, foreground_thread, FALSE);
  PumpMessages(100);
  return GetForegroundWindow() == window && GetFocus() == control;
}

void SendVirtualKey(WORD key) {
  INPUT inputs[2]{};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = key;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = key;
  inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(static_cast<UINT>(std::size(inputs)), inputs, sizeof(INPUT));
}

void SendShiftedVirtualKey(WORD key) {
  // Password/PIN controls must receive symbols such as ! as literal input.
  // Sending the physical chord also confirms that this non-bare Shift is never
  // mistaken for GY's global Chinese/English mode shortcut.
  INPUT inputs[4]{};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_SHIFT;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = key;
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = key;
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_SHIFT;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(static_cast<UINT>(std::size(inputs)), inputs, sizeof(INPUT));
}

class CapsLockRestoreGuard {
 public:
  CapsLockRestoreGuard() : was_enabled_((GetKeyState(VK_CAPITAL) & 1) != 0) {
    if (was_enabled_) {
      SendVirtualKey(VK_CAPITAL);
      PumpMessages(60);
    }
  }
  CapsLockRestoreGuard(const CapsLockRestoreGuard&) = delete;
  CapsLockRestoreGuard& operator=(const CapsLockRestoreGuard&) = delete;
  ~CapsLockRestoreGuard() {
    if (was_enabled_ && (GetKeyState(VK_CAPITAL) & 1) == 0) SendVirtualKey(VK_CAPITAL);
  }

  [[nodiscard]] bool IsTemporarilyOff() const noexcept {
    return !was_enabled_ || (GetKeyState(VK_CAPITAL) & 1) == 0;
  }
  bool RestoreNow() {
    if (was_enabled_ && (GetKeyState(VK_CAPITAL) & 1) == 0) {
      SendVirtualKey(VK_CAPITAL);
      PumpMessages(60);
    }
    return IsRestored();
  }
  [[nodiscard]] bool IsRestored() const noexcept {
    return ((GetKeyState(VK_CAPITAL) & 1) != 0) == was_enabled_;
  }

 private:
  bool was_enabled_ = false;
};

void TypeLowerAscii(const wchar_t* text) {
  for (const wchar_t* cursor = text; *cursor; ++cursor) {
    const wchar_t upper = static_cast<wchar_t>(towupper(*cursor));
    if (upper >= L'A' && upper <= L'Z') {
      SendVirtualKey(static_cast<WORD>(upper));
    } else if (upper >= L'0' && upper <= L'9') {
      SendVirtualKey(static_cast<WORD>(upper));
    }
    PumpMessages(18);
  }
}

std::wstring ReadWindowText(HWND control) {
  const int length = GetWindowTextLengthW(control);
  std::vector<wchar_t> buffer(static_cast<size_t>(length) + 1, L'\0');
  if (length > 0) GetWindowTextW(control, buffer.data(), length + 1);
  return std::wstring(buffer.data());
}

std::wstring ModulePath(HMODULE module) {
  if (!module) return {};
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(module, path, static_cast<DWORD>(std::size(path)));
  return length ? std::wstring(path, length) : std::wstring{};
}

}  // namespace

int wmain() {
  const HKL original_layout = GetKeyboardLayout(0);
  // This real-window utility must never write HKCU or settings.ini directly.
  // It accepts a Chinese starting mode, toggles EN through the normal user
  // shortcut, then restores through the audited InputMode boundary even if a
  // diagnostic fails. The person's persisted mode must finish unchanged.
  const int original_mode = gy::input_mode::Read();
  if (gy::input_mode::IsEnglish(original_mode)) {
    std::wcerr << L"Refusing real-app regression while GY starts in EN. Switch to Chinese first; the test will not change your saved mode.\n";
    return 8;
  }
  InputModeRestoreGuard restore_mode(original_mode);
  // SendInput virtual keys respect Caps Lock. Disable it only for this short
  // controlled window and restore it on every exit path, so the expected
  // lowercase EN word has the same meaning on every tester's desktop.
  CapsLockRestoreGuard caps_lock;
  if (!caps_lock.IsTemporarilyOff()) {
    std::wcerr << L"Cannot temporarily disable Caps Lock for deterministic key regression.\n";
    return 9;
  }
  HINSTANCE instance = GetModuleHandleW(nullptr);
  if (!RegisterWindowClass(instance)) {
    std::wcerr << L"Cannot register real-app test window.\n";
    return 1;
  }
  HMODULE rich_edit = LoadLibraryW(L"Msftedit.dll");
  if (!rich_edit) {
    std::wcerr << L"Cannot load RichEdit TSF text host.\n";
    return 2;
  }

  HWND window = CreateWindowExW(WS_EX_TOOLWINDOW, kWindowClass, L"GY EN regression",
                                WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
                                200, 200, 460, 170, nullptr, nullptr, instance, nullptr);
  if (!window) {
    FreeLibrary(rich_edit);
    std::wcerr << L"Cannot create real-app test window.\n";
    return 3;
  }
  CreateWindowExW(0, L"STATIC", L"normal text", WS_CHILD | WS_VISIBLE,
                  18, 16, 180, 20, window, nullptr, instance, nullptr);
  HWND normal = CreateWindowExW(WS_EX_CLIENTEDGE, MSFTEDIT_CLASS, L"",
                                WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL,
                                18, 38, 410, 26, window, nullptr, instance, nullptr);
  CreateWindowExW(0, L"STATIC", L"password (sensitive direct input)", WS_CHILD | WS_VISIBLE,
                  18, 76, 290, 20, window, nullptr, instance, nullptr);
  HWND password = CreateWindowExW(WS_EX_CLIENTEDGE, MSFTEDIT_CLASS, L"",
                                  WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL | ES_PASSWORD,
                                  18, 98, 410, 26, window, nullptr, instance, nullptr);
  if (!normal || !password) {
    DestroyWindow(window);
    FreeLibrary(rich_edit);
    std::wcerr << L"Cannot create real-app edit controls.\n";
    return 4;
  }
  SendMessageW(password, EM_SETPASSWORDCHAR, L'*', 0);

  ShowWindow(window, SW_SHOWNORMAL);
  UpdateWindow(window);
  if (!MakeForegroundAndFocus(window, normal)) {
    DestroyWindow(window);
    FreeLibrary(rich_edit);
    std::wcerr << L"Regression window did not receive foreground focus; no keys were sent.\n";
    return 5;
  }

  // The Chinese language is associated with GY for this account. Selecting it
  // only for this test thread lets TSF load its current service without
  // changing the user's saved global input preference.
  const HKL chinese_layout = LoadKeyboardLayoutW(L"00000804", KLF_ACTIVATE);
  if (chinese_layout) ActivateKeyboardLayout(chinese_layout, 0);
  PumpMessages(500);

  if (!MakeForegroundAndFocus(window, normal)) {
    DestroyWindow(window);
    FreeLibrary(rich_edit);
    std::wcerr << L"Normal test control lost foreground focus; no keys were sent.\n";
    return 6;
  }
  TypeLowerAscii(L"ni");
  PumpMessages(180);
  restore_mode.Arm();
  SendVirtualKey(VK_SHIFT);  // Must cancel Chinese preedit before entering EN.
  PumpMessages(140);
  TypeLowerAscii(L"englishtest");
  // EN is a real candidate input method: commit its selected word before the
  // focus moves. Otherwise a lingering EN composition can race the first key
  // of the password field and turn this into a test-harness artifact.
  SendVirtualKey(VK_RETURN);
  PumpMessages(260);
  const std::wstring normal_text = ReadWindowText(normal);

  // Return through the normal shortcut before opening the sensitive field.
  // This must recover the exact starting Chinese mode (simplified or
  // traditional), not silently force simplified Chinese through test code.
  SendVirtualKey(VK_SHIFT);
  PumpMessages(140);
  const int mode_after_normal_restore = gy::input_mode::Read();
  // Restore before the sensitive-field portion even if this assertion has
  // failed. That keeps the password test independent and prevents a failed
  // acceptance run from changing the user's subsequent typing mode.
  const bool mode_restored_after_normal_test = restore_mode.RestoreNow();
  const int mode_before_password = gy::input_mode::Read();

  // A password field must stay direct. It receives ordinary ASCII keys without
  // a mode toggle or candidate UI, and it must not modify global input mode.
  if (!MakeForegroundAndFocus(window, password)) {
    DestroyWindow(window);
    FreeLibrary(rich_edit);
    std::wcerr << L"Password test control lost foreground focus; no keys were sent.\n";
    return 7;
  }
  TypeLowerAscii(L"p");
  const std::wstring password_after_p = ReadWindowText(password);
  TypeLowerAscii(L"i");
  const std::wstring password_after_i = ReadWindowText(password);
  TypeLowerAscii(L"n9");
  SendShiftedVirtualKey('1');  // !
  PumpMessages(220);
  const std::wstring password_text = ReadWindowText(password);
  const int mode_after_password_shift = gy::input_mode::Read();

  const std::wstring gy_module = ModulePath(GetModuleHandleW(kGyImeModule));
  std::wcout << L"normal=" << normal_text << L"\n";
  std::wcout << L"password=" << password_text << L"\n";
  std::wcout << L"password_after_p=" << password_after_p << L"\n";
  std::wcout << L"password_after_i=" << password_after_i << L"\n";
  std::wcout << L"mode_after_normal_restore=" << mode_after_normal_restore << L"\n";
  std::wcout << L"mode_restored_after_normal_test=" << (mode_restored_after_normal_test ? L"true" : L"false") << L"\n";
  std::wcout << L"mode_before_password=" << mode_before_password << L"\n";
  std::wcout << L"mode_after_password_shift=" << mode_after_password_shift << L"\n";
  std::wcout << L"caps_lock_initially_off=" << (caps_lock.IsTemporarilyOff() ? L"true" : L"false") << L"\n";
  std::wcout << L"gy_module=" << (gy_module.empty() ? L"(not loaded)" : gy_module) << L"\n";

  DestroyWindow(window);
  FreeLibrary(rich_edit);
  if (original_layout) ActivateKeyboardLayout(original_layout, 0);
  if (gy_module.empty()) return 10;
  if (normal_text != L"englishtest") return 11;
  if (mode_after_normal_restore != original_mode || !mode_restored_after_normal_test ||
      mode_before_password != original_mode || mode_after_password_shift != original_mode) return 12;
  if (password_text != L"pin9!") return 13;
  if (!caps_lock.RestoreNow()) return 14;
  return 0;
}
