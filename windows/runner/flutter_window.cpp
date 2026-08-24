#include "flutter_window.h"

#include <shellapi.h>
#include <string.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // 系统托盘图标：窗口隐藏到后台后提供「显示窗口 / 退出」入口。
  AddTrayIcon();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RestoreFromBackground() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  ShowWindow(hwnd, SW_RESTORE);
  SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::AddTrayIcon() {
  if (tray_icon_created_) {
    return;
  }
  ZeroMemory(&tray_icon_data_, sizeof(tray_icon_data_));
  tray_icon_data_.cbSize = sizeof(tray_icon_data_);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = 1;
  tray_icon_data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_data_.hIcon = LoadIcon(GetModuleHandle(nullptr),
                                   MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_data_.szTip, L"IriX - 服务器管理器正在后台运行");
  tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
  if (Shell_NotifyIconW(NIM_ADD, &tray_icon_data_)) {
    Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_data_);
    tray_icon_created_ = true;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_created_) {
    return;
  }
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  tray_icon_created_ = false;
}

UINT FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return 0;
  }
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return 0;
  }
  AppendMenuW(menu, MF_STRING, kTrayMenuShow, L"显示窗口");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuExit, L"退出 IriX");

  POINT cursor;
  GetCursorPos(&cursor);
  // TrackPopupMenu 前必须前置激活，否则菜单不会随点击外部自动关闭。
  SetForegroundWindow(hwnd);
  UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, cursor.x,
                                cursor.y, 0, hwnd, nullptr);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
  return command;
}

void FlutterWindow::ShowTrayBalloon(const wchar_t* title,
                                    const wchar_t* message) {
  if (!tray_icon_created_) {
    return;
  }
  tray_icon_data_.uFlags = NIF_INFO;
  wcscpy_s(tray_icon_data_.szInfoTitle, title);
  wcscpy_s(tray_icon_data_.szInfo, message);
  tray_icon_data_.dwInfoFlags = NIIF_INFO;
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon_data_);
  tray_icon_data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    // 用户关闭窗口（点 X / Alt+F4）：隐藏到后台继续运行。
    // 服务器进程继续托管；通过托盘图标或再次启动 IriX 恢复显示。
    case WM_CLOSE: {
      ShowWindow(hwnd, SW_HIDE);
      static bool balloon_shown = false;
      if (!balloon_shown) {
        balloon_shown = true;
        ShowTrayBalloon(L"IriX 仍在后台运行",
                        L"窗口已隐藏，服务器继续托管。点击托盘图标可重新打开窗口。");
      }
      return 0;
    }

    // 托盘图标回调：双击恢复窗口；右键弹出菜单。
    case kTrayCallbackMessage:
      if (LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        RestoreFromBackground();
      } else if (LOWORD(lparam) == WM_RBUTTONUP) {
        const UINT command = ShowTrayMenu();
        if (command == kTrayMenuShow) {
          RestoreFromBackground();
        } else if (command == kTrayMenuExit) {
          // 真正退出：销毁窗口 → WM_DESTROY → 消息循环结束，应用退出。
          DestroyWindow(hwnd);
        }
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
