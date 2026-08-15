#include "EnglishAssist.h"

#include "InputMode.h"
#include "SettingsFile.h"

#include <windows.h>
#include <spellcheck.h>

#include <algorithm>
#include <array>

namespace gy::english_assist {
namespace {

// spellcheck.h declares this CLSID for consumers that link the platform's
// generated UUID library. Keep the value local so the TSF DLL has no extra
// import-library dependency beyond standard COM on supported Windows builds.
constexpr CLSID kSpellCheckerFactoryClsid = {
    0x7AB36653, 0x1796, 0x484B, {0xBD, 0xFA, 0xE7, 0x4F, 0x1D, 0xB7, 0xC1, 0xDC}};

bool EqualsAsciiIgnoreCase(std::wstring_view left, std::wstring_view right) noexcept {
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

void AddUnique(std::vector<std::wstring>* results, std::wstring_view value,
               std::wstring_view original, unsigned maximum) {
  if (!results || value.empty() || results->size() >= maximum ||
      EqualsAsciiIgnoreCase(value, original)) return;
  if (std::any_of(results->begin(), results->end(), [value](const std::wstring& existing) {
        return EqualsAsciiIgnoreCase(existing, value);
      })) return;
  results->emplace_back(value);
}

void AddBuiltInCorrections(std::wstring_view text, std::vector<std::wstring>* results,
                           unsigned maximum) {
  // A deterministic offline floor for frequent mistakes. Windows' installed
  // spell checker supplements this list when an en-US language pack exists;
  // the input method never downloads words or sends selected text to a server.
  constexpr std::array<std::pair<std::wstring_view, std::wstring_view>, 12> kCorrections{{
      {L"adress", L"address"}, {L"definately", L"definitely"}, {L"enviroment", L"environment"},
      {L"goverment", L"government"}, {L"occured", L"occurred"}, {L"recieve", L"receive"},
      {L"seperate", L"separate"}, {L"teh", L"the"}, {L"thier", L"their"},
      {L"untill", L"until"}, {L"wich", L"which"}, {L"wierd", L"weird"},
  }};
  for (const auto& [misspelled, correction] : kCorrections) {
    if (EqualsAsciiIgnoreCase(text, misspelled)) AddUnique(results, correction, text, maximum);
  }
}

void AddWindowsSuggestions(std::wstring_view text, std::vector<std::wstring>* results,
                           unsigned maximum) {
  if (!results || results->size() >= maximum) return;
  const HRESULT initialize = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool uninitialize = SUCCEEDED(initialize);

  ISpellCheckerFactory* factory = nullptr;
  HRESULT hr = CoCreateInstance(kSpellCheckerFactoryClsid, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory));
  if (SUCCEEDED(hr) && factory) {
    BOOL supported = FALSE;
    hr = factory->IsSupported(L"en-US", &supported);
    ISpellChecker* checker = nullptr;
    if (SUCCEEDED(hr) && supported) hr = factory->CreateSpellChecker(L"en-US", &checker);
    if (SUCCEEDED(hr) && checker) {
      IEnumString* values = nullptr;
      hr = checker->Suggest(std::wstring(text).c_str(), &values);
      if (SUCCEEDED(hr) && values) {
        while (results->size() < maximum) {
          LPOLESTR item = nullptr;
          ULONG fetched = 0;
          if (values->Next(1, &item, &fetched) != S_OK || fetched != 1 || !item) break;
          AddUnique(results, item, text, maximum);
          CoTaskMemFree(item);
        }
        values->Release();
      }
      checker->Release();
    }
    factory->Release();
  }
  if (uninitialize) CoUninitialize();
}

}  // namespace

bool IsEnabled() {
  const std::wstring path = gy::input_mode::SettingsPath();
  return !path.empty() && GetPrivateProfileIntW(L"EnglishAssist", L"Enabled", 0, path.c_str()) != 0;
}

void SetEnabled(bool enabled) {
  const std::wstring path = gy::input_mode::SettingsPath();
  if (path.empty() || !gy::settings_file::EnsureUnicodeIniFile(path)) return;
  WritePrivateProfileStringW(L"EnglishAssist", L"Enabled", enabled ? L"1" : L"0", path.c_str());
}

bool IsEligibleSelection(std::wstring_view text) noexcept {
  if (text.size() < 2 || text.size() > 64) return false;
  for (const wchar_t character : text) {
    const bool latin = (character >= L'a' && character <= L'z') ||
                       (character >= L'A' && character <= L'Z');
    if (!latin && character != L'\'' && character != L'-') return false;
  }
  return true;
}

std::vector<std::wstring> Suggest(std::wstring_view text, unsigned maximum) {
  maximum = std::clamp(maximum, 1u, kMaximumSuggestions);
  std::vector<std::wstring> results;
  if (!IsEligibleSelection(text)) return results;
  AddBuiltInCorrections(text, &results, maximum);
  AddWindowsSuggestions(text, &results, maximum);
  return results;
}

std::wstring ResolveCommitText(std::wstring_view original,
                              const std::vector<std::wstring>& suggestions,
                              unsigned index, bool accept_suggestion) {
  if (!accept_suggestion || index >= suggestions.size()) return std::wstring(original);
  return suggestions[index];
}

}  // namespace gy::english_assist
