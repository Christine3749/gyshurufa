cmake_minimum_required(VERSION 3.21)
project(GyIme LANGUAGES CXX)

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

# The TSF DLL remains a small, stable compatibility layer inside each target
# app. It talks to GyImeHost over a local named pipe for lookup/ranking work.
add_library(GyIme SHARED
  src/GyIme.cpp
  src/GyIme.def
  src/HostedPinyinEngine.cpp
  src/SelectionCallback.cpp
)
target_compile_features(GyIme PRIVATE cxx_std_20)
target_compile_definitions(GyIme PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
if(MSVC)
  target_compile_options(GyIme PRIVATE /utf-8)
endif()
target_include_directories(GyIme PRIVATE src)
target_link_libraries(GyIme PRIVATE ole32 advapi32)
# Field diagnosis: configure with -DGY_IME_TRACE=ON to log TSF focus/key/edit
# events to %TEMP%/GyIme.trace.log without touching source. Stays off for
# release and installer builds.
option(GY_IME_TRACE "Log GyIme TSF events to %TEMP%/GyIme.trace.log" OFF)
if(GY_IME_TRACE)
  target_compile_definitions(GyIme PRIVATE GY_IME_TRACE)
endif()
set_target_properties(GyIme PROPERTIES
  OUTPUT_NAME "GyIme"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# The updatable out-of-process engine. Later Host-only releases can update
# dictionaries and ranking without asking users to restart Windows or apps.
add_executable(GyImeHost WIN32
  src/GyImeHost.cpp
  src/CandidateWindow.cpp
  src/TrayController.cpp
  src/SettingsWindow.cpp
  src/GyAccountAuth.cpp
  src/GyKeepSync.cpp
  src/ClipboardHistory.cpp
  src/PinyinEngine.cpp
)
target_compile_features(GyImeHost PRIVATE cxx_std_20)
target_compile_definitions(GyImeHost PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RIME_IMPORTS GY_HOST_VERSION=\"${GY_VERSION}\" GY_RELEASE_VERSION=\"${GY_VERSION}\")
target_include_directories(GyImeHost PRIVATE src "${GY_RIME_ROOT}/include")
target_link_libraries(GyImeHost PRIVATE shell32 comdlg32 advapi32 ole32 winhttp crypt32 gdiplus "${GY_RIME_ROOT}/lib/rime.lib")
if(MSVC)
  target_compile_options(GyImeHost PRIVATE /utf-8)
endif()
set_target_properties(GyImeHost PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
if(GY_BUILD_HOST_SMOKE)
  target_compile_definitions(GyImeHost PRIVATE GY_TESTING)
endif()
add_custom_command(TARGET GyImeHost POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_ROOT}/lib/rime.dll" "$<TARGET_FILE_DIR:GyImeHost>/rime.dll"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${GY_RIME_RUNTIME_ROOT}/shared" "$<TARGET_FILE_DIR:GyImeHost>/rime-data/shared"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_RUNTIME_ROOT}/shared/luna_pinyin.schema.yaml" "$<TARGET_FILE_DIR:GyImeHost>/rime-data/shared/build/luna_pinyin.schema.yaml"
)


# A one-shot console verifier for installers. It shares the production offline
# engine and data, but intentionally has no Host mutex, tray, pipe, or UI.
add_executable(GyImeHealth src/HealthCheck.cpp src/PinyinEngine.cpp)
target_compile_features(GyImeHealth PRIVATE cxx_std_20)
target_compile_definitions(GyImeHealth PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RIME_IMPORTS GY_RELEASE_VERSION=\"${GY_VERSION}\")
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
)

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
  target_compile_definitions(GyClipboardHistorySyncSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(GyClipboardHistorySyncSmoke PRIVATE src)
  target_link_libraries(GyClipboardHistorySyncSmoke PRIVATE ole32 gdiplus)
  if(MSVC)
    target_compile_options(GyClipboardHistorySyncSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyClipboardHistorySyncSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyClipboardHistorySyncSmoke COMMAND $<TARGET_FILE:GyClipboardHistorySyncSmoke>)
  set_tests_properties(GyClipboardHistorySyncSmoke PROPERTIES TIMEOUT 10 LABELS "native;clipboard;sync;regression"
    ENVIRONMENT "LOCALAPPDATA=${GY_HEALTH_LOCALAPPDATA}")
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
  endif()
  set_target_properties(GyHostedPinyinEngineSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyHostedPinyinEngineSmoke COMMAND $<TARGET_FILE:GyHostedPinyinEngineSmoke>)
  set_tests_properties(GyHostedPinyinEngineSmoke PROPERTIES TIMEOUT 20 LABELS "native;ipc;recovery")
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
  endif()
  set_target_properties(GyKeyPolicySmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_test(NAME GyKeyPolicySmoke COMMAND $<TARGET_FILE:GyKeyPolicySmoke>)
  set_tests_properties(GyKeyPolicySmoke PROPERTIES TIMEOUT 10 LABELS "native;keyboard;shortcuts")
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
    src/PinyinEngine.cpp
  )
  target_compile_features(GyPinyinEngineSmoke PRIVATE cxx_std_20)
  target_compile_definitions(GyPinyinEngineSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RIME_IMPORTS GY_RELEASE_VERSION=\"${GY_VERSION}\")
  target_include_directories(GyPinyinEngineSmoke PRIVATE src "${GY_RIME_ROOT}/include")
  target_link_libraries(GyPinyinEngineSmoke PRIVATE advapi32 "${GY_RIME_ROOT}/lib/rime.lib")
  if(MSVC)
    target_compile_options(GyPinyinEngineSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyPinyinEngineSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_custom_command(TARGET GyPinyinEngineSmoke POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_ROOT}/lib/rime.dll" "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/rime.dll"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${GY_RIME_RUNTIME_ROOT}/shared" "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/rime-data/shared"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_RUNTIME_ROOT}/shared/luna_pinyin.schema.yaml" "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/rime-data/shared/build/luna_pinyin.schema.yaml"
  )
endif()
if(GY_BUILD_RIME_SMOKE)
  add_test(NAME GyPinyinEngineSmoke COMMAND $<TARGET_FILE:GyPinyinEngineSmoke>)
  set_tests_properties(GyPinyinEngineSmoke PROPERTIES TIMEOUT 45 LABELS "native;rime;offline")
endif()


