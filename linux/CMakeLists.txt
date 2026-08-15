cmake_minimum_required(VERSION 3.13)
set(PROJECT_NAME "audio_manager_plugin")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

add_library(${PLUGIN_NAME} SHARED
  "audio_manager_plugin.cc"
  "mpris.c"
)
apply_standard_settings()
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)

# GStreamer 播放核心(gst_player 来自 gst-plugins-good)+ GLib/Gio(MPRIS D-Bus)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GSTREAMER IMPORTED_TARGET gstreamer-1.0)
pkg_check_modules(GSTREAMER_PLAYER IMPORTED_TARGET gstreamer-player-1.0)
pkg_check_modules(GIO IMPORTED_TARGET gio-2.0)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  PkgConfig::GSTREAMER
  PkgConfig::GSTREAMER_PLAYER
  PkgConfig::GIO)
