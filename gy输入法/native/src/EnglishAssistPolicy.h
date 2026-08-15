#pragma once

#include <array>
#include <string_view>

namespace gy::english_assist {

constexpr bool EqualsAsciiIgnoreCase(std::wstring_view left, std::wstring_view right) noexcept {
  if (left.size() != right.size()) return false;
  for (size_t index = 0; index < left.size(); ++index) {
    wchar_t a = left[index];
    wchar_t b = right[index];
    if (a >= L'A' && a <= L'Z') a = static_cast<wchar_t>(a - L'A' + L'a');
    if (b >= L'A' && b <= L'Z') b = static_cast<wchar_t>(b - L'A' + L'a');
    if (a != b) return false;
  }
  return true;
}

// English Assist is a writing tool, not a code or shell tool. This is a
// conservative deny-list for known desktop IDE and terminal hosts. It layers
// on top of the stronger semantic InputScope exclusion in GyIme.cpp.
constexpr bool IsExcludedApplication(std::wstring_view executable) noexcept {
  constexpr std::array<std::wstring_view, 22> kExcluded = {
      L"alacritty.exe", L"atom.exe", L"bash.exe", L"clion64.exe", L"cmd.exe",
      L"code.exe", L"codium.exe", L"conhost.exe", L"devenv.exe", L"goland64.exe",
      L"idea64.exe", L"mintty.exe", L"nvim-qt.exe", L"powershell.exe", L"putty.exe",
      L"pwsh.exe", L"pycharm64.exe", L"rider64.exe", L"sublime_text.exe", L"wezterm-gui.exe",
      L"windowsterminal.exe", L"wsl.exe"};
  for (const std::wstring_view blocked : kExcluded) {
    if (EqualsAsciiIgnoreCase(executable, blocked)) return true;
  }
  return false;
}

constexpr bool CanActivate(bool enabled, bool english_mode, bool automatic_direct,
                           std::wstring_view executable) noexcept {
  return enabled && english_mode && !automatic_direct && !IsExcludedApplication(executable);
}

}  // namespace gy::english_assist
