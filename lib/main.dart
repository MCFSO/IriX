// IriX 应用入口文件
// 提供应用根组件、主题配置与全局状态容器（MultiProvider）。
// 启动时初始化 AppState（加载持久化实例列表），主页为 HomeScreen。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/config_annotation_service.dart';
import 'services/database_manager.dart';
import 'state/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseManager.instance.init();
  await ConfigAnnotationService.instance.init();
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
      ],
      child: MaterialApp(
        title: 'IriX',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
