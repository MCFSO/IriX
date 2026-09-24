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

# 按 Rust workspace 成员全量同步所有 FFI DLL（与 rust/Cargo.toml 的 members 保持一致，
# 新增 crate 时三处都要加：本列表、rust/Cargo.toml、build_rust.bat/sh）。
# 注意：打包流程（fastforge）会先 flutter clean 再重建，构建产物里的 xmc_*.dll 完全
# 由这里的复制规则决定，因此列表必须完整，缺一个就会打出“能装但缺功能”的安装包。
set(XMC_RUST_DLLS
  xmc_backup
  xmc_downloader
  xmc_file_ops
  xmc_logger
  xmc_http_client
  xmc_db_client
  xmc_vector_store
  xmc_orchestrator
  xmc_nbt
  xmc_devlog
)
foreach(XMC_DLL ${XMC_RUST_DLLS})
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${XMC_DLL}.dll")
    add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/${XMC_DLL}.dll"
        "$<TARGET_FILE_DIR:${BINARY_NAME}>/${XMC_DLL}.dll"
      COMMENT "Copying ${XMC_DLL}.dll to output directory"
    )
  endif()
endforeach()

# 每次构建都校验 FFI 动态库是否齐全：Release / Profile 缺失直接构建失败，
# Debug 只警告（见 check_rust_dlls.cmake 顶部说明）。
string(REPLACE ";" "," XMC_RUST_DLLS_CSV "${XMC_RUST_DLLS}")
add_custom_target(xmc_rust_dll_check ALL
  COMMAND ${CMAKE_COMMAND}
    "-DXMC_CONFIG=$<CONFIG>"
    "-DXMC_DLL_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
    "-DXMC_DLLS=${XMC_RUST_DLLS_CSV}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/check_rust_dlls.cmake"
  COMMENT "Checking Rust FFI DLLs"
  VERBATIM
)
add_dependencies(${BINARY_NAME} xmc_rust_dll_check)
