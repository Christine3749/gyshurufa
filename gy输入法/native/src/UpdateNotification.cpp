#include "UpdateNotification.h"

#include <windows.h>

#include <winrt/base.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.UI.Notifications.h>

#include <string>

namespace {
constexpr wchar_t kAppUserModelId[] = L"GYInput.Desktop";

std::wstring EscapeXml(const std::wstring& text) {
  std::wstring result;
  result.reserve(text.size());
  for (const wchar_t character : text) {
    switch (character) {
      case L'&': result += L"&amp;"; break;
      case L'<': result += L"&lt;"; break;
      case L'>': result += L"&gt;"; break;
      case L'\"': result += L"&quot;"; break;
      case L'\'': result += L"&apos;"; break;
      default: result.push_back(character); break;
    }
  }
  return result;
}
}  // namespace

bool ShowGyUpdateNotification(const std::wstring& version) {
  if (version.empty()) return false;
  bool apartment_initialized = false;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    apartment_initialized = true;
    const std::wstring safe_version = EscapeXml(version);
    const std::wstring xml_text =
        L"<toast launch=\"gyinput://update/install\">"
        L"<visual><binding template=\"ToastGeneric\">"
        L"<text>GY 输入法有新版本</text>"
        L"<text>v" + safe_version +
        L" 已准备好。下载后会校验 SHA-256 和签名。</text>"
        L"</binding></visual>"
        L"<actions>"
        L"<action content=\"安装更新\" arguments=\"gyinput://update/install\" activationType=\"protocol\"/>"
        L"<action content=\"稍后提醒\" arguments=\"gyinput://update/snooze\" activationType=\"protocol\"/>"
        L"</actions></toast>";

    winrt::Windows::Data::Xml::Dom::XmlDocument document;
    document.LoadXml(winrt::hstring(xml_text));
    auto notifier = winrt::Windows::UI::Notifications::ToastNotificationManager::CreateToastNotifier(kAppUserModelId);
    notifier.Show(winrt::Windows::UI::Notifications::ToastNotification(document));
    winrt::uninit_apartment();
    apartment_initialized = false;
    return true;
  } catch (...) {
    if (apartment_initialized) {
      try { winrt::uninit_apartment(); } catch (...) {}
    }
    return false;
  }
}
