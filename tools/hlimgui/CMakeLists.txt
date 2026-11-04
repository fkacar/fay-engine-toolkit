# hlimgui eklentisinin araç takımı sarmalayıcısı (Windows, tools/build-hlimgui.bat). Üçüncü taraf hlimgui'nin kendi
# CMake dosyası değişmez; araç takımının yerel eki (editor/native: kare koruması) aynı hedefe eklenir.
cmake_minimum_required(VERSION 3.13)
project(hlimgui_arac_takimi)

add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/../../third_party/hlimgui/extension hlimgui)
target_sources(hlimgui.hdll PRIVATE ${CMAKE_CURRENT_LIST_DIR}/../../editor/native/imgui_guard.cpp)
# Çıktı bilinen bir yere: build-hlimgui.bat oradan kopyalar.
set_target_properties(hlimgui.hdll PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/out
  RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_BINARY_DIR}/out
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/out
  LIBRARY_OUTPUT_DIRECTORY_RELEASE ${CMAKE_BINARY_DIR}/out
)
