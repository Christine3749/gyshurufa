cmake_minimum_required(VERSION 3.21)
project(GYSessionCore LANGUAGES CXX)

enable_testing()

add_library(GYSessionCore SessionGuard.cpp CandidatePool.cpp)
target_compile_features(GYSessionCore PUBLIC cxx_std_20)
target_include_directories(GYSessionCore PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")

add_executable(GYSessionGuardSmoke SessionGuardSmoke.cpp)
target_compile_features(GYSessionGuardSmoke PRIVATE cxx_std_20)
target_link_libraries(GYSessionGuardSmoke PRIVATE GYSessionCore)
add_test(NAME GYSessionGuardSmoke COMMAND GYSessionGuardSmoke)

add_executable(GYCandidatePoolSmoke CandidatePoolSmoke.cpp)
target_compile_features(GYCandidatePoolSmoke PRIVATE cxx_std_20)
target_link_libraries(GYCandidatePoolSmoke PRIVATE GYSessionCore)
add_test(NAME GYCandidatePoolSmoke COMMAND GYCandidatePoolSmoke)
