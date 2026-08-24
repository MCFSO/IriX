cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# Shell_NotifyIcon（系统托盘图标）与单实例唤醒所需。
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib")
# 源文件为无 BOM 的 UTF-8（含中文宽字符串字面量，如托盘菜单/气泡提示）；
# 显式告知 MSVC 按 UTF-8 解析，避免按系统 ANSI 代码页（GBK）解码导致乱码。
if(MSVC)
  target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")
endif()
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# 旧版局部 DLL 复制规则（保留兼容；完整列表见文件末尾全量同步）

if(FALSE) # 旧规则已由文件末尾的全量列表取代
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${CMAKE_CURRENT_SOURCE_DIR}/xmc_backup.dll"
      "$<TARGET_FILE_DIR:${BINARY_NAME}>/xmc_backup.dll"
    COMMENT "Copying xmc_backup.dll to output directory"
  )
endif()

if(FALSE) # 旧规则已由文件末尾的全量列表取代
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${CMAKE_CURRENT_SOURCE_DIR}/xmc_vector_store.dll"
      "$<TARGET_FILE_DIR:${BINARY_NAME}>/xmc_vector_store.dll"
    COMMENT "Copying xmc_vector_store.dll to output directory"
  )
endif()

if(FALSE) # 旧规则已由文件末尾的全量列表取代
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${CMAKE_CURRENT_SOURCE_DIR}/xmc_orchestrator.dll"
      "$<TARGET_FILE_DIR:${BINARY_NAME}>/xmc_orchestrator.dll"
    COMMENT "Copying xmc_orchestrator.dll to output directory"
  )
endif()

# 按 Rust workspace 成员全量同步所有 FFI DLL（新增 crate 时只需更新下方列表）
set(XMC_RUST_DLLS
  xmc_backup
  xmc_downloader
  xmc_file_ops
  xmc_logger
  xmc_http_client
  xmc_db_client
  xmc_vector_store
  xmc_orchestrator
)
foreach(XMC_DLL ${XMC_RUST_DLLS})
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${XMC_DLL}.dll")
    add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/${XMC_DLL}.dll"
        "$<TARGET_FILE_DIR:${BINARY_NAME}>/${XMC_DLL}.dll"
      COMMENT "Copying ${XMC_DLL}.dll to output directory"
    )
  else()
    message(WARNING "缺少 Rust FFI DLL: ${XMC_DLL}.dll，请先运行 build_rust.bat")
  endif()
endforeach()
