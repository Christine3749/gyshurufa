cmake_minimum_required(VERSION 3.21)
project(GyIme LANGUAGES CXX)

enable_testing()

# Ship the MSVC runtime inside GY binaries so TSF registration does not depend
# on a separately installed Visual C++ Redistributable.
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

set(GY_VERSION "dev" CACHE STRING "GY engine host version")

if(NOT WIN32)
  message(FATAL_ERROR "GY 输入法只能在 Windows 上构建。")
endif()

# This folder is the complete, redistributable offline Rime runtime.
set(GY_RIME_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/runtime/rime" CACHE PATH "Bundled librime runtime root" FORCE)
set(GY_RIME_RUNTIME_ROOT "${GY_RIME_ROOT}" CACHE PATH "Bundled GY Rime data root" FORCE)
if(NOT EXISTS "${GY_RIME_ROOT}/include/rime_api.h" OR NOT EXISTS "${GY_RIME_ROOT}/lib/rime.lib" OR NOT EXISTS "${GY_RIME_ROOT}/lib/rime.dll")
  message(FATAL_ERROR "The bundled librime runtime is incomplete under ${GY_RIME_ROOT}.")
endif()
if(NOT EXISTS "${GY_RIME_RUNTIME_ROOT}/shared/build/luna_pinyin.table.bin")
  message(FATAL_ERROR "The bundled luna-pinyin dictionary is incomplete under ${GY_RIME_RUNTIME_ROOT}/shared/build.")
endif()

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
  src/PinyinEngine.cpp
)
target_compile_features(GyImeHost PRIVATE cxx_std_20)
target_compile_definitions(GyImeHost PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RIME_IMPORTS GY_HOST_VERSION=\"${GY_VERSION}\")
target_include_directories(GyImeHost PRIVATE src "${GY_RIME_ROOT}/include")
target_link_libraries(GyImeHost PRIVATE shell32 comdlg32 advapi32 "${GY_RIME_ROOT}/lib/rime.lib")
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
)


# A one-shot console verifier for installers. It shares the production offline
# engine and data, but intentionally has no Host mutex, tray, pipe, or UI.
add_executable(GyImeHealth src/HealthCheck.cpp src/PinyinEngine.cpp)
target_compile_features(GyImeHealth PRIVATE cxx_std_20)
target_compile_definitions(GyImeHealth PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RIME_IMPORTS)
target_include_directories(GyImeHealth PRIVATE src "${GY_RIME_ROOT}/include")
target_link_libraries(GyImeHealth PRIVATE "${GY_RIME_ROOT}/lib/rime.lib")
if(MSVC)
  target_compile_options(GyImeHealth PRIVATE /W4 /permissive- /utf-8)
endif()
set_target_properties(GyImeHealth PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
add_custom_command(TARGET GyImeHealth POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_ROOT}/lib/rime.dll" "$<TARGET_FILE_DIR:GyImeHealth>/rime.dll"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${GY_RIME_RUNTIME_ROOT}/shared" "$<TARGET_FILE_DIR:GyImeHealth>/rime-data/shared"
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
  set(GY_HEALTH_LOCALAPPDATA "${CMAKE_BINARY_DIR}/test-localappdata")
  file(MAKE_DIRECTORY "${GY_HEALTH_LOCALAPPDATA}")
  add_test(NAME GyImeHealthCheck COMMAND $<TARGET_FILE:GyImeHealth>)
  set_tests_properties(GyImeHealthCheck PROPERTIES TIMEOUT 20 LABELS "native;health;offline"
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
  target_compile_definitions(GyPinyinEngineSmoke PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RIME_IMPORTS)
  target_include_directories(GyPinyinEngineSmoke PRIVATE src "${GY_RIME_ROOT}/include")
  target_link_libraries(GyPinyinEngineSmoke PRIVATE "${GY_RIME_ROOT}/lib/rime.lib")
  if(MSVC)
    target_compile_options(GyPinyinEngineSmoke PRIVATE /W4 /permissive- /utf-8)
  endif()
  set_target_properties(GyPinyinEngineSmoke PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  add_custom_command(TARGET GyPinyinEngineSmoke POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${GY_RIME_ROOT}/lib/rime.dll" "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/rime.dll"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${GY_RIME_RUNTIME_ROOT}/shared" "$<TARGET_FILE_DIR:GyPinyinEngineSmoke>/rime-data/shared"
  )
endif()
if(GY_BUILD_RIME_SMOKE)
  add_test(NAME GyPinyinEngineSmoke COMMAND $<TARGET_FILE:GyPinyinEngineSmoke>)
  set_tests_properties(GyPinyinEngineSmoke PROPERTIES TIMEOUT 45 LABELS "native;rime;offline")
endif()



