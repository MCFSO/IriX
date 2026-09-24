# 校验 Rust FFI 动态库是否齐全（由 windows/runner/CMakeLists.txt 以 ALL 目标调用）。
#
# 背景：安装包缺失 xmc_*.dll 时应用仍然能装上，但一用到对应功能就报
# “Rust xxx library not found”（例如市场页面依赖 xmc_http_client.dll）。
# 之前的写法是缺库只 message(WARNING) 后跳过复制，打包流程照样能产出安装包
# （fastforge 打包前会先 flutter clean 再重新构建，因此构建产物里的动态库完全
# 由 CMake 的复制规则决定），缺陷只能等用户装完才发现。
# 现在：Release / Profile 构建缺库直接失败，Debug 仅警告（方便只改 UI 的本地调试）。
#
# 用法：
#   cmake -DXMC_CONFIG=<Debug|Profile|Release>
#         -DXMC_DLL_DIR=<windows/runner 目录>
#         -DXMC_DLLS=xmc_backup,xmc_http_client,...
#         -P check_rust_dlls.cmake

if(NOT DEFINED XMC_DLL_DIR OR NOT DEFINED XMC_DLLS)
  message(FATAL_ERROR "check_rust_dlls.cmake: 缺少 XMC_DLL_DIR / XMC_DLLS 参数")
endif()

string(REPLACE "," ";" _xmc_dlls "${XMC_DLLS}")
set(_xmc_missing "")
foreach(_xmc_dll ${_xmc_dlls})
  if(NOT EXISTS "${XMC_DLL_DIR}/${_xmc_dll}.dll")
    list(APPEND _xmc_missing "${_xmc_dll}.dll")
  endif()
endforeach()

if(_xmc_missing)
  string(REPLACE ";" " " _xmc_missing_text "${_xmc_missing}")
  # 用 string(CONCAT) 拼接：CMake 中相邻字符串会被当成列表（插值时多出分号）。
  string(CONCAT _xmc_msg
    "缺少 Rust FFI 动态库：${_xmc_missing_text}\n"
    "请先运行 build_rust.bat（cargo build --release --manifest-path rust/Cargo.toml 并复制动态库到 windows/runner/）。\n"
    "缺少这些库时打出的安装包会缺失对应功能（运行期表现为 Rust xxx library not found）。")
  if(XMC_CONFIG STREQUAL "Debug")
    message(WARNING "${_xmc_msg}")
  else()
    message(FATAL_ERROR "${_xmc_msg}")
  endif()
endif()
