#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <windows.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // 从后台（隐藏/托盘）恢复窗口并置于前台。
  // 用于：托盘双击/菜单「显示窗口」，以及第二实例启动时唤醒已有窗口。
  void RestoreFromBackground();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // 托盘图标回调消息。
  static constexpr UINT kTrayCallbackMessage = WM_APP + 1;
  // 托盘菜单命令。
  static constexpr UINT kTrayMenuShow = 1001;
  static constexpr UINT kTrayMenuExit = 1002;

  // 创建系统托盘图标（后台运行时提供「显示窗口 / 退出」入口）。
  void AddTrayIcon();
  // 移除系统托盘图标。
  void RemoveTrayIcon();
  // 弹出托盘右键菜单，返回被选中的命令。
  UINT ShowTrayMenu();
  // 显示托盘图标的气泡提示（可选）。
  void ShowTrayBalloon(const wchar_t* title, const wchar_t* message);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 托盘图标数据与状态。
  NOTIFYICONDATAW tray_icon_data_ = {};
  bool tray_icon_created_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
