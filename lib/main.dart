// IriX 应用入口文件
// 提供应用根组件、主题配置与全局状态容器（MultiProvider）。
// 启动时初始化 AppState（加载持久化实例列表），主页为 HomeScreen。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'services/config_annotation_service.dart';
import 'services/database_manager.dart';
import 'services/font_settings.dart';
import 'services/locale_settings.dart';
import 'state/app_state.dart';
import 'state/cluster_state.dart';
import 'state/node_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseManager.instance.init();
  await ConfigAnnotationService.instance.init();
  // 字体设置（UI / 终端分开管理）在构建 UI 前加载。
  await FontSettings.instance.load();
  // 界面语言偏好在构建 UI 前加载。
  await LocaleSettings.instance.load();
  runApp(const MyApp());
}

/// 应用根组件。
///
/// 使用 [MultiProvider] 包裹 [MaterialApp]，注入 [AppState] 作为全局状态。
/// 启动时触发 [AppState.init] 加载持久化实例列表。
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final state = AppState();
            // 异步加载持久化实例列表，加载后 notifyListeners 会刷新 UI。
            state.init();
            return state;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final state = NodeState();
            // 异步加载持久化节点列表，加载后 notifyListeners 会刷新 UI。
            state.init();
            return state;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final state = ClusterState();
            // 异步加载管理模式、监控节点与集群实例列表。
            state.init();
            return state;
          },
        ),
        // 字体设置（UI / 终端分开管理）。修改后通过 Consumer 重建整个
        // MaterialApp，使字体变更立即生效。
        ChangeNotifierProvider(create: (_) => FontSettings.instance),
        // 界面语言偏好。修改后通过 Consumer 重建 MaterialApp，使 locale
        // 切换立即生效。
        ChangeNotifierProvider(create: (_) => LocaleSettings.instance),
      ],
      child: Consumer<LocaleSettings>(
        builder: (context, locale, _) => Consumer<FontSettings>(
          builder: (context, fonts, _) => MaterialApp(
            title: 'IriX',
            debugShowCheckedModeBanner: false,
            // i18n：locale 为 null 时跟随系统；支持 zh / en。
            locale: locale.localeCode == null
                ? null
                : (locale.localeCode == 'zh'
                    ? const Locale('zh')
                    : const Locale('en')),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.green,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              // 全局 UI 字体（默认内置 MiSans；空字符串 = 系统默认）。
              fontFamily: fonts.uiFontFamily,
            ),
            home: const HomeScreen(),
          ),
        ),
      ),
    );
  }
}
