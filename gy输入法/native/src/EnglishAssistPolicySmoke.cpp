#include "EnglishAssistPolicy.h"

int wmain() {
  if (!gy::english_assist::CanActivate(true, true, false, L"chrome.exe") ||
      gy::english_assist::CanActivate(false, true, false, L"chrome.exe") ||
      gy::english_assist::CanActivate(true, false, false, L"chrome.exe") ||
      gy::english_assist::CanActivate(true, true, true, L"chrome.exe")) return 1;

  for (const std::wstring_view executable : {
           L"Code.exe", L"WINDOWSTERMINAL.EXE", L"pwsh.exe", L"conhost.exe",
           L"idea64.exe", L"sublime_text.exe"}) {
    if (!gy::english_assist::IsExcludedApplication(executable) ||
        gy::english_assist::CanActivate(true, true, false, executable)) return 2;
  }
  if (gy::english_assist::IsExcludedApplication(L"notepad.exe")) return 3;
  return 0;
}
