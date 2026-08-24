#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// 单实例互斥体名（本机会话范围内唯一）。
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\IriX-MCFSO-SingleInstance";
// 与 win32_window.cpp 中 WindowClassRegistrar 注册的窗口类名一致。
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// 持有互斥体句柄直至进程退出（保证单实例全程有效）。
HANDLE g_single_instance_mutex = nullptr;

// 若已有 IriX 实例在运行，唤醒其窗口（可能处于后台隐藏状态）并返回 true。
bool WakeExistingInstance() {
  HWND existing = FindWindowW(kWindowClassName, nullptr);
  if (existing == nullptr) {
    return false;
  }
  ShowWindow(existing, SW_RESTORE);
  // AttachThreadInput 绕过系统前台窗口限制，确保窗口可靠置前。
  const DWORD target_thread = GetWindowThreadProcessId(existing, nullptr);
  const DWORD current_thread = GetCurrentThreadId();
  AttachThreadInput(current_thread, target_thread, TRUE);
  SetForegroundWindow(existing);
  BringWindowToTop(existing);
  AttachThreadInput(current_thread, target_thread, FALSE);
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // 单实例：已有实例运行时直接唤醒其窗口后退出。
  // 避免多个 IriX 进程争抢服务器进程与日志文件。
  g_single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (g_single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (WakeExistingInstance()) {
      ::CloseHandle(g_single_instance_mutex);
      g_single_instance_mutex = nullptr;
      return EXIT_SUCCESS;
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"IriX", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (g_single_instance_mutex != nullptr) {
    ::ReleaseMutex(g_single_instance_mutex);
    ::CloseHandle(g_single_instance_mutex);
    g_single_instance_mutex = nullptr;
  }
  return EXIT_SUCCESS;
}
