#include <windows.h>

#include <iostream>
#include <string>

#include <rime_api.h>

namespace {
std::wstring ParentDirectory(std::wstring path) {
  path.resize(path.find_last_of(L"\\/"));
  return path;
}

std::string Utf8(const std::wstring& text) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), size, nullptr, nullptr);
  return result;
}
}  // namespace

int main() {
  wchar_t module_path[MAX_PATH]{};
  GetModuleFileNameW(nullptr, module_path, MAX_PATH);
  const std::wstring module_dir = ParentDirectory(module_path);
  const std::wstring shared = module_dir + L"\\rime-data\\shared";
  wchar_t local_app_data[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data, MAX_PATH)) return 2;
  const std::wstring user = std::wstring(local_app_data) + L"\\GYInput\\rime";
  const std::string shared_utf8 = Utf8(shared);
  const std::string user_utf8 = Utf8(user);
  std::cout << "shared=" << shared_utf8 << "\nuser=" << user_utf8 << "\n";

  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = shared_utf8.c_str();
  traits.user_data_dir = user_utf8.c_str();
  traits.distribution_name = "GY Input Method";
  traits.distribution_code_name = "gyime";
  traits.distribution_version = "0.2";
  traits.app_name = "rime.gyime.path-smoke";
  traits.min_log_level = 2;

  RimeApi* rime = rime_get_api();
  std::cout << "api=" << static_cast<bool>(rime) << "\n";
  if (!rime) return 3;
  rime->setup(&traits);
  rime->initialize(&traits);
  const Bool maintaining = rime->start_maintenance(True);
  std::cout << "maintenance=" << maintaining << "\n";
  if (maintaining) rime->join_maintenance_thread();
  const RimeSessionId session = rime->create_session();
  std::cout << "session=" << session << "\n";
  if (!session) return 4;
  const Bool selected = rime->select_schema(session, "luna_pinyin");
  std::cout << "selected=" << selected << "\n";
  rime->destroy_session(session);
  rime->finalize();
  return selected ? 0 : 5;
}
