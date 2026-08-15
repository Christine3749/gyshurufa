#include "InputScopeProbe.h"

#include "InputScopeCache.h"
#include "InputScopePolicy.h"

#include <windows.h>
#include <uiautomation.h>

#include <memory>
#include <thread>

namespace {

struct ProbeState {
  HANDLE stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  gy::input_scope_cache::Writer cache;
  ~ProbeState() { if (stop_event) CloseHandle(stop_event); }
};

bool MetadataMatches(IUIAutomationElement* element, bool* direct, bool* sensitive) {
  if (!element || !direct || !sensitive) return false;
  VARIANT value;
  VariantInit(&value);
  if (SUCCEEDED(element->GetCurrentPropertyValue(UIA_IsPasswordPropertyId, &value)) &&
      value.vt == VT_BOOL && value.boolVal == VARIANT_TRUE) {
    *direct = true;
    *sensitive = true;
  }
  VariantClear(&value);
  for (const PROPERTYID property : {UIA_NamePropertyId, UIA_AutomationIdPropertyId, UIA_HelpTextPropertyId}) {
    VariantInit(&value);
    if (SUCCEEDED(element->GetCurrentPropertyValue(property, &value)) && value.vt == VT_BSTR && value.bstrVal) {
      *direct = *direct || gy::input_scope::IsEnglishAutomationHint(value.bstrVal);
      *sensitive = *sensitive || gy::input_scope::IsSensitiveAutomationHint(value.bstrVal);
    }
    VariantClear(&value);
  }
  return true;
}

void RunProbe(std::shared_ptr<ProbeState> state) {
  if (!state || !state->stop_event) return;
  const HRESULT initialize = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  IUIAutomation* automation = nullptr;
  if (SUCCEEDED(initialize)) CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER,
                                               IID_PPV_ARGS(&automation));
  while (WaitForSingleObject(state->stop_event, 150) == WAIT_TIMEOUT) {
    const HWND foreground = GetForegroundWindow();
    DWORD process_id = 0;
    if (!foreground || !GetWindowThreadProcessId(foreground, &process_id) || !automation) {
      state->cache.Publish(foreground, process_id, false, false);
      continue;
    }
    // UIA can synchronously enter another app. This worker is deliberately
    // detached from Host IPC and UI threads; a wedged provider can only make
    // its own snapshot stale, never delay a keystroke or candidate response.
    IUIAutomationElement* element = nullptr;
    bool direct = false;
    bool sensitive = false;
    if (SUCCEEDED(automation->GetFocusedElement(&element)) && element) {
      MetadataMatches(element, &direct, &sensitive);
      element->Release();
    }
    state->cache.Publish(foreground, process_id, direct, sensitive);
  }
  if (automation) automation->Release();
  if (SUCCEEDED(initialize)) CoUninitialize();
}

}  // namespace

void StartAsyncInputScopeProbe() {
#ifdef GY_TESTING
  // Isolated Hosts never inspect the desktop or create a live shared mapping.
  return;
#else
  auto state = std::make_shared<ProbeState>();
  if (!state->stop_event) return;
  // Do not join this thread during Host shutdown: a third-party UIA provider
  // is permitted to stall. Windows tears the worker down with the Host
  // process, while normal Host IPC continues independently throughout.
  std::thread(RunProbe, std::move(state)).detach();
#endif
}
