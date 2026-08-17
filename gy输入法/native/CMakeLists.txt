cmake_minimum_required(VERSION 3.21)
project(GyIme LANGUAGES CXX RC)

enable_testing()

# Ship the MSVC runtime inside GY binaries so TSF registration does not depend
# on a separately installed Visual C++ Redistributable.
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# The Windows source is used both inside the local multi-project workspace and
# as the root of the standalone gyshurufa GitHub repository. Prefer the
# workspace manifest when present, then fall back to the repository manifest.
get_filename_component(GY_WORKSPACE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
get_filename_component(GY_REPOSITORY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(GY_RELEASE_MANIFEST "${GY_WORKSPACE_ROOT}/release/release.json")
if(NOT EXISTS "${GY_RELEASE_MANIFEST}")
  set(GY_RELEASE_MANIFEST "${GY_REPOSITORY_ROOT}/release/release.json")
endif()
if(NOT EXISTS "${GY_RELEASE_MANIFEST}")
  message(FATAL_ERROR "Canonical release manifest is missing: ${GY_RELEASE_MANIFEST}")
endif()
file(READ "${GY_RELEASE_MANIFEST}" GY_RELEASE_MANIFEST_JSON)
string(JSON GY_MANIFEST_VERSION GET "${GY_RELEASE_MANIFEST_JSON}" windows version)
string(JSON GY_MANIFEST_CORE_VERSION GET "${GY_RELEASE_MANIFEST_JSON}" windows coreVersion)
string(JSON GY_MANIFEST_HOST_VERSION GET "${GY_RELEASE_MANIFEST_JSON}" windows hostVersion)
if(NOT GY_MANIFEST_VERSION STREQUAL GY_MANIFEST_CORE_VERSION OR NOT GY_MANIFEST_VERSION STREQUAL GY_MANIFEST_HOST_VERSION)
  message(FATAL_ERROR "release.json Windows package/core/host versions must match exactly")
endif()
if(DEFINED GY_VERSION AND NOT GY_VERSION STREQUAL "dev" AND NOT GY_VERSION STREQUAL GY_MANIFEST_VERSION)
  message(FATAL_ERROR "-DGY_VERSION=${GY_VERSION} conflicts with canonical release.json version ${GY_MANIFEST_VERSION}")
endif()
set(GY_VERSION "${GY_MANIFEST_VERSION}" CACHE STRING "GY engine host version" FORCE)
message(STATUS "GY canonical release version: ${GY_VERSION}")

# Every installed binary carries the same version as the canonical release
# contract, so Explorer, diagnostics, repair, and support logs agree.
string(REPLACE "." "," GY_VERSION_RESOURCE_PARTS "${GY_VERSION}")
set(GY_VERSION_RESOURCE_COMMAS "${GY_VERSION_RESOURCE_PARTS},0")
function(gy_configure_version_resource output file_type internal_name description)
  set(GY_VERSION_FILE_TYPE "${file_type}")
  set(GY_VERSION_INTERNAL_NAME "${internal_name}")
  set(GY_VERSION_FILE_DESCRIPTION "${description}")
  configure_file("${CMAKE_CURRENT_SOURCE_DIR}/src/GyVersion.rc.in" "${output}" @ONLY)
endfunction()
set(GY_IME_VERSION_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/GyImeVersion.rc")
set(GY_HOST_VERSION_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/GyImeHostVersion.rc")
set(GY_HEALTH_VERSION_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/GyImeHealthVersion.rc")
gy_configure_version_resource("${GY_IME_VERSION_RESOURCE}" "VFT_DLL" "GyIme" "GY Input Method TSF Compatibility Layer")
gy_configure_version_resource("${GY_HOST_VERSION_RESOURCE}" "VFT_APP" "GyImeHost" "GY Input Method Host")
gy_configure_version_resource("${GY_HEALTH_VERSION_RESOURCE}" "VFT_APP" "GyImeHealth" "GY Input Method Health Check")

if(NOT WIN32)
  message(FATAL_ERROR "GY 输入法只能在 Windows 上构建。")
endif()

# This folder is the complete, redistributable offline Rime runtime.
set(GY_RIME_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/runtime/rime" CACHE PATH "Bundled librime runtime root" FORCE)
set(GY_RIME_RUNTIME_ROOT "${GY_RIME_ROOT}" CACHE PATH "Bundled GY Rime data root" FORCE)
if(NOT EXISTS "${GY_RIME_ROOT}/include/rime_api.h" OR NOT EXISTS "${GY_RIME_ROOT}/lib/rime.lib" OR NOT EXISTS "${GY_RIME_ROOT}/lib/rime.dll")
  message(FATAL_ERROR "The bundled librime runtime is incomplete under ${GY_RIME_ROOT}.")
endif()
set(GY_RIME_BUILD_ROOT "${GY_RIME_RUNTIME_ROOT}/shared/build")
set(GY_REQUIRED_RIME_DATA
  "default.yaml"
  "luna_pinyin.schema.yaml"
  "luna_pinyin.table.bin"
  "luna_pinyin.reverse.bin"
  "luna_pinyin.prism.bin"
)
foreach(GY_RIME_DATA_FILE IN LISTS GY_REQUIRED_RIME_DATA)
  if(NOT EXISTS "${GY_RIME_BUILD_ROOT}/${GY_RIME_DATA_FILE}")
    message(FATAL_ERROR "The bundled luna-pinyin runtime is incomplete: missing ${GY_RIME_BUILD_ROOT}/${GY_RIME_DATA_FILE}.")
  endif()
endforeach()
set(GY_RIME_OPENCC_ROOT "${GY_RIME_RUNTIME_ROOT}/shared/opencc")
set(GY_REQUIRED_OPENCC_DATA
  "OPENCC_SOURCE.json"
  "t2s.json"
  "t2hk.json"
  "t2tw.json"
  "CJK_Compatibility_Ideographs.ocd2"
  "CJK_Compatibility_Ideographs.txt"
  "TSPhrases.ocd2"
  "TSPhrases.txt"
  "TSCharactersExt.ocd2"
  "TSCharactersExt.txt"
  "TSCharacters.ocd2"
  "TSCharacters.txt"
  "HKVariantsPhrases.ocd2"
  "HKVariants.ocd2"
  "TWVariantsPhrases.ocd2"
  "TWVariants.ocd2"
)
foreach(GY_OPENCC_DATA_FILE IN LISTS GY_REQUIRED_OPENCC_DATA)
  if(NOT EXISTS "${GY_RIME_OPENCC_ROOT}/${GY_OPENCC_DATA_FILE}")
    message(FATAL_ERROR "The bundled OpenCC runtime is incomplete: missing ${GY_RIME_OPENCC_ROOT}/${GY_OPENCC_DATA_FILE}.")
  endif()
endforeach()
if(NOT EXISTS "${GY_RIME_RUNTIME_ROOT}/LICENSE.opencc.txt")
  message(FATAL_ERROR "The bundled OpenCC Apache-2.0 license is missing.")
endif()

# The TSF DLL remains a small, stable compatibility layer inside each target
# app. It talks to GyImeHost over a local named pipe for lookup/ranking work.
add_library(GyIme SHARED
  src/GyIme.cpp
  src/EnglishAssist.cpp
  src/GyIme.def
  src/HostedPinyinEngine.cpp
  src/SelectionCallback.cpp
  "${GY_IME_VERSION_RESOURCE}"
)
target_compile_features(GyIme PRIVATE cxx_std_20)
target_compile_definitions(GyIme PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
                                         GY_HOST_VERSION="${GY_VERSION}")
if(MSVC)
  target_compile_options(GyIme PRIVATE /utf-8)
endif()
target_include_directories(GyIme PRIVATE src)
target_link_libraries(GyIme PRIVATE ole32 advapi32 uuid)
# Field diagnosis: configure with -DGY_IME_TRACE=ON to log TSF focus/key/edit
# events to %TEMP%/GyIme.trace.log without touching source. Stays off for
# release and installer builds.
option(GY_IME_TRACE "Log GyIme TSF events to %TEMP%/GyIme.trace.log" OFF)
if(GY_IME_TRACE)
  target_compile_definitions(GyIme PRIVATE GY_IME_TRACE)
endif()
option(GY_REGISTRATION_TRACE "Log GyIme COM/TSF registration stages to %TEMP%/GyIme.registration.log" OFF)
if(GY_REGISTRATION_TRACE)
  target_compile_definitions(GyIme PRIVATE GY_REGISTRATION_TRACE)
endif()
set_target_properties(GyIme PROPERTIES
  OUTPUT_NAME "GyIme"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# The updatable out-of-process engine. Later Host-only releases can update
# dictionaries and ranking without asking users to restart Windows or apps.
option(GY_ENGINE_ONLY_SMOKE
  "Permit engine/policy smoke targets on builders without C++/WinRT; never use for product binaries"
  OFF)
get_filename_component(GY_PROGRAM_FILES_X86 "$ENV{ProgramFiles}/../Program Files (x86)" ABSOLUTE)
file(GLOB GY_CPPWINRT_INCLUDE_CANDIDATES "${GY_PROGRAM_FILES_X86}/Windows Kits/10/Include/*/cppwinrt")
list(SORT GY_CPPWINRT_INCLUDE_CANDIDATES ORDER DESCENDING)
list(LENGTH GY_CPPWINRT_INCLUDE_CANDIDATES GY_CPPWINRT_INCLUDE_COUNT)
if(GY_CPPWINRT_INCLUDE_COUNT LESS 1)
  if(GY_ENGINE_ONLY_SMOKE)
    set(GY_CPPWINRT_INCLUDE "")
    message(WARNING "C++/WinRT is unavailable: only engine/policy smoke targets may be built.")
  else()
    message(FATAL_ERROR "C++/WinRT headers are required for product binaries.")
  endif()
else()
  list(GET GY_CPPWINRT_INCLUDE_CANDIDATES 0 GY_CPPWINRT_INCLUDE)
endif()
if(GY_ENGINE_ONLY_SMOKE)
  set(GY_UPDATE_NOTIFICATION_SOURCE src/UpdateNotificationStub.cpp)
else()
  set(GY_UPDATE_NOTIFICATION_SOURCE src/UpdateNotification.cpp)
endif()
add_executable(GyImeHost WIN32
  src/GyImeHost.cpp
  src/InputScopeProbe.cpp
  src/CandidateWindow.cpp
  src/TrayController.cpp
  src/SettingsWindow.cpp
  src/GyAccountAuth.cpp
  src/GyKeepSync.cpp
  src/ClipboardHistory.cpp
  src/EnglishLexicon.cpp
  src/PinyinEngine.cpp
  ${GY_UPDATE_NOTIFICATION_SOURCE}
  "${GY_HOST_VERSION_RESOURCE}"
)
target_compile_features(GyImeHost PRIVATE cxx_std_20)
target_compile_definitions(GyImeHost PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RIME_IMPORTS GY_HOST_VERSION=\"${GY_VERSION}\" GY_RELEASE_VERSION=\"${GY_VERSION}\")
target_include_directories(GyImeHost PRIVATE src "${GY_RIME_ROOT}/include" "${GY_CPPWINRT_INCLUDE}")
target_link_libraries(GyImeHost PRIVATE shell32 comdlg32 comctl32 advapi32 ole32 runtimeobject winhttp crypt32 gdiplus uiautomationcore "${GY_RIME_ROOT}/lib/rime.lib")
if(MSVC)
  target_compile_options(GyImeHost PRIVATE /utf-8)
elseif(MINGW)
  target_link_options(GyImeHost PRIVATE -municode)
endif()
set_target_properties(GyImeHost PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
if(GY_BUILD_HOST_SMOKE)
  target_compile_definitions(GyImeHost PRIVATE GY_TESTING)
endif()
add_custom_command(TARGET GyImeHost POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_ROOT}/lib/rime.dll" "$<TARGET_FILE_DIR:GyImeHost>/rime.dll"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${GY_RIME_RUNTIME_ROOT}/shared" "$<TARGET_FILE_DIR:GyImeHost>/rime-data/shared"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_RUNTIME_ROOT}/shared/luna_pinyin.schema.yaml" "$<TARGET_FILE_DIR:GyImeHost>/rime-data/shared/build/luna_pinyin.schema.yaml"
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:GyImeHost>/english-lexicon"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/runtime/english/english.tsv" "$<TARGET_FILE_DIR:GyImeHost>/english-lexicon/english.tsv"
)

# A manually operated preview for the real candidate window and offline
# engines.  It is excluded from normal builds/installers and does not load or
# register the TSF DLL, making it safe to hand to a user while a live IME is
# being stabilized.
option(GY_BUILD_CANDIDATE_LAB "Build the isolated visual candidate laboratory" OFF)
if(GY_BUILD_HOST_SMOKE)
  set(GY_BUILD_CANDIDATE_LAB ON CACHE BOOL "Build the isolated visual candidate laboratory" FORCE)
endif()
if(GY_BUILD_CANDIDATE_LAB)
  add_executable(GyCandidateLab WIN32
    src/CandidateLab.cpp
    src/CandidateWindow.cpp
    src/EnglishLexicon.cpp
    src/PinyinEngine.cpp
  )
  target_compile_features(GyCandidateLab PRIVATE cxx_std_20)
  target_compile_definitions(GyCandidateLab PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
                              RIME_IMPORTS GY_CANDIDATE_LAB GY_RELEASE_VERSION="${GY_VERSION}")
  target_include_directories(GyCandidateLab PRIVATE src "${GY_RIME_ROOT}/include")
  target_link_libraries(GyCandidateLab PRIVATE advapi32 crypt32 "${GY_RIME_ROOT}/lib/rime.lib")
  if(MSVC)
    target_compile_options(GyCandidateLab PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyCandidateLab PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_custom_command(TARGET GyCandidateLab POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_ROOT}/lib/rime.dll" "$<TARGET_FILE_DIR:GyCandidateLab>/rime.dll"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${GY_RIME_RUNTIME_ROOT}/shared" "$<TARGET_FILE_DIR:GyCandidateLab>/rime-data/shared"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_RUNTIME_ROOT}/shared/luna_pinyin.schema.yaml" "$<TARGET_FILE_DIR:GyCandidateLab>/rime-data/shared/build/luna_pinyin.schema.yaml"
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:GyCandidateLab>/english-lexicon"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/runtime/english/english.tsv" "$<TARGET_FILE_DIR:GyCandidateLab>/english-lexicon/english.tsv"
  )
endif()

if(GY_BUILD_HOST_SMOKE)
  # Isolated visual harness for DPI/layout review. It uses a disposable
  # LOCALAPPDATA root and is never included in an installer.
  add_executable(GySettingsLab WIN32
    src/SettingsLab.cpp
    src/SettingsWindow.cpp
    src/GyAccountAuth.cpp
    src/GyKeepSync.cpp
    src/ClipboardHistory.cpp
  )
  target_compile_features(GySettingsLab PRIVATE cxx_std_20)
  target_compile_definitions(GySettingsLab PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
                                                GY_RELEASE_VERSION="${GY_VERSION}" GY_SETTINGS_LAB)
  target_include_directories(GySettingsLab PRIVATE src "${GY_CPPWINRT_INCLUDE}")
  target_link_libraries(GySettingsLab PRIVATE shell32 comdlg32 comctl32 advapi32 ole32 runtimeobject
                                              winhttp crypt32 gdiplus uiautomationcore)
  if(MSVC)
    target_compile_options(GySettingsLab PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GySettingsLab PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()


# A one-shot console verifier for installers. It shares the production offline
# engine and data, but intentionally has no Host mutex, tray, pipe, or UI.
add_executable(GyImeHealth src/HealthCheck.cpp src/EnglishLexicon.cpp src/PinyinEngine.cpp "${GY_HEALTH_VERSION_RESOURCE}")
target_compile_features(GyImeHealth PRIVATE cxx_std_20)
target_compile_definitions(GyImeHealth PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RIME_IMPORTS GY_HEALTH_READONLY_INPUT_MODE GY_RELEASE_VERSION=\"${GY_VERSION}\")
target_include_directories(GyImeHealth PRIVATE src "${GY_RIME_ROOT}/include")
target_link_libraries(GyImeHealth PRIVATE advapi32 "${GY_RIME_ROOT}/lib/rime.lib")
if(MSVC)
  target_compile_options(GyImeHealth PRIVATE /W4 /permissive- /utf-8)
endif()
set_target_properties(GyImeHealth PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
add_custom_command(TARGET GyImeHealth POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_ROOT}/lib/rime.dll" "$<TARGET_FILE_DIR:GyImeHealth>/rime.dll"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${GY_RIME_RUNTIME_ROOT}/shared" "$<TARGET_FILE_DIR:GyImeHealth>/rime-data/shared"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_RUNTIME_ROOT}/shared/luna_pinyin.schema.yaml" "$<TARGET_FILE_DIR:GyImeHealth>/rime-data/shared/build/luna_pinyin.schema.yaml"
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:GyImeHealth>/english-lexicon"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/runtime/english/english.tsv" "$<TARGET_FILE_DIR:GyImeHealth>/english-lexicon/english.tsv"
)

# Manual real-window regression utility. It is available in both production
# and smoke builds so an internal candidate can prove normal/password TSF
# behavior without compiling GY_TESTING into the installed Host. It is never
# registered, installed, or run by CTest because it requires an interactive
# desktop and changes only its own thread's active keyboard layout.
add_executable(GyEnRealAppRegression src/EnRealAppRegression.cpp)
target_compile_features(GyEnRealAppRegression PRIVATE cxx_std_20)
target_compile_definitions(GyEnRealAppRegression PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(GyEnRealAppRegression PRIVATE user32 advapi32)
if(MSVC)
  target_compile_options(GyEnRealAppRegression PRIVATE /W4 /permissive- /utf-8)
endif()
set_target_properties(GyEnRealAppRegression PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# Development-only protocol verification. It starts a private Host instance,
# asks for nihao, then cleanly stops that instance.
option(GY_BUILD_HOST_SMOKE "Build the Host IPC smoke test" OFF)
if(GY_BUILD_HOST_SMOKE)
  add_executable(GyHostSmoke src/HostSmoke.cpp)
  target_compile_features(GyHostSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyHostSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX GY_TESTING)
  target_include_directories(GyHostSmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyHostSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyHostSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyHostSmoke COMMAND $<TARGET_FILE:GyHostSmoke>)
  set_tests_properties(GyHostSmoke PROPERTIES TIMEOUT 20 LABELS "native;ipc;e2e")
  # Keystroke-path latency benchmark against an isolated test Host. Not a
  # ctest: run bin/HostPerf.exe manually to capture before/after numbers.
  add_executable(GyHostPerf src/HostPerf.cpp)
  target_compile_features(GyHostPerf PRIVATE cxx_std_20)
  target_compile_definitions(GyHostPerf PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX GY_TESTING)
  target_include_directories(GyHostPerf PRIVATE src)
  if(MSVC)
    target_compile_options(GyHostPerf PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyHostPerf PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  set(GY_HEALTH_LOCALAPPDATA "${CMAKE_BINARY_DIR}/test-localappdata")
  file(MAKE_DIRECTORY "${GY_HEALTH_LOCALAPPDATA}")
  add_test(NAME GyImeHealthCheck COMMAND $<TARGET_FILE:GyImeHealth>)
  set_tests_properties(GyImeHealthCheck PROPERTIES TIMEOUT 20 LABELS "native;health;offline"
    ENVIRONMENT "LOCALAPPDATA=${GY_HEALTH_LOCALAPPDATA}")
  # Sync v3 must preserve the event order.  In particular a later restore ADD
  # has to win over an earlier DELETE for the same entry ID, and a snapshot
  # must refill HEAD(20) after a deletion.
  add_executable(GyClipboardHistorySyncSmoke
    src/ClipboardHistorySyncSmoke.cpp
    src/ClipboardHistory.cpp
  )
  target_compile_features(GyClipboardHistorySyncSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyClipboardHistorySyncSmoke PRIVATE GY_TESTING UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyClipboardHistorySyncSmoke PRIVATE src)
  target_link_libraries(GyClipboardHistorySyncSmoke PRIVATE ole32 gdiplus advapi32)
  if(MSVC)
    target_compile_options(GyClipboardHistorySyncSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyClipboardHistorySyncSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyClipboardHistorySyncSmoke COMMAND $<TARGET_FILE:GyClipboardHistorySyncSmoke>)
  set_tests_properties(GyClipboardHistorySyncSmoke PROPERTIES TIMEOUT 10 LABELS "native;clipboard;sync;regression"
    ENVIRONMENT "LOCALAPPDATA=${GY_HEALTH_LOCALAPPDATA}")

  # One-time maintenance utility used by release validation and support to
  # skip a pre-login clipboard backlog without exposing its contents.
  add_executable(GyClipboardSkipPending
    src/ClipboardSkipPending.cpp
    src/ClipboardHistory.cpp
  )
  target_compile_features(GyClipboardSkipPending PRIVATE cxx_std_20)
  target_compile_definitions(GyClipboardSkipPending PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyClipboardSkipPending PRIVATE src)
  target_link_libraries(GyClipboardSkipPending PRIVATE ole32 gdiplus advapi32)
  if(MSVC)
    target_compile_options(GyClipboardSkipPending PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyClipboardSkipPending PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_executable(GyHostedPinyinEngineSmoke
    src/HostedPinyinEngineSmoke.cpp
    src/HostedPinyinEngine.cpp
  )
  target_compile_features(GyHostedPinyinEngineSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyHostedPinyinEngineSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX GY_TESTING GY_HOST_VERSION="${GY_VERSION}")
  target_include_directories(GyHostedPinyinEngineSmoke PRIVATE src)
  target_link_libraries(GyHostedPinyinEngineSmoke PRIVATE advapi32)
  if(MSVC)
    target_compile_options(GyHostedPinyinEngineSmoke PRIVATE /W4 /permissive- /utf-8)
  elseif(MINGW)
    target_link_options(GyHostedPinyinEngineSmoke PRIVATE -municode)
  endif()
  set_target_properties(GyHostedPinyinEngineSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyHostedPinyinEngineSmoke COMMAND $<TARGET_FILE:GyHostedPinyinEngineSmoke>)
  set_tests_properties(GyHostedPinyinEngineSmoke PROPERTIES TIMEOUT 20 LABELS "native;ipc;recovery")
  # Regression guard for the system-freeze incident: a connected Host that
  # never replies must time out inside the input budget, without touching the
  # registered Host, current input mode, or any live process.
  add_executable(GyHostedPinyinEngineDeadlineSmoke
    src/HostedPinyinEngineDeadlineSmoke.cpp
    src/HostedPinyinEngine.cpp
  )
  target_compile_features(GyHostedPinyinEngineDeadlineSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyHostedPinyinEngineDeadlineSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX GY_TESTING GY_HOST_VERSION="${GY_VERSION}")
  target_include_directories(GyHostedPinyinEngineDeadlineSmoke PRIVATE src)
  target_link_libraries(GyHostedPinyinEngineDeadlineSmoke PRIVATE advapi32)
  if(MSVC)
    target_compile_options(GyHostedPinyinEngineDeadlineSmoke PRIVATE /W4 /permissive- /utf-8)
  elseif(MINGW)
    target_link_options(GyHostedPinyinEngineDeadlineSmoke PRIVATE -municode)
  endif()
  set_target_properties(GyHostedPinyinEngineDeadlineSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyHostedPinyinEngineDeadlineSmoke COMMAND $<TARGET_FILE:GyHostedPinyinEngineDeadlineSmoke>)
  set_tests_properties(GyHostedPinyinEngineDeadlineSmoke PROPERTIES TIMEOUT 10 LABELS "native;ipc;deadline;regression")
  add_executable(GySelectionCallbackSmoke
    src/SelectionCallbackSmoke.cpp
    src/SelectionCallback.cpp
  )
  target_compile_features(GySelectionCallbackSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GySelectionCallbackSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GySelectionCallbackSmoke PRIVATE src)
  target_link_libraries(GySelectionCallbackSmoke PRIVATE ole32 advapi32)
  if(MSVC)
    target_compile_options(GySelectionCallbackSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GySelectionCallbackSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GySelectionCallbackSmoke COMMAND $<TARGET_FILE:GySelectionCallbackSmoke>)
  set_tests_properties(GySelectionCallbackSmoke PROPERTIES TIMEOUT 10 LABELS "native;ipc")
  add_executable(GyKeyPolicySmoke src/KeyPolicySmoke.cpp)
  target_compile_features(GyKeyPolicySmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyKeyPolicySmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyKeyPolicySmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyKeyPolicySmoke PRIVATE /W4 /permissive- /utf-8)
  elseif(MINGW)
    target_link_options(GyKeyPolicySmoke PRIVATE -municode)
  endif()
  set_target_properties(GyKeyPolicySmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyKeyPolicySmoke COMMAND $<TARGET_FILE:GyKeyPolicySmoke>)
  set_tests_properties(GyKeyPolicySmoke PROPERTIES TIMEOUT 10 LABELS "native;keyboard;shortcuts")
  add_executable(GyNumericEntryPolicySmoke src/NumericEntryPolicySmoke.cpp)
  target_compile_features(GyNumericEntryPolicySmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyNumericEntryPolicySmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyNumericEntryPolicySmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyNumericEntryPolicySmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyNumericEntryPolicySmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyNumericEntryPolicySmoke COMMAND $<TARGET_FILE:GyNumericEntryPolicySmoke>)
  set_tests_properties(GyNumericEntryPolicySmoke PROPERTIES TIMEOUT 10 LABELS "native;keyboard;numbers;regression")
  add_executable(GyCorrectionPolicySmoke src/CorrectionPolicySmoke.cpp)
  target_compile_features(GyCorrectionPolicySmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyCorrectionPolicySmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyCorrectionPolicySmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyCorrectionPolicySmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyCorrectionPolicySmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyCorrectionPolicySmoke COMMAND $<TARGET_FILE:GyCorrectionPolicySmoke>)
  set_tests_properties(GyCorrectionPolicySmoke PROPERTIES TIMEOUT 10 LABELS "native;correction;privacy;regression")
  add_executable(GyInputScopeCacheSmoke src/InputScopeCacheSmoke.cpp)
  target_compile_features(GyInputScopeCacheSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyInputScopeCacheSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX GY_TESTING)
  target_include_directories(GyInputScopeCacheSmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyInputScopeCacheSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyInputScopeCacheSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyInputScopeCacheSmoke COMMAND $<TARGET_FILE:GyInputScopeCacheSmoke>)
  set_tests_properties(GyInputScopeCacheSmoke PROPERTIES TIMEOUT 10 LABELS "native;input-scope;privacy;regression")
  add_executable(GyTsfEditSessionPolicySmoke src/TsfEditSessionPolicySmoke.cpp)
  target_compile_features(GyTsfEditSessionPolicySmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyTsfEditSessionPolicySmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyTsfEditSessionPolicySmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyTsfEditSessionPolicySmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyTsfEditSessionPolicySmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyTsfEditSessionPolicySmoke COMMAND $<TARGET_FILE:GyTsfEditSessionPolicySmoke>)
  set_tests_properties(GyTsfEditSessionPolicySmoke PROPERTIES TIMEOUT 10 LABELS "native;tsf;firefox;regression")
  add_executable(GyEnglishAssistSmoke src/EnglishAssistSmoke.cpp src/EnglishAssist.cpp)
  target_compile_features(GyEnglishAssistSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyEnglishAssistSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyEnglishAssistSmoke PRIVATE src)
  target_link_libraries(GyEnglishAssistSmoke PRIVATE ole32 uuid)
  if(MSVC)
    target_compile_options(GyEnglishAssistSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyEnglishAssistSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyEnglishAssistSmoke COMMAND $<TARGET_FILE:GyEnglishAssistSmoke>)
  set_tests_properties(GyEnglishAssistSmoke PROPERTIES TIMEOUT 10 LABELS "native;english;privacy")
  add_executable(GyEnglishAssistPolicySmoke src/EnglishAssistPolicySmoke.cpp)
  target_compile_features(GyEnglishAssistPolicySmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyEnglishAssistPolicySmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyEnglishAssistPolicySmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyEnglishAssistPolicySmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyEnglishAssistPolicySmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyEnglishAssistPolicySmoke COMMAND $<TARGET_FILE:GyEnglishAssistPolicySmoke>)
  set_tests_properties(GyEnglishAssistPolicySmoke PROPERTIES TIMEOUT 10 LABELS "native;english;privacy;policy")
  # Runs the Windows TSF profile manager in an isolated process. It verifies
  # that the current user has enabled GY and that the registered DLL creates
  # its text-service COM object; no user language-bar state is changed.
  add_executable(GyTsfActivationSmoke src/TsfActivationSmoke.cpp)
  target_compile_features(GyTsfActivationSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyTsfActivationSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyTsfActivationSmoke PRIVATE src)
  # ITfInputProcessorProfileMgr is a COM interface. The test resolves the two
  # optional desktop factory helpers from msctf.dll at runtime because the
  # Windows SDK intentionally ships no msctf import library.
  target_link_libraries(GyTsfActivationSmoke PRIVATE ole32)
  if(MSVC)
    target_compile_options(GyTsfActivationSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyTsfActivationSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyTsfActivationSmoke COMMAND $<TARGET_FILE:GyTsfActivationSmoke>)
  set_tests_properties(GyTsfActivationSmoke PROPERTIES TIMEOUT 10 LABELS "native;tsf;activation;e2e")
  add_executable(GyHostProtocolSmoke src/HostProtocolSmoke.cpp)
  target_compile_features(GyHostProtocolSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyHostProtocolSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyHostProtocolSmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyHostProtocolSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyHostProtocolSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyHostProtocolSmoke COMMAND $<TARGET_FILE:GyHostProtocolSmoke>)
  set_tests_properties(GyHostProtocolSmoke PROPERTIES TIMEOUT 10 LABELS "native;ipc;protocol")
  add_executable(GyCandidateLayoutSmoke src/CandidateLayoutSmoke.cpp)
  target_compile_features(GyCandidateLayoutSmoke PRIVATE cxx_std_20)
  target_include_directories(GyCandidateLayoutSmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyCandidateLayoutSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyCandidateLayoutSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyCandidateLayoutSmoke COMMAND $<TARGET_FILE:GyCandidateLayoutSmoke>)
  set_tests_properties(GyCandidateLayoutSmoke PROPERTIES TIMEOUT 10 LABELS "native;candidate-layout;regression")
  add_executable(GyCandidatePresentationSmoke src/CandidatePresentationSmoke.cpp)
  target_compile_features(GyCandidatePresentationSmoke PRIVATE cxx_std_20)
  target_include_directories(GyCandidatePresentationSmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyCandidatePresentationSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyCandidatePresentationSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyCandidatePresentationSmoke COMMAND $<TARGET_FILE:GyCandidatePresentationSmoke>)
  set_tests_properties(GyCandidatePresentationSmoke PROPERTIES TIMEOUT 10 LABELS "native;candidate-presentation;regression")
  add_executable(GyEnglishCandidatePolicySmoke src/EnglishCandidatePolicySmoke.cpp)
  target_compile_features(GyEnglishCandidatePolicySmoke PRIVATE cxx_std_20)
  target_include_directories(GyEnglishCandidatePolicySmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyEnglishCandidatePolicySmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyEnglishCandidatePolicySmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyEnglishCandidatePolicySmoke COMMAND $<TARGET_FILE:GyEnglishCandidatePolicySmoke>)
  set_tests_properties(GyEnglishCandidatePolicySmoke PROPERTIES TIMEOUT 10 LABELS "native;english;candidate-semantics;regression")
  add_executable(GyCandidateAppearanceSmoke src/CandidateAppearanceSmoke.cpp)
  target_compile_features(GyCandidateAppearanceSmoke PRIVATE cxx_std_20)
  target_include_directories(GyCandidateAppearanceSmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyCandidateAppearanceSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyCandidateAppearanceSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyCandidateAppearanceSmoke COMMAND $<TARGET_FILE:GyCandidateAppearanceSmoke>)
  set_tests_properties(GyCandidateAppearanceSmoke PROPERTIES TIMEOUT 10 LABELS "native;candidate-layout;appearance;regression")
  add_executable(GyCandidatePlacementPolicySmoke src/CandidatePlacementPolicySmoke.cpp)
  target_compile_features(GyCandidatePlacementPolicySmoke PRIVATE cxx_std_20)
  target_include_directories(GyCandidatePlacementPolicySmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyCandidatePlacementPolicySmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyCandidatePlacementPolicySmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyCandidatePlacementPolicySmoke COMMAND $<TARGET_FILE:GyCandidatePlacementPolicySmoke>)
  set_tests_properties(GyCandidatePlacementPolicySmoke PROPERTIES TIMEOUT 10 LABELS "native;candidate-placement;regression")
  add_executable(GyCandidateContractSmoke src/CandidateContractSmoke.cpp)
  target_compile_features(GyCandidateContractSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyCandidateContractSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyCandidateContractSmoke PRIVATE src)
  if(MSVC)
    target_compile_options(GyCandidateContractSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyCandidateContractSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyCandidateContractSmoke COMMAND $<TARGET_FILE:GyCandidateContractSmoke>)
  set_tests_properties(GyCandidateContractSmoke PROPERTIES TIMEOUT 10 LABELS "native;candidate-layout;contract;regression")
  find_program(GY_POWERSHELL_EXECUTABLE NAMES powershell.exe pwsh.exe)
  if(GY_POWERSHELL_EXECUTABLE)
    add_test(NAME GyInstallerSmoke
      COMMAND "${GY_POWERSHELL_EXECUTABLE}" -NoProfile -ExecutionPolicy Bypass -File "${CMAKE_CURRENT_SOURCE_DIR}/installer/InstallerSmoke.ps1")
    set_tests_properties(GyInstallerSmoke PROPERTIES TIMEOUT 10 LABELS "native;installer;upgrade;rollback")
    add_test(NAME GyEnglishInteractionPolicySmoke
      COMMAND "${GY_POWERSHELL_EXECUTABLE}" -NoProfile -ExecutionPolicy Bypass -File "${CMAKE_CURRENT_SOURCE_DIR}/installer/EnglishInteractionPolicySmoke.ps1")
    set_tests_properties(GyEnglishInteractionPolicySmoke PROPERTIES TIMEOUT 10 LABELS "native;english;keyboard;candidate-presentation;regression")
    add_test(NAME GyEnglishLexiconSyncSmoke
      COMMAND "${GY_POWERSHELL_EXECUTABLE}" -NoProfile -ExecutionPolicy Bypass -File "${CMAKE_CURRENT_SOURCE_DIR}/installer/EnglishLexiconSyncSmoke.ps1")
    set_tests_properties(GyEnglishLexiconSyncSmoke PROPERTIES TIMEOUT 15 LABELS "native;english;lexicon;offline;policy")
  endif()
endif()
# Development-only verification; normal builds and installations create only GyIme.
option(GY_BUILD_RIME_SMOKE "Build the offline Rime engine smoke test" OFF)
if(GY_BUILD_HOST_SMOKE)
  # Host integration is incomplete without the real offline Pinyin/phrase/learning smoke.
  set(GY_BUILD_RIME_SMOKE ON CACHE BOOL "Build the offline Rime engine smoke test" FORCE)
endif()
if(GY_BUILD_RIME_SMOKE)
  add_executable(GyPinyinEngineSmoke
    src/PinyinEngineSmoke.cpp
    src/EnglishLexicon.cpp
    src/PinyinEngine.cpp
  )
  target_compile_features(GyPinyinEngineSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyPinyinEngineSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RIME_IMPORTS GY_TESTING GY_RELEASE_VERSION=\"${GY_VERSION}\")
  target_include_directories(GyPinyinEngineSmoke PRIVATE src "${GY_RIME_ROOT}/include")
  target_link_libraries(GyPinyinEngineSmoke PRIVATE advapi32 crypt32 "${GY_RIME_ROOT}/lib/rime.lib")
  if(MSVC)
    target_compile_options(GyPinyinEngineSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyPinyinEngineSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_custom_command(TARGET GyPinyinEngineSmoke POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_ROOT}/lib/rime.dll" "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/rime.dll"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${GY_RIME_RUNTIME_ROOT}/shared" "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/rime-data/shared"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_RUNTIME_ROOT}/shared/luna_pinyin.schema.yaml" "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/rime-data/shared/build/luna_pinyin.schema.yaml"
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/english-lexicon"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/runtime/english/english.tsv" "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/english-lexicon/english.tsv"
  )
endif()
if(GY_BUILD_RIME_SMOKE)
  add_test(NAME GyPinyinEngineSmoke COMMAND $<TARGET_FILE:GyPinyinEngineSmoke>)
  set_tests_properties(GyPinyinEngineSmoke PROPERTIES TIMEOUT 45 LABELS "native;rime;offline")
endif()


