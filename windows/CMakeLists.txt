cmake_minimum_required(VERSION 3.14)
project(audio_manager LANGUAGES CXX)

set(PLUGIN_NAME "audio_manager_plugin")

add_library(${PLUGIN_NAME} SHARED
  "audio_manager_plugin.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

# C++/WinRT 需要 Windows 10 SDK(17763+)；UTF-8 保证中文注释与日志
target_compile_options(${PLUGIN_NAME} PRIVATE /utf-8)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
