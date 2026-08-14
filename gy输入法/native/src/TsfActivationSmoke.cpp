#include <windows.h>
#include <msctf.h>

#include <iostream>

#include "Guids.h"

namespace {

using CreateThreadMgrFn = HRESULT (WINAPI*)(ITfThreadMgr**);
using CreateProfilesFn = HRESULT (WINAPI*)(ITfInputProcessorProfiles**);

struct TsfFactories {
  HMODULE module = nullptr;
  CreateThreadMgrFn create_thread_manager = nullptr;
  CreateProfilesFn create_profiles = nullptr;

  bool Load() {
    module = LoadLibraryW(L"msctf.dll");
    if (!module) return false;
    create_thread_manager = reinterpret_cast<CreateThreadMgrFn>(
        GetProcAddress(module, "TF_CreateThreadMgr"));
    create_profiles = reinterpret_cast<CreateProfilesFn>(
        GetProcAddress(module, "TF_CreateInputProcessorProfiles"));
    return create_thread_manager && create_profiles;
  }

  ~TsfFactories() { if (module) FreeLibrary(module); }
};

using DllGetClassObjectFn = HRESULT (WINAPI*)(REFCLSID, REFIID, void**);

struct ServiceModule {
  HMODULE module = nullptr;

  HRESULT Create(ITfTextInputProcessorEx** service) {
    if (!service) return E_INVALIDARG;
    *service = nullptr;
    wchar_t* test_dll = nullptr;
    size_t test_dll_length = 0;
    if (_wdupenv_s(&test_dll, &test_dll_length, L"GY_TSF_SMOKE_DLL") != 0) return E_FAIL;
    if (!test_dll || !*test_dll) {
      free(test_dll);
      return CoCreateInstance(CLSID_GyTextService, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(service));
    }
    module = LoadLibraryW(test_dll);
    free(test_dll);
    if (!module) return HRESULT_FROM_WIN32(GetLastError());
    const auto get_class_object = reinterpret_cast<DllGetClassObjectFn>(
        GetProcAddress(module, "DllGetClassObject"));
    if (!get_class_object) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    IClassFactory* factory = nullptr;
    HRESULT hr = get_class_object(CLSID_GyTextService, IID_PPV_ARGS(&factory));
    if (SUCCEEDED(hr) && factory) {
      hr = factory->CreateInstance(nullptr, IID_PPV_ARGS(service));
      factory->Release();
    }
    return hr;
  }

  ~ServiceModule() { if (module) FreeLibrary(module); }
};

bool SameGuid(REFGUID left, REFGUID right) {
  return InlineIsEqualGUID(left, right) != FALSE;
}

std::wstring GuidText(REFGUID guid) {
  wchar_t text[64]{};
  StringFromGUID2(guid, text, static_cast<int>(std::size(text)));
  return text;
}

bool IsTruthyEnvironmentValue(const wchar_t* name) {
  wchar_t value[8]{};
  const DWORD length = GetEnvironmentVariableW(name, value, static_cast<DWORD>(std::size(value)));
  return length > 0 && lstrcmpiW(value, L"0") != 0 && lstrcmpiW(value, L"false") != 0;
}

void WriteEnumeratedProfiles(ITfInputProcessorProfileMgr* profiles) {
  if (!profiles) return;
  IEnumTfInputProcessorProfiles* values = nullptr;
  const HRESULT hr = profiles->EnumProfiles(0, &values);
  std::wcerr << L"TSF EnumProfiles(all)=0x" << std::hex << static_cast<unsigned long>(hr) << L"\n";
  if (FAILED(hr) || !values) return;
  TF_INPUTPROCESSORPROFILE profile{};
  ULONG fetched = 0;
  unsigned index = 0;
  while (values->Next(1, &profile, &fetched) == S_OK && fetched == 1 && index++ < 64) {
    std::wcerr << L"  profile lang=0x" << std::hex << profile.langid
               << L" clsid=" << GuidText(profile.clsid)
               << L" guid=" << GuidText(profile.guidProfile)
               << L" flags=0x" << profile.dwFlags << L"\n";
  }
  values->Release();
}

void WriteLanguageProfiles(ITfInputProcessorProfiles* profiles, LANGID language) {
  if (!profiles) return;
  IEnumTfLanguageProfiles* values = nullptr;
  const HRESULT hr = profiles->EnumLanguageProfiles(language, &values);
  std::wcerr << L"TSF EnumLanguageProfiles(0x" << std::hex << language
             << L")=0x" << static_cast<unsigned long>(hr) << L"\n";
  if (FAILED(hr) || !values) return;
  TF_LANGUAGEPROFILE profile{};
  ULONG fetched = 0;
  unsigned index = 0;
  while (values->Next(1, &profile, &fetched) == S_OK && fetched == 1 && index++ < 64) {
    std::wcerr << L"  language-profile clsid=" << GuidText(profile.clsid)
               << L" guid=" << GuidText(profile.guidProfile)
               << L" category=" << GuidText(profile.catid)
               << L" active=" << profile.fActive << L"\n";
  }
  values->Release();
}

}  // namespace

int wmain() {
  // This is intentionally FORPROCESS only: it proves that Windows can load
  // and activate the registered GY TIP without changing the user's desktop
  // language bar, keyboard selection, or another application's input state.
  const HRESULT initialize = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool uninitialize = SUCCEEDED(initialize);
  if (FAILED(initialize) && initialize != RPC_E_CHANGED_MODE) {
    std::wcerr << L"CoInitializeEx failed: 0x" << std::hex << static_cast<unsigned long>(initialize) << L"\n";
    return 1;
  }

  TsfFactories factories;
  if (!factories.Load()) {
    if (uninitialize) CoUninitialize();
    std::wcerr << L"msctf.dll does not expose the desktop TSF factory helpers\n";
    return 2;
  }

  // A text service is activated by an input process with an active TSF thread
  // manager. Profile APIs are callable without one on some Windows builds,
  // but that omits the same session initialization used by Notepad, Chromium
  // and Terminal and can make a valid profile appear absent.
  ITfThreadMgr* thread_manager = nullptr;
  HRESULT hr = factories.create_thread_manager(&thread_manager);
  TfClientId application_client_id = TF_CLIENTID_NULL;
  if (SUCCEEDED(hr) && thread_manager) hr = thread_manager->Activate(&application_client_id);
  if (FAILED(hr) || !thread_manager || application_client_id == TF_CLIENTID_NULL) {
    if (thread_manager) thread_manager->Release();
    if (uninitialize) CoUninitialize();
    std::wcerr << L"Cannot activate a TSF thread manager: 0x" << std::hex
               << static_cast<unsigned long>(hr) << L"\n";
    return 2;
  }

  ITfInputProcessorProfiles* legacy_profiles = nullptr;
  hr = factories.create_profiles(&legacy_profiles);
  ITfInputProcessorProfileMgr* profiles = nullptr;
  if (SUCCEEDED(hr) && legacy_profiles) {
    hr = legacy_profiles->QueryInterface(IID_PPV_ARGS(&profiles));
  }
  if (FAILED(hr) || !profiles) {
    if (legacy_profiles) legacy_profiles->Release();
    thread_manager->Deactivate();
    thread_manager->Release();
    if (uninitialize) CoUninitialize();
    std::wcerr << L"Cannot create TSF profile manager: 0x" << std::hex << static_cast<unsigned long>(hr) << L"\n";
    return 3;
  }
  WriteEnumeratedProfiles(profiles);

  constexpr LANGID kChineseSimplified = MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED);
  WriteLanguageProfiles(legacy_profiles, kChineseSimplified);
  BOOL enabled = FALSE;
  const HRESULT enabled_hr = legacy_profiles->IsEnabledLanguageProfile(
      CLSID_GyTextService, kChineseSimplified, GUID_PROFILE_GY_PINYIN, &enabled);
  LANGID current_language = 0;
  const HRESULT current_language_hr = legacy_profiles->GetCurrentLanguage(&current_language);
  const bool request_session_activation = IsTruthyEnvironmentValue(L"GY_TSF_SMOKE_ACTIVATE");
  const bool request_default_profile = IsTruthyEnvironmentValue(L"GY_TSF_SMOKE_SET_DEFAULT");
  HRESULT requested_default_hr = S_FALSE;
  if (request_default_profile) {
    requested_default_hr = legacy_profiles->SetDefaultLanguageProfile(
        kChineseSimplified, CLSID_GyTextService, GUID_PROFILE_GY_PINYIN);
  }
  HRESULT requested_activation_hr = S_FALSE;
  if (request_session_activation && SUCCEEDED(current_language_hr) &&
      current_language == kChineseSimplified) {
    requested_activation_hr = legacy_profiles->ActivateLanguageProfile(
        CLSID_GyTextService, kChineseSimplified, GUID_PROFILE_GY_PINYIN);
  }
  LANGID gy_active_language = 0;
  GUID gy_active_profile{};
  const HRESULT gy_active_hr = legacy_profiles->GetActiveLanguageProfile(
      CLSID_GyTextService, &gy_active_language, &gy_active_profile);
  legacy_profiles->Release();
  if (FAILED(enabled_hr) || !enabled) {
    profiles->Release();
    thread_manager->Deactivate();
    thread_manager->Release();
    if (uninitialize) CoUninitialize();
    std::wcerr << L"GY profile is not enabled for the current user: 0x" << std::hex
               << static_cast<unsigned long>(enabled_hr) << L"\n";
    return 4;
  }
  if (request_session_activation && FAILED(requested_activation_hr)) {
    profiles->Release();
    thread_manager->Deactivate();
    thread_manager->Release();
    if (uninitialize) CoUninitialize();
    std::wcerr << L"Windows could not activate GY for the current Chinese input session: 0x"
               << std::hex << static_cast<unsigned long>(requested_activation_hr) << L"\n";
    return 5;
  }
  if (request_default_profile && FAILED(requested_default_hr)) {
    profiles->Release();
    thread_manager->Deactivate();
    thread_manager->Release();
    if (uninitialize) CoUninitialize();
    std::wcerr << L"Windows could not set GY as the default Chinese text profile: 0x"
               << std::hex << static_cast<unsigned long>(requested_default_hr) << L"\n";
    return 6;
  }

  // The profile manager's enumeration can omit enabled third-party TIPs until
  // a language-bar session has switched to them. Do not mutate the user's
  // desktop merely to force that cache. Create the registered COM service
  // instead: this proves the installed DLL and dependencies can load. TSF
  // itself, rather than an arbitrary test client, owns ActivateEx and gives a
  // real foreground text process its service client id.
  ServiceModule service_module;
  ITfTextInputProcessorEx* service = nullptr;
  hr = service_module.Create(&service);
  if (FAILED(hr) || !service) {
    profiles->Release();
    thread_manager->Deactivate();
    thread_manager->Release();
    if (uninitialize) CoUninitialize();
    std::wcerr << L"GY text service could not be created from its registered DLL: 0x"
               << std::hex << static_cast<unsigned long>(hr) << L"\n";
    return 5;
  }
  service->Release();

  // Keep the modern manager query as non-blocking diagnostics: this Windows
  // session currently returns keyboard layouts only even for other enabled
  // third-party TIPs. The enabled-profile check and direct service creation
  // above are the release assertions.
  TF_INPUTPROCESSORPROFILE registered{};
  const HRESULT query_hr = profiles->GetProfile(
      TF_PROFILETYPE_INPUTPROCESSOR, kChineseSimplified, CLSID_GyTextService,
      GUID_PROFILE_GY_PINYIN, nullptr, &registered);
  const bool query_matches = SUCCEEDED(query_hr) &&
      SameGuid(registered.clsid, CLSID_GyTextService) &&
      SameGuid(registered.guidProfile, GUID_PROFILE_GY_PINYIN);

  profiles->Release();
  thread_manager->Deactivate();
  thread_manager->Release();
  if (uninitialize) CoUninitialize();
  if (!query_matches) {
    // Windows 11 may omit an enabled third-party TIP from this manager cache.
    // Keep the condition visible in CI logs without treating it as a false
    // product failure; installed-user activation is handled by TSF itself.
    std::wcerr << L"GY service creation passed, but GetProfile cache returned: 0x"
               << std::hex << static_cast<unsigned long>(query_hr) << L"\n";
  }
  std::wcerr << L"TSF current language=0x" << std::hex << current_language
             << L" hr=0x" << static_cast<unsigned long>(current_language_hr)
             << L"; GY active profile=0x" << static_cast<unsigned long>(gy_active_hr)
             << L" lang=0x" << gy_active_language
             << L" guid=" << GuidText(gy_active_profile) << L"\n";
  if (request_session_activation) {
    std::wcerr << L"GY requested session activation=0x" << std::hex
               << static_cast<unsigned long>(requested_activation_hr) << L"\n";
  }
  if (request_default_profile) {
    std::wcerr << L"GY requested default profile=0x" << std::hex
               << static_cast<unsigned long>(requested_default_hr) << L"\n";
  }
  return 0;
}
