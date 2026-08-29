import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// 保存
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get common_save;

  /// 取消
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get common_cancel;

  /// 删除
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get common_delete;

  /// 编辑
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get common_edit;

  /// 刷新
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get common_refresh;

  /// 重试
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get common_retry;

  /// 确定
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get common_confirm;

  /// 关闭
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get common_close;

  /// 添加
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get common_add;

  /// 搜索
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get common_search;

  /// 名称
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get common_name;

  /// 状态
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get common_status;

  /// 操作
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get common_action;

  /// 加载中
  ///
  /// In zh, this message translates to:
  /// **'加载中…'**
  String get common_loading;

  /// 错误
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get common_error;

  /// 成功
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get common_success;

  /// 复制
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get common_copy;

  /// 移除
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get common_remove;

  /// 好的
  ///
  /// In zh, this message translates to:
  /// **'好的'**
  String get common_ok;

  /// 返回
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get common_back;

  /// 重置
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get common_reset;

  /// 应用
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get common_apply;

  /// 确认删除标题
  ///
  /// In zh, this message translates to:
  /// **'确认删除'**
  String get common_confirmDelete;

  /// 打开
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get common_open;

  /// 已启用
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get common_enabled;

  /// 已关闭
  ///
  /// In zh, this message translates to:
  /// **'已关闭'**
  String get common_disabled;

  /// 通用删除确认（含项目名）
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」吗？此操作不可撤销。'**
  String common_deleteItemConfirm(String name);

  /// 项目计数（英文需单复数）
  ///
  /// In zh, this message translates to:
  /// **'{count} 个项目'**
  String common_itemCount(int count);

  /// 相对时间-分钟
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟前'**
  String common_timeMinutesAgo(int minutes);

  /// 相对时间-小时
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时前'**
  String common_timeHoursAgo(int hours);

  /// 相对时间-天
  ///
  /// In zh, this message translates to:
  /// **'{days} 天前'**
  String common_timeDaysAgo(int days);

  /// 相对时间-月
  ///
  /// In zh, this message translates to:
  /// **'{months} 个月前'**
  String common_timeMonthsAgo(int months);

  /// 相对时间-年
  ///
  /// In zh, this message translates to:
  /// **'{years} 年前'**
  String common_timeYearsAgo(int years);

  /// 语言设置标签
  ///
  /// In zh, this message translates to:
  /// **'界面语言'**
  String get common_language;

  /// 语言-跟随系统
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get common_languageSystem;

  /// 语言-简体中文
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get common_languageChinese;

  /// 语言-英文
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get common_languageEnglish;

  /// 设置对话框标题
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings_title;

  /// 管理模式标题
  ///
  /// In zh, this message translates to:
  /// **'多机管理模式'**
  String get settings_multiMode;

  /// 多机模式说明
  ///
  /// In zh, this message translates to:
  /// **'实例分布到多个节点，自动分配资源、崩溃迁移与数据同步'**
  String get settings_multiModeOn;

  /// 单机模式说明
  ///
  /// In zh, this message translates to:
  /// **'单机模式：实例在本机运行'**
  String get settings_singleMode;

  /// 多机模式提示
  ///
  /// In zh, this message translates to:
  /// **'多机模式需至少 2 个节点，可在「主页」中添加。'**
  String get settings_multiModeHint;

  /// Vault 标题
  ///
  /// In zh, this message translates to:
  /// **'Vault 加密保险库'**
  String get settings_vault;

  /// Vault 启用说明
  ///
  /// In zh, this message translates to:
  /// **'已启用：节点详情 / 解锁 / 初始化 / 证书绑定等保险库能力可用'**
  String get settings_vaultOn;

  /// Vault 关闭说明
  ///
  /// In zh, this message translates to:
  /// **'关闭：不展示保险库相关能力（节点需以 -vault 开启并配置 TLS）'**
  String get settings_vaultOff;

  /// 下载线程数
  ///
  /// In zh, this message translates to:
  /// **'下载线程数: {count}'**
  String settings_downloadThreads(int count);

  /// 下载线程提示
  ///
  /// In zh, this message translates to:
  /// **'多线程分片断点续传；服务端不支持 Range 时自动回退单线程。'**
  String get settings_downloadThreadsHint;

  /// 数据库每页行数
  ///
  /// In zh, this message translates to:
  /// **'数据库每页行数: {count}'**
  String settings_dbPageSize(int count);

  /// 数据库分页提示
  ///
  /// In zh, this message translates to:
  /// **'浏览数据库表数据时每页显示的行数。'**
  String get settings_dbPageSizeHint;

  /// 字体标题
  ///
  /// In zh, this message translates to:
  /// **'字体'**
  String get settings_font;

  /// 字体说明
  ///
  /// In zh, this message translates to:
  /// **'终端（控制台 / 日志 / 代码）与其余界面字体分开设置；其余界面默认 MiSans，终端默认 JetBrains Mono。'**
  String get settings_fontHint;

  /// 界面字体标签
  ///
  /// In zh, this message translates to:
  /// **'界面字体'**
  String get settings_uiFont;

  /// 终端字体标签
  ///
  /// In zh, this message translates to:
  /// **'终端字体'**
  String get settings_terminalFont;

  /// 字体回退提示
  ///
  /// In zh, this message translates to:
  /// **'未安装的系统字体（如 JetBrains Mono）会自动回退到默认字体。'**
  String get settings_fontFallbackHint;

  /// 重命名节点对话框标题
  ///
  /// In zh, this message translates to:
  /// **'重命名节点'**
  String get node_renameTitle;

  /// 节点名称输入框提示
  ///
  /// In zh, this message translates to:
  /// **'节点名称'**
  String get node_nameHint;

  /// 删除节点确认标题
  ///
  /// In zh, this message translates to:
  /// **'删除节点「{name}」？'**
  String node_deleteConfirmTitle(String name);

  /// 删除节点确认内容
  ///
  /// In zh, this message translates to:
  /// **'仅删除本地保存的节点信息，不会影响服务器上的数据。'**
  String get node_deleteConfirmContent;

  /// 节点在线状态
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get node_online;

  /// 节点离线状态
  ///
  /// In zh, this message translates to:
  /// **'离线'**
  String get node_offline;

  /// 节点菜单-重命名
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get node_renameMenu;

  /// 节点菜单-删除
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get node_deleteMenu;

  /// container_tabContainers
  ///
  /// In zh, this message translates to:
  /// **'容器'**
  String get container_tabContainers;

  /// container_tabRelease
  ///
  /// In zh, this message translates to:
  /// **'发行'**
  String get container_tabRelease;

  /// container_tabForward
  ///
  /// In zh, this message translates to:
  /// **'转发'**
  String get container_tabForward;

  /// container_tabSettings
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get container_tabSettings;

  /// container_tabImages
  ///
  /// In zh, this message translates to:
  /// **'镜像'**
  String get container_tabImages;

  /// container_tabVolumes
  ///
  /// In zh, this message translates to:
  /// **'卷'**
  String get container_tabVolumes;

  /// container_tabNetworks
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get container_tabNetworks;

  /// container_jailList
  ///
  /// In zh, this message translates to:
  /// **'Jail 列表'**
  String get container_jailList;

  /// container_containerList
  ///
  /// In zh, this message translates to:
  /// **'容器列表'**
  String get container_containerList;

  /// container_import
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get container_import;

  /// container_createJail
  ///
  /// In zh, this message translates to:
  /// **'创建 Jail'**
  String get container_createJail;

  /// container_createContainer
  ///
  /// In zh, this message translates to:
  /// **'创建容器'**
  String get container_createContainer;

  /// container_noJails
  ///
  /// In zh, this message translates to:
  /// **'暂无 Jail'**
  String get container_noJails;

  /// container_noContainers
  ///
  /// In zh, this message translates to:
  /// **'暂无容器'**
  String get container_noContainers;

  /// container_bootstrappedReleases
  ///
  /// In zh, this message translates to:
  /// **'已 Bootstrap 的发行版'**
  String get container_bootstrappedReleases;

  /// container_imageList
  ///
  /// In zh, this message translates to:
  /// **'镜像列表'**
  String get container_imageList;

  /// container_bootstrap
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap'**
  String get container_bootstrap;

  /// container_pull
  ///
  /// In zh, this message translates to:
  /// **'拉取'**
  String get container_pull;

  /// container_build
  ///
  /// In zh, this message translates to:
  /// **'构建'**
  String get container_build;

  /// container_noReleases
  ///
  /// In zh, this message translates to:
  /// **'暂无发行版，点击 Bootstrap 拉取（如 14.2-RELEASE）'**
  String get container_noReleases;

  /// container_noImages
  ///
  /// In zh, this message translates to:
  /// **'暂无镜像'**
  String get container_noImages;

  /// container_deleteImage
  ///
  /// In zh, this message translates to:
  /// **'删除镜像'**
  String get container_deleteImage;

  /// container_bootstrapRelease
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap 发行版'**
  String get container_bootstrapRelease;

  /// container_pullImage
  ///
  /// In zh, this message translates to:
  /// **'拉取镜像'**
  String get container_pullImage;

  /// container_releaseName
  ///
  /// In zh, this message translates to:
  /// **'发行版名称'**
  String get container_releaseName;

  /// container_imageName
  ///
  /// In zh, this message translates to:
  /// **'镜像名称'**
  String get container_imageName;

  /// container_releaseNameHint
  ///
  /// In zh, this message translates to:
  /// **'如 14.2-RELEASE'**
  String get container_releaseNameHint;

  /// container_imageNameHint
  ///
  /// In zh, this message translates to:
  /// **'如 itzg/minecraft-server:latest'**
  String get container_imageNameHint;

  /// container_rdrRules
  ///
  /// In zh, this message translates to:
  /// **'端口转发规则（bastille rdr）'**
  String get container_rdrRules;

  /// container_addForward
  ///
  /// In zh, this message translates to:
  /// **'添加转发'**
  String get container_addForward;

  /// container_noRdrRules
  ///
  /// In zh, this message translates to:
  /// **'暂无转发规则'**
  String get container_noRdrRules;

  /// container_deleteForward
  ///
  /// In zh, this message translates to:
  /// **'删除转发'**
  String get container_deleteForward;

  /// container_forwardDeleted
  ///
  /// In zh, this message translates to:
  /// **'转发规则已删除'**
  String get container_forwardDeleted;

  /// container_forwardAdded
  ///
  /// In zh, this message translates to:
  /// **'转发规则已添加'**
  String get container_forwardAdded;

  /// container_deleteVolume
  ///
  /// In zh, this message translates to:
  /// **'删除卷'**
  String get container_deleteVolume;

  /// container_volumeList
  ///
  /// In zh, this message translates to:
  /// **'卷列表'**
  String get container_volumeList;

  /// container_networkList
  ///
  /// In zh, this message translates to:
  /// **'网络列表'**
  String get container_networkList;

  /// container_noVolumes
  ///
  /// In zh, this message translates to:
  /// **'暂无卷'**
  String get container_noVolumes;

  /// container_noNetworks
  ///
  /// In zh, this message translates to:
  /// **'暂无网络'**
  String get container_noNetworks;

  /// container_start
  ///
  /// In zh, this message translates to:
  /// **'启动'**
  String get container_start;

  /// container_stop
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get container_stop;

  /// container_manageDetail
  ///
  /// In zh, this message translates to:
  /// **'管理（详情）'**
  String get container_manageDetail;

  /// container_moreActions
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get container_moreActions;

  /// container_restart
  ///
  /// In zh, this message translates to:
  /// **'重启'**
  String get container_restart;

  /// container_clone
  ///
  /// In zh, this message translates to:
  /// **'克隆'**
  String get container_clone;

  /// container_resourceLimit
  ///
  /// In zh, this message translates to:
  /// **'资源限制'**
  String get container_resourceLimit;

  /// container_exportArchive
  ///
  /// In zh, this message translates to:
  /// **'导出归档'**
  String get container_exportArchive;

  /// container_status
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get container_status;

  /// container_image
  ///
  /// In zh, this message translates to:
  /// **'镜像'**
  String get container_image;

  /// container_ports
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get container_ports;

  /// container_createdAt
  ///
  /// In zh, this message translates to:
  /// **'创建时间'**
  String get container_createdAt;

  /// container_confirmOperation
  ///
  /// In zh, this message translates to:
  /// **'确认操作'**
  String get container_confirmOperation;

  /// container_exportSavedPath
  ///
  /// In zh, this message translates to:
  /// **'归档已保存到节点上的路径：'**
  String get container_exportSavedPath;

  /// container_redetect
  ///
  /// In zh, this message translates to:
  /// **'重新检测'**
  String get container_redetect;

  /// container_envUnavailableBastille
  ///
  /// In zh, this message translates to:
  /// **'Bastille 运行在 FreeBSD 节点上：请在「节点管理」中添加在线 FreeBSD 节点（irix-node）后，从节点详情页的「容器」Tab 管理 jail。'**
  String get container_envUnavailableBastille;

  /// container_envUnavailableDocker
  ///
  /// In zh, this message translates to:
  /// **'本机使用 Docker 环境：安装并启动 Docker Desktop（或安装 docker CLI）后点击「重新检测」即可使用全部容器功能。'**
  String get container_envUnavailableDocker;

  /// container_nameHelperBastille
  ///
  /// In zh, this message translates to:
  /// **'仅字母、数字、- 和 _，不能为纯数字'**
  String get container_nameHelperBastille;

  /// container_release
  ///
  /// In zh, this message translates to:
  /// **'发行版'**
  String get container_release;

  /// container_imageHelper
  ///
  /// In zh, this message translates to:
  /// **'如 itzg/minecraft-server:latest'**
  String get container_imageHelper;

  /// container_releaseHelper
  ///
  /// In zh, this message translates to:
  /// **'如 14.2-RELEASE（需先 Bootstrap）'**
  String get container_releaseHelper;

  /// container_ipAddress
  ///
  /// In zh, this message translates to:
  /// **'IP 地址'**
  String get container_ipAddress;

  /// container_ipHelper
  ///
  /// In zh, this message translates to:
  /// **'含前缀，如 192.168.1.50/24'**
  String get container_ipHelper;

  /// container_jailType
  ///
  /// In zh, this message translates to:
  /// **'Jail 类型'**
  String get container_jailType;

  /// container_jailTypeThin
  ///
  /// In zh, this message translates to:
  /// **'thin — 符号链接样板（默认）'**
  String get container_jailTypeThin;

  /// container_jailTypeThick
  ///
  /// In zh, this message translates to:
  /// **'thick — 厚容器（-T 解压样板）'**
  String get container_jailTypeThick;

  /// container_jailTypeClone
  ///
  /// In zh, this message translates to:
  /// **'clone — 克隆现有发行版'**
  String get container_jailTypeClone;

  /// container_jailTypeEmpty
  ///
  /// In zh, this message translates to:
  /// **'empty — 空容器（-E，仅需名称）'**
  String get container_jailTypeEmpty;

  /// container_jailTypeLinux
  ///
  /// In zh, this message translates to:
  /// **'linux — Linux Jail（-L）'**
  String get container_jailTypeLinux;

  /// container_vnetMode
  ///
  /// In zh, this message translates to:
  /// **'VNET 模式'**
  String get container_vnetMode;

  /// container_vnetModeNone
  ///
  /// In zh, this message translates to:
  /// **'不使用 VNET（共享宿主网络）'**
  String get container_vnetModeNone;

  /// container_vnetModeVnet
  ///
  /// In zh, this message translates to:
  /// **'VNET（-V，网卡须为物理网卡）'**
  String get container_vnetModeVnet;

  /// container_vnetModeBridge
  ///
  /// In zh, this message translates to:
  /// **'桥接 VNET（-B，网卡须为桥接网卡）'**
  String get container_vnetModeBridge;

  /// container_bridgeNic
  ///
  /// In zh, this message translates to:
  /// **'桥接网卡'**
  String get container_bridgeNic;

  /// container_physicalNic
  ///
  /// In zh, this message translates to:
  /// **'物理网卡'**
  String get container_physicalNic;

  /// container_bridgeNicHint
  ///
  /// In zh, this message translates to:
  /// **'如 bridge0'**
  String get container_bridgeNicHint;

  /// container_physicalNicHint
  ///
  /// In zh, this message translates to:
  /// **'如 em0'**
  String get container_physicalNicHint;

  /// container_portMapping
  ///
  /// In zh, this message translates to:
  /// **'端口映射'**
  String get container_portMapping;

  /// container_portMappingHelper
  ///
  /// In zh, this message translates to:
  /// **'宿主机端口:容器端口，多个用逗号分隔'**
  String get container_portMappingHelper;

  /// container_portMappingHelperBastille
  ///
  /// In zh, this message translates to:
  /// **'宿主机端口:jail 端口，多个用逗号分隔；创建后经 rdr 自动应用'**
  String get container_portMappingHelperBastille;

  /// container_dataMount
  ///
  /// In zh, this message translates to:
  /// **'数据目录挂载（nullfs）'**
  String get container_dataMount;

  /// container_volumeMount
  ///
  /// In zh, this message translates to:
  /// **'卷挂载'**
  String get container_volumeMount;

  /// container_dataMountHelper
  ///
  /// In zh, this message translates to:
  /// **'宿主机路径:jail 内路径，多个用逗号分隔'**
  String get container_dataMountHelper;

  /// container_volumeMountHelper
  ///
  /// In zh, this message translates to:
  /// **'宿主机路径:容器路径，多个用逗号分隔'**
  String get container_volumeMountHelper;

  /// container_envVars
  ///
  /// In zh, this message translates to:
  /// **'环境变量'**
  String get container_envVars;

  /// container_envVarsHelper
  ///
  /// In zh, this message translates to:
  /// **'每行一个 KEY=VALUE，如 MEMORY=2G、EULA=TRUE'**
  String get container_envVarsHelper;

  /// container_restartPolicy
  ///
  /// In zh, this message translates to:
  /// **'重启策略'**
  String get container_restartPolicy;

  /// container_restartNo
  ///
  /// In zh, this message translates to:
  /// **'no — 不自动重启'**
  String get container_restartNo;

  /// container_restartUnlessStopped
  ///
  /// In zh, this message translates to:
  /// **'unless-stopped — 退出自动重启'**
  String get container_restartUnlessStopped;

  /// container_restartAlways
  ///
  /// In zh, this message translates to:
  /// **'always — 总是重启'**
  String get container_restartAlways;

  /// container_restartOnFailure
  ///
  /// In zh, this message translates to:
  /// **'on-failure — 异常退出时重启'**
  String get container_restartOnFailure;

  /// container_startCommand
  ///
  /// In zh, this message translates to:
  /// **'启动命令（留空用镜像默认）'**
  String get container_startCommand;

  /// container_workdir
  ///
  /// In zh, this message translates to:
  /// **'工作目录（留空默认）'**
  String get container_workdir;

  /// container_workdirHelper
  ///
  /// In zh, this message translates to:
  /// **'如 /data —— 强制在挂载的数据目录内启动'**
  String get container_workdirHelper;

  /// container_memoryLimit
  ///
  /// In zh, this message translates to:
  /// **'内存上限（MB，留空不限）'**
  String get container_memoryLimit;

  /// container_cpuCores
  ///
  /// In zh, this message translates to:
  /// **'CPU 核数（留空不限）'**
  String get container_cpuCores;

  /// container_diskLimit
  ///
  /// In zh, this message translates to:
  /// **'磁盘上限（MB，留空不限）'**
  String get container_diskLimit;

  /// container_diskLimitHelper
  ///
  /// In zh, this message translates to:
  /// **'依赖存储驱动支持 size 配额'**
  String get container_diskLimitHelper;

  /// container_diskLimitHelperBastille
  ///
  /// In zh, this message translates to:
  /// **'ZFS 数据集配额'**
  String get container_diskLimitHelperBastille;

  /// container_createHintBastille
  ///
  /// In zh, this message translates to:
  /// **'提示：thin（默认）/ thick（-T）/ clone（-C）/ empty（-E，仅需名称）/ linux（-L）为互斥的创建方式；Linux Jail 不能与 VNET（-V/-B）同时使用；VNET 需先完成「设置」页的网络初始化，IP 必须含子网掩码。'**
  String get container_createHintBastille;

  /// container_enterJailName
  ///
  /// In zh, this message translates to:
  /// **'请填写 Jail 名称'**
  String get container_enterJailName;

  /// container_nameAndImageRequired
  ///
  /// In zh, this message translates to:
  /// **'名称与镜像 / 发行版不能为空'**
  String get container_nameAndImageRequired;

  /// container_jailNameRule
  ///
  /// In zh, this message translates to:
  /// **'Jail 名仅允许字母、数字、- 和 _，且不能为纯数字'**
  String get container_jailNameRule;

  /// container_jailIpRequired
  ///
  /// In zh, this message translates to:
  /// **'Bastille 创建 Jail 必须显式声明 IP 地址'**
  String get container_jailIpRequired;

  /// container_linuxVnetConflict
  ///
  /// In zh, this message translates to:
  /// **'Linux Jail（-L）不能与 VNET（-V/-B）同时使用'**
  String get container_linuxVnetConflict;

  /// container_enterBridgeNic
  ///
  /// In zh, this message translates to:
  /// **'请填写桥接网卡名称'**
  String get container_enterBridgeNic;

  /// container_enterPhysicalNic
  ///
  /// In zh, this message translates to:
  /// **'请填写物理网卡名称'**
  String get container_enterPhysicalNic;

  /// container_vnetIpMustContainMask
  ///
  /// In zh, this message translates to:
  /// **'VNET Jail 的 IP 必须含子网掩码，如 192.168.1.50/24'**
  String get container_vnetIpMustContainMask;

  /// container_newName
  ///
  /// In zh, this message translates to:
  /// **'新名称'**
  String get container_newName;

  /// container_notPureNumber
  ///
  /// In zh, this message translates to:
  /// **'不能为纯数字'**
  String get container_notPureNumber;

  /// container_newIp
  ///
  /// In zh, this message translates to:
  /// **'新 IP 地址（留空沿用源，需含前缀）'**
  String get container_newIp;

  /// container_newIpHint
  ///
  /// In zh, this message translates to:
  /// **'如 192.168.1.51/24'**
  String get container_newIpHint;

  /// container_resourceLimits
  ///
  /// In zh, this message translates to:
  /// **'资源限制'**
  String get container_resourceLimits;

  /// container_memoryLimitKeep
  ///
  /// In zh, this message translates to:
  /// **'内存上限（MB，留空不变）'**
  String get container_memoryLimitKeep;

  /// container_cpuCoresKeep
  ///
  /// In zh, this message translates to:
  /// **'CPU 核数（留空不变）'**
  String get container_cpuCoresKeep;

  /// container_diskLimitKeep
  ///
  /// In zh, this message translates to:
  /// **'磁盘上限（MB，留空不变）'**
  String get container_diskLimitKeep;

  /// container_diskLimitKeepHelper
  ///
  /// In zh, this message translates to:
  /// **'Docker 不支持热更新磁盘上限'**
  String get container_diskLimitKeepHelper;

  /// container_jail
  ///
  /// In zh, this message translates to:
  /// **'Jail'**
  String get container_jail;

  /// container_protocol
  ///
  /// In zh, this message translates to:
  /// **'协议'**
  String get container_protocol;

  /// container_hostPort
  ///
  /// In zh, this message translates to:
  /// **'宿主机端口'**
  String get container_hostPort;

  /// container_jailPort
  ///
  /// In zh, this message translates to:
  /// **'Jail 内端口'**
  String get container_jailPort;

  /// container_archivePath
  ///
  /// In zh, this message translates to:
  /// **'归档路径（节点上的归档文件）'**
  String get container_archivePath;

  /// container_archivePathHint
  ///
  /// In zh, this message translates to:
  /// **'如 /usr/local/bastille/backups/xxx.txz'**
  String get container_archivePathHint;

  /// container_specifyRelease
  ///
  /// In zh, this message translates to:
  /// **'指定发行版（留空按归档内名称）'**
  String get container_specifyRelease;

  /// container_specifyReleaseHint
  ///
  /// In zh, this message translates to:
  /// **'如 14.2-RELEASE'**
  String get container_specifyReleaseHint;

  /// container_skipChecksum
  ///
  /// In zh, this message translates to:
  /// **'跳过校验和验证（-f / --force）'**
  String get container_skipChecksum;

  /// container_importJail
  ///
  /// In zh, this message translates to:
  /// **'导入 Jail'**
  String get container_importJail;

  /// container_setupDefaultTitle
  ///
  /// In zh, this message translates to:
  /// **'一键默认初始化'**
  String get container_setupDefaultTitle;

  /// container_setupDefaultDesc
  ///
  /// In zh, this message translates to:
  /// **'不带选项执行 bastille setup：自动配置 loopback（bastille0）、firewall 与 storage。多数场景足够使用。'**
  String get container_setupDefaultDesc;

  /// container_setupDefaultRun
  ///
  /// In zh, this message translates to:
  /// **'执行 bastille setup'**
  String get container_setupDefaultRun;

  /// container_setupFirewallTitle
  ///
  /// In zh, this message translates to:
  /// **'防火墙（firewall）'**
  String get container_setupFirewallTitle;

  /// container_setupFirewallDesc
  ///
  /// In zh, this message translates to:
  /// **'配置 PF 防火墙：启用服务并生成默认 pf.conf —— 端口转发（bastille rdr）的前提。'**
  String get container_setupFirewallDesc;

  /// container_setupFirewallRun
  ///
  /// In zh, this message translates to:
  /// **'执行 bastille setup firewall'**
  String get container_setupFirewallRun;

  /// container_setupVnetTitle
  ///
  /// In zh, this message translates to:
  /// **'VNET 网络（vnet）'**
  String get container_setupVnetTitle;

  /// container_setupVnetDesc
  ///
  /// In zh, this message translates to:
  /// **'为 VNET jail（-V）配置宿主网络。参数为可选项（部分版本为交互式，由服务端注入）。'**
  String get container_setupVnetDesc;

  /// container_setupVnetRun
  ///
  /// In zh, this message translates to:
  /// **'执行 bastille setup vnet'**
  String get container_setupVnetRun;

  /// container_setupBridgeTitle
  ///
  /// In zh, this message translates to:
  /// **'桥接网络（bridge）'**
  String get container_setupBridgeTitle;

  /// container_setupBridgeDesc
  ///
  /// In zh, this message translates to:
  /// **'配置桥接网卡 —— 桥接 VNET jail（-B）的前提。需先在系统上创建 bridge 接口（如 ifconfig bridge create）。'**
  String get container_setupBridgeDesc;

  /// container_setupBridgeRun
  ///
  /// In zh, this message translates to:
  /// **'执行 bastille setup bridge'**
  String get container_setupBridgeRun;

  /// container_setupSharedTitle
  ///
  /// In zh, this message translates to:
  /// **'共享网卡（shared）'**
  String get container_setupSharedTitle;

  /// container_setupSharedDesc
  ///
  /// In zh, this message translates to:
  /// **'将指定网卡设为共享接口：create 未指定 INTERFACE 时默认使用。与 loopback 互斥（配置其一将禁用另一项）。'**
  String get container_setupSharedDesc;

  /// container_setupSharedRun
  ///
  /// In zh, this message translates to:
  /// **'执行 bastille setup shared'**
  String get container_setupSharedRun;

  /// container_setupLinuxTitle
  ///
  /// In zh, this message translates to:
  /// **'Linux Jail（linux）'**
  String get container_setupLinuxTitle;

  /// container_setupLinuxDesc
  ///
  /// In zh, this message translates to:
  /// **'初始化 Linuxulator —— 创建 Linux jail（-L）的前提：加载所需内核模块并安装 debootstrap 包。'**
  String get container_setupLinuxDesc;

  /// container_setupLinuxRun
  ///
  /// In zh, this message translates to:
  /// **'执行 bastille setup linux'**
  String get container_setupLinuxRun;

  /// container_setupFieldExtIf
  ///
  /// In zh, this message translates to:
  /// **'外网网卡'**
  String get container_setupFieldExtIf;

  /// container_setupFieldExtIfHint
  ///
  /// In zh, this message translates to:
  /// **'如 em0'**
  String get container_setupFieldExtIfHint;

  /// container_setupFieldTunIf
  ///
  /// In zh, this message translates to:
  /// **'桥接网卡'**
  String get container_setupFieldTunIf;

  /// container_setupFieldTunIfHint
  ///
  /// In zh, this message translates to:
  /// **'默认 bastille0'**
  String get container_setupFieldTunIfHint;

  /// container_setupFieldAddr
  ///
  /// In zh, this message translates to:
  /// **'网段'**
  String get container_setupFieldAddr;

  /// container_setupFieldAddrHint
  ///
  /// In zh, this message translates to:
  /// **'如 10.99.0.0/24'**
  String get container_setupFieldAddrHint;

  /// container_setupFieldNic
  ///
  /// In zh, this message translates to:
  /// **'网卡'**
  String get container_setupFieldNic;

  /// container_enterNicName
  ///
  /// In zh, this message translates to:
  /// **'请填写网卡名称'**
  String get container_enterNicName;

  /// container_initDone
  ///
  /// In zh, this message translates to:
  /// **'初始化完成'**
  String get container_initDone;

  /// container_initFailed
  ///
  /// In zh, this message translates to:
  /// **'初始化失败'**
  String get container_initFailed;

  /// container_buildImage
  ///
  /// In zh, this message translates to:
  /// **'构建镜像'**
  String get container_buildImage;

  /// container_tag
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get container_tag;

  /// container_dockerfile
  ///
  /// In zh, this message translates to:
  /// **'Dockerfile'**
  String get container_dockerfile;

  /// container_buildContextNote
  ///
  /// In zh, this message translates to:
  /// **'构建上下文为 stdin（与 MCSM dockerFile 一致）；需要 COPY 本地文件时请把文件放进镜像基础层。'**
  String get container_buildContextNote;

  /// container_startBuild
  ///
  /// In zh, this message translates to:
  /// **'开始构建'**
  String get container_startBuild;

  /// container_buildDone
  ///
  /// In zh, this message translates to:
  /// **'构建完成'**
  String get container_buildDone;

  /// container_buildFailed
  ///
  /// In zh, this message translates to:
  /// **'构建失败'**
  String get container_buildFailed;

  /// container_building
  ///
  /// In zh, this message translates to:
  /// **'构建中...'**
  String get container_building;

  /// container_waitingBuildOutput
  ///
  /// In zh, this message translates to:
  /// **'等待构建输出...'**
  String get container_waitingBuildOutput;

  /// container_buildInBackground
  ///
  /// In zh, this message translates to:
  /// **'后台构建'**
  String get container_buildInBackground;

  /// No description provided for @container_operationSuccess.
  ///
  /// In zh, this message translates to:
  /// **'操作成功：{name}'**
  String container_operationSuccess(String name);

  /// No description provided for @container_created.
  ///
  /// In zh, this message translates to:
  /// **'已创建：{name}'**
  String container_created(String name);

  /// No description provided for @container_cloned.
  ///
  /// In zh, this message translates to:
  /// **'已克隆为：{name}'**
  String container_cloned(String name);

  /// No description provided for @container_limitsUpdated.
  ///
  /// In zh, this message translates to:
  /// **'资源限制已更新：{name}'**
  String container_limitsUpdated(String name);

  /// No description provided for @container_exportDone.
  ///
  /// In zh, this message translates to:
  /// **'导出完成：{name}'**
  String container_exportDone(String name);

  /// No description provided for @container_importDone.
  ///
  /// In zh, this message translates to:
  /// **'导入完成：{name}'**
  String container_importDone(String name);

  /// No description provided for @container_buildTitle.
  ///
  /// In zh, this message translates to:
  /// **'构建 {imageName}'**
  String container_buildTitle(String imageName);

  /// No description provided for @container_envUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'{name} 不可用'**
  String container_envUnavailable(String name);

  /// No description provided for @container_envLabel.
  ///
  /// In zh, this message translates to:
  /// **'{name} 环境'**
  String container_envLabel(String name);

  /// No description provided for @container_deleteConfirmContainer.
  ///
  /// In zh, this message translates to:
  /// **'确定删除容器 {name} 吗？'**
  String container_deleteConfirmContainer(String name);

  /// No description provided for @container_deleteConfirmJail.
  ///
  /// In zh, this message translates to:
  /// **'确定删除 Jail {name} 吗？'**
  String container_deleteConfirmJail(String name);

  /// No description provided for @container_deleteVolumeConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除卷 {name} 吗？'**
  String container_deleteVolumeConfirm(String name);

  /// No description provided for @container_bootstrapSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'Bootstrap 任务已提交：{name}（后台进行，稍后刷新列表）'**
  String container_bootstrapSubmitted(String name);

  /// No description provided for @container_pullDone.
  ///
  /// In zh, this message translates to:
  /// **'镜像拉取完成：{name}'**
  String container_pullDone(String name);

  /// No description provided for @container_cloneTitle.
  ///
  /// In zh, this message translates to:
  /// **'克隆 {source}'**
  String container_cloneTitle(String source);

  /// No description provided for @container_portFormatError.
  ///
  /// In zh, this message translates to:
  /// **'端口格式错误：{port}（应为 宿主机:容器端口）'**
  String container_portFormatError(String port);

  /// No description provided for @container_deleteImageConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除镜像 {tag} 吗？'**
  String container_deleteImageConfirm(String tag);

  /// No description provided for @container_rdrSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'{proto}  宿主机 {hostPort} → jail {containerPort}'**
  String container_rdrSubtitle(String proto, int hostPort, int containerPort);

  /// No description provided for @container_deleteForwardConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除 {container} 的 {proto} {hostPort}→{containerPort} 吗？'**
  String container_deleteForwardConfirm(
    String container,
    String proto,
    int hostPort,
    int containerPort,
  );

  /// addNode_title
  ///
  /// In zh, this message translates to:
  /// **'添加节点'**
  String get addNode_title;

  /// addNode_fillAddressFirst
  ///
  /// In zh, this message translates to:
  /// **'请先填写地址'**
  String get addNode_fillAddressFirst;

  /// addNode_connectSuccess
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get addNode_connectSuccess;

  /// addNode_connectFailed
  ///
  /// In zh, this message translates to:
  /// **'连接失败，请检查地址与 API Key'**
  String get addNode_connectFailed;

  /// addNode_fillNodeAddress
  ///
  /// In zh, this message translates to:
  /// **'请填写节点地址'**
  String get addNode_fillNodeAddress;

  /// addNode_mcsmApiKeyRequired
  ///
  /// In zh, this message translates to:
  /// **'MCSM 节点需要填写 API Key'**
  String get addNode_mcsmApiKeyRequired;

  /// addNode_remoteNodeKeyRequired
  ///
  /// In zh, this message translates to:
  /// **'远程 Node 节点必须填写密钥（仅本机回环地址可留空）'**
  String get addNode_remoteNodeKeyRequired;

  /// addNode_plaintextWarningTitle
  ///
  /// In zh, this message translates to:
  /// **'明文连接警告'**
  String get addNode_plaintextWarningTitle;

  /// addNode_plaintextWarningContent
  ///
  /// In zh, this message translates to:
  /// **'该节点地址使用明文 HTTP（非 https），API 密钥与全部控制流量（含文件读写、命令执行）可被同网段窃听或篡改。'**
  String get addNode_plaintextWarningContent;

  /// addNode_continueAnyway
  ///
  /// In zh, this message translates to:
  /// **'仍然继续'**
  String get addNode_continueAnyway;

  /// addNode_cancelledEnableHttps
  ///
  /// In zh, this message translates to:
  /// **'已取消：请为节点启用 HTTPS'**
  String get addNode_cancelledEnableHttps;

  /// addNode_prevStep
  ///
  /// In zh, this message translates to:
  /// **'上一步'**
  String get addNode_prevStep;

  /// addNode_nextStep
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get addNode_nextStep;

  /// addNode_testConnection
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get addNode_testConnection;

  /// addNode_finish
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get addNode_finish;

  /// addNode_stepType
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get addNode_stepType;

  /// addNode_stepName
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get addNode_stepName;

  /// addNode_stepKey
  ///
  /// In zh, this message translates to:
  /// **'Key'**
  String get addNode_stepKey;

  /// addNode_selectType
  ///
  /// In zh, this message translates to:
  /// **'选择节点类型'**
  String get addNode_selectType;

  /// addNode_mcsmSubtitle
  ///
  /// In zh, this message translates to:
  /// **'连接远程 MCSManager 面板\n需填写面板 API Key'**
  String get addNode_mcsmSubtitle;

  /// addNode_nodeSubtitle
  ///
  /// In zh, this message translates to:
  /// **'IriX 本地 Go 语言节点\n本机回环可免密钥，远程必须配置密钥'**
  String get addNode_nodeSubtitle;

  /// addNode_nameHint
  ///
  /// In zh, this message translates to:
  /// **'例如：我的面板 / 本地节点'**
  String get addNode_nameHint;

  /// addNode_address
  ///
  /// In zh, this message translates to:
  /// **'节点地址'**
  String get addNode_address;

  /// addNode_mcsmAddressHelper
  ///
  /// In zh, this message translates to:
  /// **'MCSManager 面板地址（含端口，如 23333）；远程建议使用 https'**
  String get addNode_mcsmAddressHelper;

  /// addNode_nodeAddressHelper
  ///
  /// In zh, this message translates to:
  /// **'本地节点守护进程地址（默认 12346 端口）'**
  String get addNode_nodeAddressHelper;

  /// addNode_keyTitle
  ///
  /// In zh, this message translates to:
  /// **'节点 Key / API Key'**
  String get addNode_keyTitle;

  /// addNode_mcsmKeyHint
  ///
  /// In zh, this message translates to:
  /// **'MCSManager 用户 API Key'**
  String get addNode_mcsmKeyHint;

  /// addNode_nodeKeyHint
  ///
  /// In zh, this message translates to:
  /// **'本地节点密钥（本机回环可留空）'**
  String get addNode_nodeKeyHint;

  /// addNode_copiedApiKey
  ///
  /// In zh, this message translates to:
  /// **'已复制 API Key'**
  String get addNode_copiedApiKey;

  /// addNode_show
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get addNode_show;

  /// addNode_hide
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get addNode_hide;

  /// addNode_mcsmKeyHelper
  ///
  /// In zh, this message translates to:
  /// **'在 MCSManager 面板「用户信息」中生成并复制'**
  String get addNode_mcsmKeyHelper;

  /// addNode_nodeKeyHelper
  ///
  /// In zh, this message translates to:
  /// **'远程节点必须填写密钥；仅 127.0.0.1 本机回环可留空'**
  String get addNode_nodeKeyHelper;

  /// wizard_title
  ///
  /// In zh, this message translates to:
  /// **'首次配置引导'**
  String get wizard_title;

  /// wizard_detectingNat
  ///
  /// In zh, this message translates to:
  /// **'正在检测 NAT 类型...'**
  String get wizard_detectingNat;

  /// wizard_jdk8Note
  ///
  /// In zh, this message translates to:
  /// **'Minecraft 1.16.5 及更早版本'**
  String get wizard_jdk8Note;

  /// wizard_jdk17Note
  ///
  /// In zh, this message translates to:
  /// **'Minecraft 1.18+ 官方推荐'**
  String get wizard_jdk17Note;

  /// wizard_jdk21Note
  ///
  /// In zh, this message translates to:
  /// **'Minecraft 1.20.5+ 推荐'**
  String get wizard_jdk21Note;

  /// wizard_jdk25Note
  ///
  /// In zh, this message translates to:
  /// **'最新 LTS（新版本服务端）'**
  String get wizard_jdk25Note;

  /// wizard_skipThisStep
  ///
  /// In zh, this message translates to:
  /// **'跳过此步'**
  String get wizard_skipThisStep;

  /// wizard_skipHint
  ///
  /// In zh, this message translates to:
  /// **'提示：可随时点击左上角「跳过」退出引导。'**
  String get wizard_skipHint;

  /// wizard_stepCreateInstance
  ///
  /// In zh, this message translates to:
  /// **'第 5 步 · 创建第一个实例'**
  String get wizard_stepCreateInstance;

  /// wizard_createInstanceDesc
  ///
  /// In zh, this message translates to:
  /// **'下载或导入服务端核心，创建你的第一个 Minecraft 服务器实例。\n完成后将自动检测网络环境（NAT 类型）并给出内网穿透建议。'**
  String get wizard_createInstanceDesc;

  /// wizard_createFirstInstance
  ///
  /// In zh, this message translates to:
  /// **'创建第一个实例'**
  String get wizard_createFirstInstance;

  /// wizard_noInstanceCreated
  ///
  /// In zh, this message translates to:
  /// **'还没有创建实例，请先完成实例创建'**
  String get wizard_noInstanceCreated;

  /// wizard_done
  ///
  /// In zh, this message translates to:
  /// **'引导完成！'**
  String get wizard_done;

  /// wizard_natUncertain
  ///
  /// In zh, this message translates to:
  /// **'（结果不确定）'**
  String get wizard_natUncertain;

  /// wizard_frpNeeded
  ///
  /// In zh, this message translates to:
  /// **'你的网络处于 NAT 之后，好友可能无法直接连接服务器。\n是否需要配置 FRP 内网穿透，让外网玩家可以加入？'**
  String get wizard_frpNeeded;

  /// wizard_frpNotNeeded
  ///
  /// In zh, this message translates to:
  /// **'你的网络为公网直连，玩家可直接通过你的公网 IP 连接，无需内网穿透。'**
  String get wizard_frpNotNeeded;

  /// wizard_configureFrp
  ///
  /// In zh, this message translates to:
  /// **'需要，去配置 FRP'**
  String get wizard_configureFrp;

  /// wizard_notNow
  ///
  /// In zh, this message translates to:
  /// **'暂不需要'**
  String get wizard_notNow;

  /// wizard_adoptiumSource
  ///
  /// In zh, this message translates to:
  /// **'来自 Adoptium（Eclipse Temurin），下载约 200MB'**
  String get wizard_adoptiumSource;

  /// wizard_unknownError
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get wizard_unknownError;

  /// common_skip
  ///
  /// In zh, this message translates to:
  /// **'跳过'**
  String get common_skip;

  /// No description provided for @wizard_totalSteps.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 步，按顺序完成'**
  String wizard_totalSteps(int count);

  /// No description provided for @wizard_installJdk.
  ///
  /// In zh, this message translates to:
  /// **'安装 {name}'**
  String wizard_installJdk(String name);

  /// No description provided for @wizard_stepInstallJdk.
  ///
  /// In zh, this message translates to:
  /// **'第 {step} 步 · 安装 {name}'**
  String wizard_stepInstallJdk(int step, String name);

  /// No description provided for @wizard_startInstall.
  ///
  /// In zh, this message translates to:
  /// **'开始安装 {name}'**
  String wizard_startInstall(String name);

  /// No description provided for @wizard_downloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载 {name} ... {percent}%'**
  String wizard_downloading(String name, String percent);

  /// No description provided for @wizard_jdkInstalled.
  ///
  /// In zh, this message translates to:
  /// **'{name} 已安装'**
  String wizard_jdkInstalled(String name);

  /// No description provided for @wizard_installFailed.
  ///
  /// In zh, this message translates to:
  /// **'安装失败：{error}'**
  String wizard_installFailed(String error);

  /// No description provided for @wizard_natType.
  ///
  /// In zh, this message translates to:
  /// **'NAT 类型：{label}'**
  String wizard_natType(String label);

  /// No description provided for @wizard_natMapped.
  ///
  /// In zh, this message translates to:
  /// **'（{addr}）'**
  String wizard_natMapped(String addr);

  /// No description provided for @wizard_stepNumber.
  ///
  /// In zh, this message translates to:
  /// **'{index}. {title}'**
  String wizard_stepNumber(int index, String title);

  /// ai_stop
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get ai_stop;

  /// ai_clearConversation
  ///
  /// In zh, this message translates to:
  /// **'清空对话'**
  String get ai_clearConversation;

  /// ai_modelMcpSettings
  ///
  /// In zh, this message translates to:
  /// **'模型与 MCP 设置'**
  String get ai_modelMcpSettings;

  /// ai_closePanel
  ///
  /// In zh, this message translates to:
  /// **'关闭 AI 面板'**
  String get ai_closePanel;

  /// ai_addModel
  ///
  /// In zh, this message translates to:
  /// **'添加模型'**
  String get ai_addModel;

  /// ai_startChat
  ///
  /// In zh, this message translates to:
  /// **'开始和 AI 对话吧'**
  String get ai_startChat;

  /// ai_addModelFirst
  ///
  /// In zh, this message translates to:
  /// **'请先添加模型'**
  String get ai_addModelFirst;

  /// ai_emptyHintHasModel
  ///
  /// In zh, this message translates to:
  /// **'可以让 AI 查看日志、分析报错、管理文件'**
  String get ai_emptyHintHasModel;

  /// ai_emptyHintNoModel
  ///
  /// In zh, this message translates to:
  /// **'配置 OpenAI 兼容 API 模型（DeepSeek / OpenAI / Ollama 等）后即可使用'**
  String get ai_emptyHintNoModel;

  /// ai_thinking
  ///
  /// In zh, this message translates to:
  /// **'AI 思考中…'**
  String get ai_thinking;

  /// ai_compressingHistory
  ///
  /// In zh, this message translates to:
  /// **'对话历史较长，正在压缩…'**
  String get ai_compressingHistory;

  /// ai_requestSensitiveOp
  ///
  /// In zh, this message translates to:
  /// **'AI 申请执行敏感操作'**
  String get ai_requestSensitiveOp;

  /// ai_deny
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get ai_deny;

  /// ai_allow
  ///
  /// In zh, this message translates to:
  /// **'允许'**
  String get ai_allow;

  /// ai_viewLog
  ///
  /// In zh, this message translates to:
  /// **'看日志'**
  String get ai_viewLog;

  /// ai_viewLogHint
  ///
  /// In zh, this message translates to:
  /// **'从实例 logs/ 文件夹挑选日志，解析后发送给 AI 分析'**
  String get ai_viewLogHint;

  /// ai_pickLogFileTooltip
  ///
  /// In zh, this message translates to:
  /// **'选择日志文件（.log / .log.gz），解析后发送给 AI'**
  String get ai_pickLogFileTooltip;

  /// ai_askHint
  ///
  /// In zh, this message translates to:
  /// **'向 AI 提问…'**
  String get ai_askHint;

  /// ai_addModelToChat
  ///
  /// In zh, this message translates to:
  /// **'请先添加模型再开始对话'**
  String get ai_addModelToChat;

  /// ai_title
  ///
  /// In zh, this message translates to:
  /// **'AI 助手'**
  String get ai_title;

  /// ai_milvusSaved
  ///
  /// In zh, this message translates to:
  /// **'Milvus 连接已保存'**
  String get ai_milvusSaved;

  /// ai_configMilvusFirst
  ///
  /// In zh, this message translates to:
  /// **'请先在上方配置 Milvus 连接再导入知识库'**
  String get ai_configMilvusFirst;

  /// ai_addModelForEmbedding
  ///
  /// In zh, this message translates to:
  /// **'请先添加 AI 模型，知识库导入需要调用 Embedding 接口'**
  String get ai_addModelForEmbedding;

  /// ai_knowledgeImported
  ///
  /// In zh, this message translates to:
  /// **'知识库导入完成'**
  String get ai_knowledgeImported;

  /// ai_deleteDocumentTitle
  ///
  /// In zh, this message translates to:
  /// **'删除文档'**
  String get ai_deleteDocumentTitle;

  /// ai_settingsTitle
  ///
  /// In zh, this message translates to:
  /// **'AI 设置'**
  String get ai_settingsTitle;

  /// ai_models
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get ai_models;

  /// ai_noModelsYet
  ///
  /// In zh, this message translates to:
  /// **'还没有模型，点击右上角「添加模型」'**
  String get ai_noModelsYet;

  /// ai_knowledgeBase
  ///
  /// In zh, this message translates to:
  /// **'知识库'**
  String get ai_knowledgeBase;

  /// ai_importing
  ///
  /// In zh, this message translates to:
  /// **'导入中…'**
  String get ai_importing;

  /// ai_importDoc
  ///
  /// In zh, this message translates to:
  /// **'导入文档'**
  String get ai_importDoc;

  /// ai_milvusConnection
  ///
  /// In zh, this message translates to:
  /// **'向量库（Milvus）连接'**
  String get ai_milvusConnection;

  /// ai_milvusAddress
  ///
  /// In zh, this message translates to:
  /// **'Milvus 地址'**
  String get ai_milvusAddress;

  /// ai_milvusToken
  ///
  /// In zh, this message translates to:
  /// **'Token（可选）'**
  String get ai_milvusToken;

  /// ai_milvusCollection
  ///
  /// In zh, this message translates to:
  /// **'集合名称'**
  String get ai_milvusCollection;

  /// ai_saving
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get ai_saving;

  /// ai_saveConnection
  ///
  /// In zh, this message translates to:
  /// **'保存连接'**
  String get ai_saveConnection;

  /// ai_milvusNotConfigured
  ///
  /// In zh, this message translates to:
  /// **'尚未配置 Milvus 连接，导入/检索知识库前请先保存'**
  String get ai_milvusNotConfigured;

  /// ai_knowledgeEmpty
  ///
  /// In zh, this message translates to:
  /// **'知识库为空。导入 .txt/.md 文档后，AI 对话时可检索知识库内容。\n（需在模型设置中配置 Embedding 模型，或留空使用同名模型）'**
  String get ai_knowledgeEmpty;

  /// ai_localMcpServer
  ///
  /// In zh, this message translates to:
  /// **'本地 MCP 服务器'**
  String get ai_localMcpServer;

  /// ai_port
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get ai_port;

  /// ai_mcpNotRunning
  ///
  /// In zh, this message translates to:
  /// **'未运行'**
  String get ai_mcpNotRunning;

  /// ai_copyEndpoint
  ///
  /// In zh, this message translates to:
  /// **'复制端点'**
  String get ai_copyEndpoint;

  /// ai_mcpConfigNote
  ///
  /// In zh, this message translates to:
  /// **'在 Claude Desktop / Cursor 等工具中配置（已启用鉴权，token 每次启动随机生成）：'**
  String get ai_mcpConfigNote;

  /// ai_mcpConfigNoteTail
  ///
  /// In zh, this message translates to:
  /// **'点击复制按钮可直接复制完整配置。'**
  String get ai_mcpConfigNoteTail;

  /// ai_selectLogFile
  ///
  /// In zh, this message translates to:
  /// **'选择日志文件（logs/）'**
  String get ai_selectLogFile;

  /// ai_noLogFiles
  ///
  /// In zh, this message translates to:
  /// **'logs/ 文件夹内没有 .log / .log.gz 文件'**
  String get ai_noLogFiles;

  /// ai_send
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get ai_send;

  /// ai_deleteModelTitle
  ///
  /// In zh, this message translates to:
  /// **'删除模型'**
  String get ai_deleteModelTitle;

  /// ai_mcpConfigCopied
  ///
  /// In zh, this message translates to:
  /// **'已复制 MCP 完整配置（含鉴权 token）'**
  String get ai_mcpConfigCopied;

  /// ai_milvusTokenHint
  ///
  /// In zh, this message translates to:
  /// **'未启用鉴权可留空'**
  String get ai_milvusTokenHint;

  /// frp_title
  ///
  /// In zh, this message translates to:
  /// **'FRP 端口映射'**
  String get frp_title;

  /// frp_logoutTitle
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get frp_logoutTitle;

  /// frp_logoutConfirm
  ///
  /// In zh, this message translates to:
  /// **'确定要退出登录吗？'**
  String get frp_logoutConfirm;

  /// frp_logout
  ///
  /// In zh, this message translates to:
  /// **'退出'**
  String get frp_logout;

  /// frp_tunnelCreated
  ///
  /// In zh, this message translates to:
  /// **'隧道创建成功'**
  String get frp_tunnelCreated;

  /// frp_addTunnel
  ///
  /// In zh, this message translates to:
  /// **'添加隧道'**
  String get frp_addTunnel;

  /// frp_openfrpDisclaimer
  ///
  /// In zh, this message translates to:
  /// **'此项目由社区开发，OpenFrp 官方不负责除节点问题以外的技术支持'**
  String get frp_openfrpDisclaimer;

  /// frp_log
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get frp_log;

  /// frp_clearMemoryLog
  ///
  /// In zh, this message translates to:
  /// **'清空内存日志'**
  String get frp_clearMemoryLog;

  /// frp_noLogYet
  ///
  /// In zh, this message translates to:
  /// **'暂无日志\n\n点击左侧隧道卡片可查看对应日志'**
  String get frp_noLogYet;

  /// frp_portMapping
  ///
  /// In zh, this message translates to:
  /// **'端口映射'**
  String get frp_portMapping;

  /// frp_loginPromptCustom
  ///
  /// In zh, this message translates to:
  /// **'配置你的 frps 服务器地址与认证 token，\n隧道保存在本地，一键启动 frpc 实现内网穿透。'**
  String get frp_loginPromptCustom;

  /// frp_loginPromptChml
  ///
  /// In zh, this message translates to:
  /// **'登录 ChmlFrp 账号后可为服务器创建端口映射（隧道），\n并在 IriX 内一键启动 frpc 实现内网穿透。'**
  String get frp_loginPromptChml;

  /// frp_loginPromptOpen
  ///
  /// In zh, this message translates to:
  /// **'登录 OpenFrp 后可为服务器创建端口映射（隧道），\n并在 IriX 内一键启动 frpc 实现内网穿透。'**
  String get frp_loginPromptOpen;

  /// frp_configFrps
  ///
  /// In zh, this message translates to:
  /// **'配置 frps'**
  String get frp_configFrps;

  /// frp_login
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get frp_login;

  /// frp_noAccountRegister
  ///
  /// In zh, this message translates to:
  /// **'还没有账号？去注册'**
  String get frp_noAccountRegister;

  /// frp_traffic
  ///
  /// In zh, this message translates to:
  /// **'剩余流量'**
  String get frp_traffic;

  /// frp_tunnels
  ///
  /// In zh, this message translates to:
  /// **'隧道'**
  String get frp_tunnels;

  /// frp_status
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get frp_status;

  /// frp_noTunnelsYet
  ///
  /// In zh, this message translates to:
  /// **'还没有隧道'**
  String get frp_noTunnelsYet;

  /// frp_addTunnelHint
  ///
  /// In zh, this message translates to:
  /// **'点击右上角「添加隧道」创建端口映射'**
  String get frp_addTunnelHint;

  /// frp_online
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get frp_online;

  /// frp_connecting
  ///
  /// In zh, this message translates to:
  /// **'连接中'**
  String get frp_connecting;

  /// frp_offline
  ///
  /// In zh, this message translates to:
  /// **'离线'**
  String get frp_offline;

  /// frp_start
  ///
  /// In zh, this message translates to:
  /// **'启动'**
  String get frp_start;

  /// frp_stop
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get frp_stop;

  /// frp_encrypt
  ///
  /// In zh, this message translates to:
  /// **'加密'**
  String get frp_encrypt;

  /// frp_compress
  ///
  /// In zh, this message translates to:
  /// **'压缩'**
  String get frp_compress;

  /// frp_disabledLabel
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get frp_disabledLabel;

  /// frp_requestingAuth
  ///
  /// In zh, this message translates to:
  /// **'正在请求授权…'**
  String get frp_requestingAuth;

  /// frp_cannotOpenBrowser
  ///
  /// In zh, this message translates to:
  /// **'无法打开浏览器，请重试'**
  String get frp_cannotOpenBrowser;

  /// frp_authorizedDecrypting
  ///
  /// In zh, this message translates to:
  /// **'已授权，正在解密…'**
  String get frp_authorizedDecrypting;

  /// frp_waitingBrowserAuth
  ///
  /// In zh, this message translates to:
  /// **'等待浏览器授权…'**
  String get frp_waitingBrowserAuth;

  /// frp_authTimeout
  ///
  /// In zh, this message translates to:
  /// **'授权超时，请重试'**
  String get frp_authTimeout;

  /// frp_loginOpenFrpTitle
  ///
  /// In zh, this message translates to:
  /// **'登录 OpenFrp'**
  String get frp_loginOpenFrpTitle;

  /// frp_openfrpAuthDesc
  ///
  /// In zh, this message translates to:
  /// **'点击下方按钮后将在浏览器中打开 OpenFrp 授权页：\n登录并在授权页确认后，IriX 会自动完成登录，无需复制任何内容。\n轮询最长 5 分钟，超时或取消需重新发起。'**
  String get frp_openfrpAuthDesc;

  /// frp_authorizeInBrowser
  ///
  /// In zh, this message translates to:
  /// **'在浏览器中授权'**
  String get frp_authorizeInBrowser;

  /// frp_enterServerAddress
  ///
  /// In zh, this message translates to:
  /// **'请输入服务器地址'**
  String get frp_enterServerAddress;

  /// frp_configSelfHosted
  ///
  /// In zh, this message translates to:
  /// **'配置自建 frps'**
  String get frp_configSelfHosted;

  /// frp_serverAddress
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get frp_serverAddress;

  /// frp_authToken
  ///
  /// In zh, this message translates to:
  /// **'认证 token'**
  String get frp_authToken;

  /// frp_authTokenHint
  ///
  /// In zh, this message translates to:
  /// **'frps 配置中的 auth.token（可留空）'**
  String get frp_authTokenHint;

  /// frp_selfHostedHint
  ///
  /// In zh, this message translates to:
  /// **'隧道将保存在本地，启动时生成 frpc TOML 配置并运行。'**
  String get frp_selfHostedHint;

  /// frp_authCallbackTimeout
  ///
  /// In zh, this message translates to:
  /// **'等待网页授权超时或已取消'**
  String get frp_authCallbackTimeout;

  /// frp_noAccessToken
  ///
  /// In zh, this message translates to:
  /// **'授权回调中未获取到 access_token，请重试'**
  String get frp_noAccessToken;

  /// frp_loginChmlFrpTitle
  ///
  /// In zh, this message translates to:
  /// **'登录 ChmlFrp'**
  String get frp_loginChmlFrpTitle;

  /// frp_chmlfrpAuthDesc
  ///
  /// In zh, this message translates to:
  /// **'点击下方按钮后将在浏览器中打开 ChmlFrp 授权页：\n登录并授权后会自动跳回 IriX，无需复制粘贴任何内容。'**
  String get frp_chmlfrpAuthDesc;

  /// frp_chmlfrpNoRegister
  ///
  /// In zh, this message translates to:
  /// **'IriX 不提供 ChmlFrp 账号注册，请前往官网注册后登录。'**
  String get frp_chmlfrpNoRegister;

  /// frp_loginSakuraFrpTitle
  ///
  /// In zh, this message translates to:
  /// **'登录 SakuraFrp'**
  String get frp_loginSakuraFrpTitle;

  /// frp_accessToken
  ///
  /// In zh, this message translates to:
  /// **'访问密钥 (Access Token)'**
  String get frp_accessToken;

  /// frp_accessTokenHint
  ///
  /// In zh, this message translates to:
  /// **'粘贴 SakuraFrp 访问密钥'**
  String get frp_accessTokenHint;

  /// frp_show
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get frp_show;

  /// frp_hide
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get frp_hide;

  /// frp_sakurafrpTokenHint
  ///
  /// In zh, this message translates to:
  /// **'获取方式：打开 SakuraFrp 控制台 → 账户信息 → 访问密钥，点击复制后粘贴到此处。'**
  String get frp_sakurafrpTokenHint;

  /// frp_loginHayFrpTitle
  ///
  /// In zh, this message translates to:
  /// **'登录 HayFrp'**
  String get frp_loginHayFrpTitle;

  /// frp_usernameOrEmail
  ///
  /// In zh, this message translates to:
  /// **'用户名或邮箱'**
  String get frp_usernameOrEmail;

  /// frp_password
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get frp_password;

  /// frp_hayfrpTokenHint
  ///
  /// In zh, this message translates to:
  /// **'登录获取的 Token 有效期 7 天，每次登录会使上次 Token 失效。'**
  String get frp_hayfrpTokenHint;

  /// frp_tunnelNameRule
  ///
  /// In zh, this message translates to:
  /// **'隧道名称仅支持英文、数字、- 和 _'**
  String get frp_tunnelNameRule;

  /// frp_selectNode
  ///
  /// In zh, this message translates to:
  /// **'请选择节点'**
  String get frp_selectNode;

  /// frp_enterLocalAddr
  ///
  /// In zh, this message translates to:
  /// **'请输入本地地址'**
  String get frp_enterLocalAddr;

  /// frp_localPortRange
  ///
  /// In zh, this message translates to:
  /// **'本地端口需在 1-65535 之间'**
  String get frp_localPortRange;

  /// frp_webNeedsDomain
  ///
  /// In zh, this message translates to:
  /// **'HTTP/HTTPS 隧道需要填写绑定域名'**
  String get frp_webNeedsDomain;

  /// frp_remotePortRange
  ///
  /// In zh, this message translates to:
  /// **'远程端口需在 1-65535 之间'**
  String get frp_remotePortRange;

  /// frp_tunnelName
  ///
  /// In zh, this message translates to:
  /// **'隧道名称'**
  String get frp_tunnelName;

  /// frp_tunnelNameHint
  ///
  /// In zh, this message translates to:
  /// **'例如 my_server（不支持中文）'**
  String get frp_tunnelNameHint;

  /// frp_tunnelType
  ///
  /// In zh, this message translates to:
  /// **'隧道类型'**
  String get frp_tunnelType;

  /// frp_localAddress
  ///
  /// In zh, this message translates to:
  /// **'本地地址'**
  String get frp_localAddress;

  /// frp_selectInstance
  ///
  /// In zh, this message translates to:
  /// **'选择实例'**
  String get frp_selectInstance;

  /// frp_manualInput
  ///
  /// In zh, this message translates to:
  /// **'手动填写'**
  String get frp_manualInput;

  /// frp_localPort
  ///
  /// In zh, this message translates to:
  /// **'本地端口'**
  String get frp_localPort;

  /// frp_localPortExample
  ///
  /// In zh, this message translates to:
  /// **'例如 25565'**
  String get frp_localPortExample;

  /// frp_localPortAuto
  ///
  /// In zh, this message translates to:
  /// **'本地端口（自动读取）'**
  String get frp_localPortAuto;

  /// frp_remotePortHint
  ///
  /// In zh, this message translates to:
  /// **'开放给外部的端口'**
  String get frp_remotePortHint;

  /// frp_bindDomain
  ///
  /// In zh, this message translates to:
  /// **'绑定域名'**
  String get frp_bindDomain;

  /// frp_noAvailableNodes
  ///
  /// In zh, this message translates to:
  /// **'没有可用的节点'**
  String get frp_noAvailableNodes;

  /// frp_node
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get frp_node;

  /// frp_noAvailableInstances
  ///
  /// In zh, this message translates to:
  /// **'没有可用实例（需存在 server.properties 才能自动读取端口）'**
  String get frp_noAvailableInstances;

  /// frp_instanceAutoPort
  ///
  /// In zh, this message translates to:
  /// **'实例（自动读取 server-port）'**
  String get frp_instanceAutoPort;

  /// frp_create
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get frp_create;

  /// frp_cannotOpenRegisterPage
  ///
  /// In zh, this message translates to:
  /// **'无法打开注册页面'**
  String get frp_cannotOpenRegisterPage;

  /// frp_deleteTunnelTitle
  ///
  /// In zh, this message translates to:
  /// **'删除隧道'**
  String get frp_deleteTunnelTitle;

  /// frp_enterAccessToken
  ///
  /// In zh, this message translates to:
  /// **'请输入访问密钥'**
  String get frp_enterAccessToken;

  /// frp_enterUsernamePassword
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名和密码'**
  String get frp_enterUsernamePassword;

  /// No description provided for @ai_logParseFailed.
  ///
  /// In zh, this message translates to:
  /// **'日志解析失败: {e}'**
  String ai_logParseFailed(String e);

  /// No description provided for @ai_compressedHistory.
  ///
  /// In zh, this message translates to:
  /// **'已压缩对话历史：{summary}'**
  String ai_compressedHistory(String summary);

  /// No description provided for @ai_saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败: {e}'**
  String ai_saveFailed(String e);

  /// No description provided for @ai_readFileFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取文件失败: {e}'**
  String ai_readFileFailed(String e);

  /// No description provided for @ai_importFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败: {e}'**
  String ai_importFailed(String e);

  /// No description provided for @ai_deleteDocumentConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定从知识库删除 \"{title}\" 吗？'**
  String ai_deleteDocumentConfirm(String title);

  /// No description provided for @ai_deleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败: {e}'**
  String ai_deleteFailed(String e);

  /// No description provided for @ai_deleteModelConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除模型 \"{name}\" 吗？'**
  String ai_deleteModelConfirm(String name);

  /// No description provided for @ai_mcpStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'MCP 服务器启动失败: {e}'**
  String ai_mcpStartFailed(String e);

  /// No description provided for @ai_modelSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'{baseUrl}\n上下文窗口: {contextWindow} tokens'**
  String ai_modelSubtitle(String baseUrl, int contextWindow);

  /// No description provided for @ai_milvusConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置 Milvus 连接：{uri}'**
  String ai_milvusConfigured(String uri);

  /// No description provided for @ai_docSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'{chunkCount} 个分块 · {createdAt}'**
  String ai_docSubtitle(int chunkCount, String createdAt);

  /// No description provided for @ai_mcpRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中 {endpoint}'**
  String ai_mcpRunning(String endpoint);

  /// No description provided for @frp_loginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败: {e}'**
  String frp_loginFailed(String e);

  /// No description provided for @frp_createFailed.
  ///
  /// In zh, this message translates to:
  /// **'创建失败: {e}'**
  String frp_createFailed(String e);

  /// No description provided for @frp_deleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败: {e}'**
  String frp_deleteFailed(String e);

  /// No description provided for @frp_startFailed.
  ///
  /// In zh, this message translates to:
  /// **'启动失败: {e}'**
  String frp_startFailed(String e);

  /// No description provided for @frp_deleteTunnelConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除隧道 \"{name}\" 吗？'**
  String frp_deleteTunnelConfirm(String name);

  /// No description provided for @frp_deleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {name}'**
  String frp_deleted(String name);

  /// No description provided for @frp_domainLabel.
  ///
  /// In zh, this message translates to:
  /// **'域名: {domain}'**
  String frp_domainLabel(String domain);

  /// No description provided for @frp_remotePort.
  ///
  /// In zh, this message translates to:
  /// **'远程端口 {port}'**
  String frp_remotePort(String port);

  /// No description provided for @frp_localMapping.
  ///
  /// In zh, this message translates to:
  /// **'本地 {localAddr}:{localPort}  →  {remoteText}'**
  String frp_localMapping(String localAddr, int localPort, String remoteText);

  /// No description provided for @frp_connectAddress.
  ///
  /// In zh, this message translates to:
  /// **'连接地址 {address}'**
  String frp_connectAddress(String address);

  /// No description provided for @frp_nodeLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'节点加载失败: {error}'**
  String frp_nodeLoadFailed(String error);

  /// No description provided for @frp_instancePort.
  ///
  /// In zh, this message translates to:
  /// **'{name} · 端口 {port}'**
  String frp_instancePort(String name, int port);

  /// No description provided for @frp_tunnelCount.
  ///
  /// In zh, this message translates to:
  /// **'隧道 ({count})'**
  String frp_tunnelCount(int count);

  /// dbDetail_connectionInfo
  ///
  /// In zh, this message translates to:
  /// **'连接信息'**
  String get dbDetail_connectionInfo;

  /// dbDetail_connected
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get dbDetail_connected;

  /// dbDetail_type
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get dbDetail_type;

  /// dbDetail_address
  ///
  /// In zh, this message translates to:
  /// **'地址'**
  String get dbDetail_address;

  /// dbDetail_user
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get dbDetail_user;

  /// dbDetail_database
  ///
  /// In zh, this message translates to:
  /// **'数据库'**
  String get dbDetail_database;

  /// dbDetail_none
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get dbDetail_none;

  /// dbDetail_testConnection
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get dbDetail_testConnection;

  /// dbDetail_runSql
  ///
  /// In zh, this message translates to:
  /// **'执行 SQL'**
  String get dbDetail_runSql;

  /// dbDetail_userManagement
  ///
  /// In zh, this message translates to:
  /// **'用户管理'**
  String get dbDetail_userManagement;

  /// dbDetail_newUser
  ///
  /// In zh, this message translates to:
  /// **'新建用户'**
  String get dbDetail_newUser;

  /// dbDetail_redisNoUserManagement
  ///
  /// In zh, this message translates to:
  /// **'Redis 不支持用户管理'**
  String get dbDetail_redisNoUserManagement;

  /// dbDetail_noUsers
  ///
  /// In zh, this message translates to:
  /// **'暂无用户'**
  String get dbDetail_noUsers;

  /// dbDetail_view
  ///
  /// In zh, this message translates to:
  /// **'查看'**
  String get dbDetail_view;

  /// dbDetail_noData
  ///
  /// In zh, this message translates to:
  /// **'无数据'**
  String get dbDetail_noData;

  /// dbDetail_databases
  ///
  /// In zh, this message translates to:
  /// **'数据库'**
  String get dbDetail_databases;

  /// dbDetail_newDatabase
  ///
  /// In zh, this message translates to:
  /// **'新建数据库'**
  String get dbDetail_newDatabase;

  /// dbDetail_noDatabases
  ///
  /// In zh, this message translates to:
  /// **'未找到数据库'**
  String get dbDetail_noDatabases;

  /// dbDetail_noTables
  ///
  /// In zh, this message translates to:
  /// **'该数据库没有表'**
  String get dbDetail_noTables;

  /// dbDetail_addRow
  ///
  /// In zh, this message translates to:
  /// **'添加行'**
  String get dbDetail_addRow;

  /// dbDetail_noDataInTable
  ///
  /// In zh, this message translates to:
  /// **'该表没有数据'**
  String get dbDetail_noDataInTable;

  /// dbDetail_noDataInPage
  ///
  /// In zh, this message translates to:
  /// **'当前页无数据'**
  String get dbDetail_noDataInPage;

  /// dbDetail_prevPage
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get dbDetail_prevPage;

  /// dbDetail_nextPage
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get dbDetail_nextPage;

  /// dbDetail_saved
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get dbDetail_saved;

  /// dbDetail_noMatchingRow
  ///
  /// In zh, this message translates to:
  /// **'未找到匹配行，数据未修改'**
  String get dbDetail_noMatchingRow;

  /// dbDetail_rowAdded
  ///
  /// In zh, this message translates to:
  /// **'已添加行'**
  String get dbDetail_rowAdded;

  /// dbDetail_deleteRow
  ///
  /// In zh, this message translates to:
  /// **'删除行'**
  String get dbDetail_deleteRow;

  /// dbDetail_deleteRowConfirm
  ///
  /// In zh, this message translates to:
  /// **'确定要删除这一行吗？此操作不可恢复！'**
  String get dbDetail_deleteRowConfirm;

  /// dbDetail_connectionSuccess
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get dbDetail_connectionSuccess;

  /// dbDetail_dropDatabaseTitle
  ///
  /// In zh, this message translates to:
  /// **'删除数据库'**
  String get dbDetail_dropDatabaseTitle;

  /// dbDetail_dropUserTitle
  ///
  /// In zh, this message translates to:
  /// **'删除用户'**
  String get dbDetail_dropUserTitle;

  /// dbDetail_searchKeyPrefix
  ///
  /// In zh, this message translates to:
  /// **'前缀搜索 Key'**
  String get dbDetail_searchKeyPrefix;

  /// dbDetail_addRedisKey
  ///
  /// In zh, this message translates to:
  /// **'添加 Key'**
  String get dbDetail_addRedisKey;

  /// dbDetail_noMatchingKeys
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的 Key'**
  String get dbDetail_noMatchingKeys;

  /// dbDetail_emptyValue
  ///
  /// In zh, this message translates to:
  /// **'(空)'**
  String get dbDetail_emptyValue;

  /// dbDetail_keyRequired
  ///
  /// In zh, this message translates to:
  /// **'Key 不能为空'**
  String get dbDetail_keyRequired;

  /// dbDetail_keyName
  ///
  /// In zh, this message translates to:
  /// **'Key 名称'**
  String get dbDetail_keyName;

  /// dbDetail_value
  ///
  /// In zh, this message translates to:
  /// **'值'**
  String get dbDetail_value;

  /// dbDetail_usernameRequired
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名'**
  String get dbDetail_usernameRequired;

  /// dbDetail_passwordRequired
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get dbDetail_passwordRequired;

  /// dbDetail_hostRequired
  ///
  /// In zh, this message translates to:
  /// **'请输入登录主机'**
  String get dbDetail_hostRequired;

  /// dbDetail_username
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get dbDetail_username;

  /// dbDetail_password
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get dbDetail_password;

  /// dbDetail_loginHost
  ///
  /// In zh, this message translates to:
  /// **'登录主机'**
  String get dbDetail_loginHost;

  /// dbDetail_loginHostHint
  ///
  /// In zh, this message translates to:
  /// **'例如 % 或 localhost'**
  String get dbDetail_loginHostHint;

  /// dbDetail_create
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get dbDetail_create;

  /// dbDetail_databaseNameRequired
  ///
  /// In zh, this message translates to:
  /// **'请输入数据库名称'**
  String get dbDetail_databaseNameRequired;

  /// dbDetail_databaseName
  ///
  /// In zh, this message translates to:
  /// **'数据库名称'**
  String get dbDetail_databaseName;

  /// dbDetail_databaseNameHintPg
  ///
  /// In zh, this message translates to:
  /// **'小写字母/数字/下划线'**
  String get dbDetail_databaseNameHintPg;

  /// dbDetail_databaseNameHint
  ///
  /// In zh, this message translates to:
  /// **'例如 minecraft'**
  String get dbDetail_databaseNameHint;

  /// dbDetail_databaseAccount
  ///
  /// In zh, this message translates to:
  /// **'数据库专用账号'**
  String get dbDetail_databaseAccount;

  /// dbDetail_autoGenerate
  ///
  /// In zh, this message translates to:
  /// **'自动生成'**
  String get dbDetail_autoGenerate;

  /// dbDetail_custom
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get dbDetail_custom;

  /// dbDetail_regenerate
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get dbDetail_regenerate;

  /// dbDetail_databaseAccountNote
  ///
  /// In zh, this message translates to:
  /// **'将创建独立数据库并授予该账号全部权限'**
  String get dbDetail_databaseAccountNote;

  /// dbDetail_execute
  ///
  /// In zh, this message translates to:
  /// **'执行'**
  String get dbDetail_execute;

  /// dbDetail_selectDatabase
  ///
  /// In zh, this message translates to:
  /// **'选择数据库'**
  String get dbDetail_selectDatabase;

  /// dbDetail_resultShownAfterRun
  ///
  /// In zh, this message translates to:
  /// **'执行后在此显示结果'**
  String get dbDetail_resultShownAfterRun;

  /// dbDetail_queryNoRows
  ///
  /// In zh, this message translates to:
  /// **'查询返回 0 行'**
  String get dbDetail_queryNoRows;

  /// jailDetail_tabRun
  ///
  /// In zh, this message translates to:
  /// **'运行'**
  String get jailDetail_tabRun;

  /// jailDetail_tabFiles
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get jailDetail_tabFiles;

  /// jailDetail_tabConsole
  ///
  /// In zh, this message translates to:
  /// **'控制台'**
  String get jailDetail_tabConsole;

  /// jailDetail_tabPackages
  ///
  /// In zh, this message translates to:
  /// **'软件包'**
  String get jailDetail_tabPackages;

  /// jailDetail_tabMounts
  ///
  /// In zh, this message translates to:
  /// **'挂载'**
  String get jailDetail_tabMounts;

  /// jailDetail_tabSettings
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get jailDetail_tabSettings;

  /// jailDetail_running
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get jailDetail_running;

  /// jailDetail_stopped
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get jailDetail_stopped;

  /// jailDetail_sectionInstanceMount
  ///
  /// In zh, this message translates to:
  /// **'实例挂载（bastille mount）'**
  String get jailDetail_sectionInstanceMount;

  /// jailDetail_selectInstance
  ///
  /// In zh, this message translates to:
  /// **'选择节点实例（自动填充路径与命令）'**
  String get jailDetail_selectInstance;

  /// jailDetail_loadingInstances
  ///
  /// In zh, this message translates to:
  /// **'正在加载实例列表…'**
  String get jailDetail_loadingInstances;

  /// jailDetail_manualFill
  ///
  /// In zh, this message translates to:
  /// **'手动填写（不选择实例）'**
  String get jailDetail_manualFill;

  /// jailDetail_hostPath
  ///
  /// In zh, this message translates to:
  /// **'实例目录（节点上的宿主机路径）'**
  String get jailDetail_hostPath;

  /// jailDetail_hostPathHint
  ///
  /// In zh, this message translates to:
  /// **'如 /usr/local/irix-node/instances/mc-survival'**
  String get jailDetail_hostPathHint;

  /// jailDetail_jailPath
  ///
  /// In zh, this message translates to:
  /// **'Jail 内路径（默认 /data）'**
  String get jailDetail_jailPath;

  /// jailDetail_mounted
  ///
  /// In zh, this message translates to:
  /// **'已挂载'**
  String get jailDetail_mounted;

  /// jailDetail_notMounted
  ///
  /// In zh, this message translates to:
  /// **'未挂载'**
  String get jailDetail_notMounted;

  /// jailDetail_mountButton
  ///
  /// In zh, this message translates to:
  /// **'挂载'**
  String get jailDetail_mountButton;

  /// jailDetail_unmountButton
  ///
  /// In zh, this message translates to:
  /// **'卸载'**
  String get jailDetail_unmountButton;

  /// jailDetail_sectionRunInstance
  ///
  /// In zh, this message translates to:
  /// **'在 Jail 内运行实例（bastille cmd）'**
  String get jailDetail_sectionRunInstance;

  /// jailDetail_startCommand
  ///
  /// In zh, this message translates to:
  /// **'启动命令'**
  String get jailDetail_startCommand;

  /// jailDetail_startCommandHint
  ///
  /// In zh, this message translates to:
  /// **'如 java -Xmx2G -jar server.jar nogui'**
  String get jailDetail_startCommandHint;

  /// jailDetail_workdir
  ///
  /// In zh, this message translates to:
  /// **'运行目录（容器内工作目录，默认 /data）'**
  String get jailDetail_workdir;

  /// jailDetail_watchdog
  ///
  /// In zh, this message translates to:
  /// **'看门狗：进程退出后自动停止 Jail'**
  String get jailDetail_watchdog;

  /// jailDetail_watchdogSubtitle
  ///
  /// In zh, this message translates to:
  /// **'容器内进程（如 MC 服务端）停止运行后，自动执行 bastille stop'**
  String get jailDetail_watchdogSubtitle;

  /// jailDetail_startRun
  ///
  /// In zh, this message translates to:
  /// **'启动运行'**
  String get jailDetail_startRun;

  /// jailDetail_stopProcess
  ///
  /// In zh, this message translates to:
  /// **'停止进程'**
  String get jailDetail_stopProcess;

  /// jailDetail_sessionRunning
  ///
  /// In zh, this message translates to:
  /// **'会话运行中'**
  String get jailDetail_sessionRunning;

  /// jailDetail_sessionEnded
  ///
  /// In zh, this message translates to:
  /// **'会话已结束'**
  String get jailDetail_sessionEnded;

  /// jailDetail_runHint
  ///
  /// In zh, this message translates to:
  /// **'提示：未挂载实例目录时，启动运行会自动挂载（默认 /data）。查看输出 / 发送命令请在下方控制台进行。'**
  String get jailDetail_runHint;

  /// jailDetail_sessionConsole
  ///
  /// In zh, this message translates to:
  /// **'运行会话控制台'**
  String get jailDetail_sessionConsole;

  /// jailDetail_sessionNoOutput
  ///
  /// In zh, this message translates to:
  /// **'（尚未启动运行，输出将显示在这里）'**
  String get jailDetail_sessionNoOutput;

  /// jailDetail_commandInputHint
  ///
  /// In zh, this message translates to:
  /// **'输入命令（如 say hello），回车发送'**
  String get jailDetail_commandInputHint;

  /// jailDetail_jailPathLabel
  ///
  /// In zh, this message translates to:
  /// **'Jail 内路径'**
  String get jailDetail_jailPathLabel;

  /// jailDetail_jailPathHint
  ///
  /// In zh, this message translates to:
  /// **'如 /data 或 /usr/local/bin'**
  String get jailDetail_jailPathHint;

  /// jailDetail_goto
  ///
  /// In zh, this message translates to:
  /// **'跳转'**
  String get jailDetail_goto;

  /// jailDetail_mountPoints
  ///
  /// In zh, this message translates to:
  /// **'挂载点：'**
  String get jailDetail_mountPoints;

  /// jailDetail_upload
  ///
  /// In zh, this message translates to:
  /// **'上传'**
  String get jailDetail_upload;

  /// jailDetail_newFolder
  ///
  /// In zh, this message translates to:
  /// **'新建目录'**
  String get jailDetail_newFolder;

  /// jailDetail_newFile
  ///
  /// In zh, this message translates to:
  /// **'新建文件'**
  String get jailDetail_newFile;

  /// jailDetail_upLevel
  ///
  /// In zh, this message translates to:
  /// **'返回上级'**
  String get jailDetail_upLevel;

  /// jailDetail_download
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get jailDetail_download;

  /// jailDetail_fillHostPath
  ///
  /// In zh, this message translates to:
  /// **'请填写实例目录（节点上的宿主机路径）'**
  String get jailDetail_fillHostPath;

  /// jailDetail_jailNotRunning
  ///
  /// In zh, this message translates to:
  /// **'Jail 未运行，请先在顶部启动 Jail'**
  String get jailDetail_jailNotRunning;

  /// jailDetail_fillStartCommand
  ///
  /// In zh, this message translates to:
  /// **'请填写启动命令（如 java -Xmx2G -jar server.jar nogui）'**
  String get jailDetail_fillStartCommand;

  /// jailDetail_mountInstanceFailed
  ///
  /// In zh, this message translates to:
  /// **'实例目录挂载失败'**
  String get jailDetail_mountInstanceFailed;

  /// jailDetail_noSessionId
  ///
  /// In zh, this message translates to:
  /// **'节点未返回会话 id：可能节点版本过旧，缺少运行会话接口'**
  String get jailDetail_noSessionId;

  /// jailDetail_runStartedWatch
  ///
  /// In zh, this message translates to:
  /// **'已在 Jail 内启动'**
  String get jailDetail_runStartedWatch;

  /// jailDetail_watchdogSuffix
  ///
  /// In zh, this message translates to:
  /// **'（看门狗开启：进程退出后自动停止 Jail）'**
  String get jailDetail_watchdogSuffix;

  /// jailDetail_jailStoppedSuffix
  ///
  /// In zh, this message translates to:
  /// **'，Jail 已停止'**
  String get jailDetail_jailStoppedSuffix;

  /// jailDetail_startFailed
  ///
  /// In zh, this message translates to:
  /// **'启动失败'**
  String get jailDetail_startFailed;

  /// jailDetail_noRunningSession
  ///
  /// In zh, this message translates to:
  /// **'没有运行中的会话'**
  String get jailDetail_noRunningSession;

  /// jailDetail_sendFailed
  ///
  /// In zh, this message translates to:
  /// **'发送失败'**
  String get jailDetail_sendFailed;

  /// jailDetail_noConsoleLog
  ///
  /// In zh, this message translates to:
  /// **'（Jail 未运行，无控制台日志）'**
  String get jailDetail_noConsoleLog;

  /// jailDetail_noOutput
  ///
  /// In zh, this message translates to:
  /// **'（无输出）'**
  String get jailDetail_noOutput;

  /// jailDetail_execFailed
  ///
  /// In zh, this message translates to:
  /// **'执行失败'**
  String get jailDetail_execFailed;

  /// jailDetail_fillPkgName
  ///
  /// In zh, this message translates to:
  /// **'请填写包名（如 openjdk17-jre）'**
  String get jailDetail_fillPkgName;

  /// jailDetail_procMounted
  ///
  /// In zh, this message translates to:
  /// **'/proc 已挂载'**
  String get jailDetail_procMounted;

  /// jailDetail_procfsMounted
  ///
  /// In zh, this message translates to:
  /// **'已挂载 procfs → /proc'**
  String get jailDetail_procfsMounted;

  /// jailDetail_loadFilesFailed
  ///
  /// In zh, this message translates to:
  /// **'加载文件列表失败'**
  String get jailDetail_loadFilesFailed;

  /// jailDetail_folderName
  ///
  /// In zh, this message translates to:
  /// **'目录名称'**
  String get jailDetail_folderName;

  /// jailDetail_fileName
  ///
  /// In zh, this message translates to:
  /// **'文件名称'**
  String get jailDetail_fileName;

  /// jailDetail_uploadFailed
  ///
  /// In zh, this message translates to:
  /// **'上传失败'**
  String get jailDetail_uploadFailed;

  /// jailDetail_saveFile
  ///
  /// In zh, this message translates to:
  /// **'保存文件'**
  String get jailDetail_saveFile;

  /// jailDetail_downloadFailed
  ///
  /// In zh, this message translates to:
  /// **'下载失败'**
  String get jailDetail_downloadFailed;

  /// jailDetail_fileTooLarge
  ///
  /// In zh, this message translates to:
  /// **'文件过大（>2MB），请下载后编辑'**
  String get jailDetail_fileTooLarge;

  /// jailDetail_readFileFailed
  ///
  /// In zh, this message translates to:
  /// **'读取文件失败'**
  String get jailDetail_readFileFailed;

  /// jailDetail_saveFailed
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String get jailDetail_saveFailed;

  /// jailDetail_editText
  ///
  /// In zh, this message translates to:
  /// **'编辑（文本）'**
  String get jailDetail_editText;

  /// jailDetail_downloadLocal
  ///
  /// In zh, this message translates to:
  /// **'下载到本地'**
  String get jailDetail_downloadLocal;

  /// jailDetail_folder
  ///
  /// In zh, this message translates to:
  /// **'目录'**
  String get jailDetail_folder;

  /// jailDetail_file
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get jailDetail_file;

  /// jailDetail_deleteFailed
  ///
  /// In zh, this message translates to:
  /// **'删除失败'**
  String get jailDetail_deleteFailed;

  /// jailDetail_removeConfigContent
  ///
  /// In zh, this message translates to:
  /// **'从 jail.conf 中移除该参数（下次启动生效）。'**
  String get jailDetail_removeConfigContent;

  /// jailDetail_configTitle
  ///
  /// In zh, this message translates to:
  /// **'Jail 配置（bastille config）'**
  String get jailDetail_configTitle;

  /// jailDetail_addConfig
  ///
  /// In zh, this message translates to:
  /// **'添加配置项'**
  String get jailDetail_addConfig;

  /// jailDetail_noConfig
  ///
  /// In zh, this message translates to:
  /// **'暂无配置项，点击「添加配置项」'**
  String get jailDetail_noConfig;

  /// jailDetail_removeConfig
  ///
  /// In zh, this message translates to:
  /// **'删除配置项'**
  String get jailDetail_removeConfig;

  /// jailDetail_consoleHint
  ///
  /// In zh, this message translates to:
  /// **'Jail 系统控制台日志（bastille console 视角）· 下方命令在 jail 内执行（sh 语义）'**
  String get jailDetail_consoleHint;

  /// jailDetail_noLogOutput
  ///
  /// In zh, this message translates to:
  /// **'（暂无日志输出）'**
  String get jailDetail_noLogOutput;

  /// jailDetail_consoleCmdHint
  ///
  /// In zh, this message translates to:
  /// **'jail 内执行命令（如 ls /data、java -version）'**
  String get jailDetail_consoleCmdHint;

  /// jailDetail_runCommand
  ///
  /// In zh, this message translates to:
  /// **'执行命令'**
  String get jailDetail_runCommand;

  /// jailDetail_refreshLog
  ///
  /// In zh, this message translates to:
  /// **'刷新日志'**
  String get jailDetail_refreshLog;

  /// jailDetail_pkgManage
  ///
  /// In zh, this message translates to:
  /// **'软件包管理（bastille pkg）'**
  String get jailDetail_pkgManage;

  /// jailDetail_pkgName
  ///
  /// In zh, this message translates to:
  /// **'包名（逗号 / 空格分隔）'**
  String get jailDetail_pkgName;

  /// jailDetail_pkgNameHint
  ///
  /// In zh, this message translates to:
  /// **'如 openjdk17-jre openjdk21-jre'**
  String get jailDetail_pkgNameHint;

  /// jailDetail_pkgInstall
  ///
  /// In zh, this message translates to:
  /// **'安装（install）'**
  String get jailDetail_pkgInstall;

  /// jailDetail_pkgDelete
  ///
  /// In zh, this message translates to:
  /// **'删除（delete）'**
  String get jailDetail_pkgDelete;

  /// jailDetail_pkgUpdate
  ///
  /// In zh, this message translates to:
  /// **'更新索引（update）'**
  String get jailDetail_pkgUpdate;

  /// jailDetail_pkgUpgrade
  ///
  /// In zh, this message translates to:
  /// **'升级全部（upgrade）'**
  String get jailDetail_pkgUpgrade;

  /// jailDetail_pkgAutoremove
  ///
  /// In zh, this message translates to:
  /// **'清理无用依赖（autoremove）'**
  String get jailDetail_pkgAutoremove;

  /// jailDetail_executing
  ///
  /// In zh, this message translates to:
  /// **'执行中…'**
  String get jailDetail_executing;

  /// jailDetail_execute
  ///
  /// In zh, this message translates to:
  /// **'执行'**
  String get jailDetail_execute;

  /// jailDetail_detectJava
  ///
  /// In zh, this message translates to:
  /// **'检测 Java'**
  String get jailDetail_detectJava;

  /// jailDetail_javaEnv
  ///
  /// In zh, this message translates to:
  /// **'Java 环境'**
  String get jailDetail_javaEnv;

  /// jailDetail_mountProc
  ///
  /// In zh, this message translates to:
  /// **'挂载 /proc（procfs）'**
  String get jailDetail_mountProc;

  /// jailDetail_mountProcSubtitle
  ///
  /// In zh, this message translates to:
  /// **'部分 Java 版本 / JVM 特性（GC 日志等）需要 jail 内有 /proc；仅需执行一次，写入 fstab 后重启自动生效。'**
  String get jailDetail_mountProcSubtitle;

  /// jailDetail_installJava
  ///
  /// In zh, this message translates to:
  /// **'安装 Java 运行环境'**
  String get jailDetail_installJava;

  /// jailDetail_installJavaSubtitle
  ///
  /// In zh, this message translates to:
  /// **'在「操作」选择安装，包名填写 openjdk17-jre 等（见上方快捷包），然后点击「执行」。安装完成后可用「检测 Java」验证。'**
  String get jailDetail_installJavaSubtitle;

  /// jailDetail_mountListTitle
  ///
  /// In zh, this message translates to:
  /// **'挂载列表（bastille mount / fstab）'**
  String get jailDetail_mountListTitle;

  /// jailDetail_noMounts
  ///
  /// In zh, this message translates to:
  /// **'暂无挂载，点击「添加挂载」'**
  String get jailDetail_noMounts;

  /// jailDetail_openDir
  ///
  /// In zh, this message translates to:
  /// **'打开目录（文件 Tab）'**
  String get jailDetail_openDir;

  /// jailDetail_fstabPersist
  ///
  /// In zh, this message translates to:
  /// **'fstab 持久化（重启自动挂载）'**
  String get jailDetail_fstabPersist;

  /// jailDetail_tempMount
  ///
  /// In zh, this message translates to:
  /// **'仅当前挂载（重启后需重新挂载）'**
  String get jailDetail_tempMount;

  /// jailDetail_addMount
  ///
  /// In zh, this message translates to:
  /// **'添加挂载'**
  String get jailDetail_addMount;

  /// jailDetail_fstype
  ///
  /// In zh, this message translates to:
  /// **'文件系统类型'**
  String get jailDetail_fstype;

  /// jailDetail_fstypeNullfs
  ///
  /// In zh, this message translates to:
  /// **'nullfs（宿主机目录）'**
  String get jailDetail_fstypeNullfs;

  /// jailDetail_fstypeProcfs
  ///
  /// In zh, this message translates to:
  /// **'procfs（/proc，Java 需要）'**
  String get jailDetail_fstypeProcfs;

  /// jailDetail_srcPath
  ///
  /// In zh, this message translates to:
  /// **'宿主机源路径'**
  String get jailDetail_srcPath;

  /// jailDetail_dstPath
  ///
  /// In zh, this message translates to:
  /// **'Jail 内目标路径'**
  String get jailDetail_dstPath;

  /// jailDetail_dstPathHint
  ///
  /// In zh, this message translates to:
  /// **'如 /data 或 /proc'**
  String get jailDetail_dstPathHint;

  /// jailDetail_mountOption
  ///
  /// In zh, this message translates to:
  /// **'挂载选项（默认 rw）'**
  String get jailDetail_mountOption;

  /// jailDetail_fstabPersistSubtitle
  ///
  /// In zh, this message translates to:
  /// **'写入 fstab：jail 启动时自动挂载，重启不丢失（推荐）'**
  String get jailDetail_fstabPersistSubtitle;

  /// jailDetail_nullfsHint
  ///
  /// In zh, this message translates to:
  /// **'提示：nullfs 实时挂载需要 jail 运行中；jail 未运行时只能写入 fstab（下次启动生效）。挂载后可在「文件」Tab 查看目录内容。'**
  String get jailDetail_nullfsHint;

  /// jailDetail_unmountTitle
  ///
  /// In zh, this message translates to:
  /// **'卸载挂载'**
  String get jailDetail_unmountTitle;

  /// jailDetail_configKey
  ///
  /// In zh, this message translates to:
  /// **'配置键（如 ip4.addr、hostname）'**
  String get jailDetail_configKey;

  /// jailDetail_configValue
  ///
  /// In zh, this message translates to:
  /// **'配置值'**
  String get jailDetail_configValue;

  /// jailDetail_configValueHint
  ///
  /// In zh, this message translates to:
  /// **'如 192.168.1.51/24、yes'**
  String get jailDetail_configValueHint;

  /// jailDetail_clearOutput
  ///
  /// In zh, this message translates to:
  /// **'清空输出'**
  String get jailDetail_clearOutput;

  /// jailDetail_noRunningSessionInput
  ///
  /// In zh, this message translates to:
  /// **'（无运行中的会话）'**
  String get jailDetail_noRunningSessionInput;

  /// jailDetail_send
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get jailDetail_send;

  /// jailDetail_mountAddedPersist
  ///
  /// In zh, this message translates to:
  /// **'挂载已添加（fstab 持久化，重启自动挂载）'**
  String get jailDetail_mountAddedPersist;

  /// jailDetail_mountAddedTemp
  ///
  /// In zh, this message translates to:
  /// **'挂载已添加（仅当前挂载，重启后需重新挂载）'**
  String get jailDetail_mountAddedTemp;

  /// jailDetail_operationFailed
  ///
  /// In zh, this message translates to:
  /// **'操作失败'**
  String get jailDetail_operationFailed;

  /// jailDetail_stopFailed
  ///
  /// In zh, this message translates to:
  /// **'停止失败'**
  String get jailDetail_stopFailed;

  /// jailDetail_configHintIp4Addr
  ///
  /// In zh, this message translates to:
  /// **'IPv4 地址（如 192.168.1.50/24）'**
  String get jailDetail_configHintIp4Addr;

  /// jailDetail_configHintIp6Addr
  ///
  /// In zh, this message translates to:
  /// **'IPv6 地址'**
  String get jailDetail_configHintIp6Addr;

  /// jailDetail_configHintHostname
  ///
  /// In zh, this message translates to:
  /// **'jail 主机名'**
  String get jailDetail_configHintHostname;

  /// jailDetail_configHintExecStart
  ///
  /// In zh, this message translates to:
  /// **'启动时执行的命令'**
  String get jailDetail_configHintExecStart;

  /// jailDetail_configHintExecStop
  ///
  /// In zh, this message translates to:
  /// **'停止时执行的命令'**
  String get jailDetail_configHintExecStop;

  /// jailDetail_configHintExecConsolelog
  ///
  /// In zh, this message translates to:
  /// **'控制台日志路径'**
  String get jailDetail_configHintExecConsolelog;

  /// jailDetail_configHintAutostart
  ///
  /// In zh, this message translates to:
  /// **'开机自启（yes/no）'**
  String get jailDetail_configHintAutostart;

  /// jailDetail_configHintAllowMount
  ///
  /// In zh, this message translates to:
  /// **'允许 jail 内挂载'**
  String get jailDetail_configHintAllowMount;

  /// jailDetail_configHintAllowMountProcfs
  ///
  /// In zh, this message translates to:
  /// **'允许挂载 procfs'**
  String get jailDetail_configHintAllowMountProcfs;

  /// jailDetail_configHintVnet
  ///
  /// In zh, this message translates to:
  /// **'VNET 网络模式'**
  String get jailDetail_configHintVnet;

  /// jailDetail_configHintInterface
  ///
  /// In zh, this message translates to:
  /// **'网络接口'**
  String get jailDetail_configHintInterface;

  /// jailDetail_configHintSecurelevel
  ///
  /// In zh, this message translates to:
  /// **'安全级别'**
  String get jailDetail_configHintSecurelevel;

  /// No description provided for @dbDetail_title.
  ///
  /// In zh, this message translates to:
  /// **'{name} - 数据库'**
  String dbDetail_title(String name);

  /// No description provided for @dbDetail_databasePrefix.
  ///
  /// In zh, this message translates to:
  /// **'数据库: {name}'**
  String dbDetail_databasePrefix(String name);

  /// No description provided for @dbDetail_tablePrefix.
  ///
  /// In zh, this message translates to:
  /// **'表: {name}'**
  String dbDetail_tablePrefix(String name);

  /// No description provided for @dbDetail_pageInfo.
  ///
  /// In zh, this message translates to:
  /// **'第 {page} / {maxPage} 页 · 共 {totalRows} 行 · 每页 {pageSize} 行'**
  String dbDetail_pageInfo(int page, int maxPage, int totalRows, int pageSize);

  /// No description provided for @dbDetail_saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败: {error}'**
  String dbDetail_saveFailed(String error);

  /// No description provided for @dbDetail_addFailed.
  ///
  /// In zh, this message translates to:
  /// **'添加失败: {error}'**
  String dbDetail_addFailed(String error);

  /// No description provided for @dbDetail_rowsDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {count} 行'**
  String dbDetail_rowsDeleted(int count);

  /// No description provided for @dbDetail_connectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败: {error}'**
  String dbDetail_connectionFailed(String error);

  /// No description provided for @dbDetail_databaseCreated.
  ///
  /// In zh, this message translates to:
  /// **'已创建数据库 {name}'**
  String dbDetail_databaseCreated(String name);

  /// No description provided for @dbDetail_createFailed.
  ///
  /// In zh, this message translates to:
  /// **'创建失败: {error}'**
  String dbDetail_createFailed(String error);

  /// No description provided for @dbDetail_dropDatabaseConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除数据库 {name} 吗？\n此操作不可恢复！'**
  String dbDetail_dropDatabaseConfirm(String name);

  /// No description provided for @dbDetail_databaseDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除数据库 {name}'**
  String dbDetail_databaseDeleted(String name);

  /// No description provided for @dbDetail_deleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败: {error}'**
  String dbDetail_deleteFailed(String error);

  /// No description provided for @dbDetail_redisKeyDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {name}'**
  String dbDetail_redisKeyDeleted(String name);

  /// No description provided for @dbDetail_userCreated.
  ///
  /// In zh, this message translates to:
  /// **'已创建用户 {name}'**
  String dbDetail_userCreated(String name);

  /// No description provided for @dbDetail_dropUserConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除用户 {name} 吗？'**
  String dbDetail_dropUserConfirm(String name);

  /// No description provided for @dbDetail_userDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除用户 {name}'**
  String dbDetail_userDeleted(String name);

  /// No description provided for @dbDetail_affectedRows.
  ///
  /// In zh, this message translates to:
  /// **'受影响行数: {count}'**
  String dbDetail_affectedRows(int count);

  /// No description provided for @jailDetail_releaseOf.
  ///
  /// In zh, this message translates to:
  /// **'发行版 {name}'**
  String jailDetail_releaseOf(String name);

  /// No description provided for @jailDetail_forwardOf.
  ///
  /// In zh, this message translates to:
  /// **'转发 {ports}'**
  String jailDetail_forwardOf(String ports);

  /// No description provided for @jailDetail_pathEmpty.
  ///
  /// In zh, this message translates to:
  /// **'{path} 为空\n挂载实例目录后，文件会出现在这里'**
  String jailDetail_pathEmpty(String path);

  /// No description provided for @jailDetail_mountedPersist.
  ///
  /// In zh, this message translates to:
  /// **'已挂载 {src} → {dst}（fstab 持久化，重启不丢失）'**
  String jailDetail_mountedPersist(String src, String dst);

  /// No description provided for @jailDetail_unmounted.
  ///
  /// In zh, this message translates to:
  /// **'已卸载 {path}'**
  String jailDetail_unmounted(String path);

  /// No description provided for @jailDetail_processExited.
  ///
  /// In zh, this message translates to:
  /// **'容器内进程已退出（exit {code}）'**
  String jailDetail_processExited(String code);

  /// No description provided for @jailDetail_execFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'执行失败：{error}'**
  String jailDetail_execFailedDetail(String error);

  /// No description provided for @jailDetail_detectFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'检测失败：{error}'**
  String jailDetail_detectFailedDetail(String error);

  /// No description provided for @jailDetail_locatedAt.
  ///
  /// In zh, this message translates to:
  /// **'位于 {path}'**
  String jailDetail_locatedAt(String path);

  /// No description provided for @jailDetail_selectUpload.
  ///
  /// In zh, this message translates to:
  /// **'选择要上传到 {path} 的文件'**
  String jailDetail_selectUpload(String path);

  /// No description provided for @jailDetail_uploadedFiles.
  ///
  /// In zh, this message translates to:
  /// **'已上传 {count} 个文件到 {path}'**
  String jailDetail_uploadedFiles(int count, String path);

  /// No description provided for @jailDetail_downloadedTo.
  ///
  /// In zh, this message translates to:
  /// **'已下载到 {path}'**
  String jailDetail_downloadedTo(String path);

  /// No description provided for @jailDetail_editFile.
  ///
  /// In zh, this message translates to:
  /// **'编辑 {name}'**
  String jailDetail_editFile(String name);

  /// No description provided for @jailDetail_savedFile.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {name}'**
  String jailDetail_savedFile(String name);

  /// No description provided for @jailDetail_deleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除{type}？'**
  String jailDetail_deleteConfirm(String type);

  /// No description provided for @jailDetail_deletePathConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除 {path} 吗？\n{dir}'**
  String jailDetail_deletePathConfirm(String path, bool dir);

  /// No description provided for @jailDetail_deletedPath.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {path}'**
  String jailDetail_deletedPath(String path);

  /// No description provided for @jailDetail_configSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {key}'**
  String jailDetail_configSaved(String key);

  /// No description provided for @jailDetail_removeConfigTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除配置项 {key}？'**
  String jailDetail_removeConfigTitle(String key);

  /// No description provided for @jailDetail_configRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已删除 {key}'**
  String jailDetail_configRemoved(String key);

  /// No description provided for @jailDetail_configAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加 {key}'**
  String jailDetail_configAdded(String key);

  /// No description provided for @jailDetail_optionOf.
  ///
  /// In zh, this message translates to:
  /// **'选项 {options}'**
  String jailDetail_optionOf(String options);

  /// No description provided for @jailDetail_unmountConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定卸载 {display} 吗？\n（fstab 条目也会一并移除）'**
  String jailDetail_unmountConfirm(String display);

  /// nbt_title
  ///
  /// In zh, this message translates to:
  /// **'NBT 编辑器'**
  String get nbt_title;

  /// nbt_importNbt
  ///
  /// In zh, this message translates to:
  /// **'导入 .nbt'**
  String get nbt_importNbt;

  /// nbt_pasteSnbt
  ///
  /// In zh, this message translates to:
  /// **'粘贴 SNBT'**
  String get nbt_pasteSnbt;

  /// nbt_exportNbt
  ///
  /// In zh, this message translates to:
  /// **'导出 .nbt'**
  String get nbt_exportNbt;

  /// nbt_exportViewSnbt
  ///
  /// In zh, this message translates to:
  /// **'导出/查看 SNBT'**
  String get nbt_exportViewSnbt;

  /// nbt_domainTree
  ///
  /// In zh, this message translates to:
  /// **'通用树'**
  String get nbt_domainTree;

  /// nbt_domainItem
  ///
  /// In zh, this message translates to:
  /// **'物品'**
  String get nbt_domainItem;

  /// nbt_domainEntity
  ///
  /// In zh, this message translates to:
  /// **'实体'**
  String get nbt_domainEntity;

  /// nbt_domainVillager
  ///
  /// In zh, this message translates to:
  /// **'村民交易'**
  String get nbt_domainVillager;

  /// nbt_domainRcon
  ///
  /// In zh, this message translates to:
  /// **'连服务器'**
  String get nbt_domainRcon;

  /// nbt_mode
  ///
  /// In zh, this message translates to:
  /// **'模式'**
  String get nbt_mode;

  /// nbt_advancedTree
  ///
  /// In zh, this message translates to:
  /// **'高级树'**
  String get nbt_advancedTree;

  /// nbt_simpleMode
  ///
  /// In zh, this message translates to:
  /// **'简易模式'**
  String get nbt_simpleMode;

  /// nbt_treeOnlyAdvanced
  ///
  /// In zh, this message translates to:
  /// **'通用树模式仅提供高级树编辑。'**
  String get nbt_treeOnlyAdvanced;

  /// nbt_searchPath
  ///
  /// In zh, this message translates to:
  /// **'搜索路径…'**
  String get nbt_searchPath;

  /// nbt_root
  ///
  /// In zh, this message translates to:
  /// **'(root)'**
  String get nbt_root;

  /// nbt_emptyList
  ///
  /// In zh, this message translates to:
  /// **'(空列表)'**
  String get nbt_emptyList;

  /// nbt_emptyCompound
  ///
  /// In zh, this message translates to:
  /// **'(空 Compound)'**
  String get nbt_emptyCompound;

  /// nbt_editValue
  ///
  /// In zh, this message translates to:
  /// **'编辑值'**
  String get nbt_editValue;

  /// nbt_addChild
  ///
  /// In zh, this message translates to:
  /// **'添加子节点'**
  String get nbt_addChild;

  /// nbt_type
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get nbt_type;

  /// nbt_keyName
  ///
  /// In zh, this message translates to:
  /// **'键名'**
  String get nbt_keyName;

  /// nbt_rootUndeletable
  ///
  /// In zh, this message translates to:
  /// **'根节点不可删除'**
  String get nbt_rootUndeletable;

  /// nbt_loadFailed
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get nbt_loadFailed;

  /// nbt_snbtParsed
  ///
  /// In zh, this message translates to:
  /// **'已解析 SNBT'**
  String get nbt_snbtParsed;

  /// nbt_currentSnbt
  ///
  /// In zh, this message translates to:
  /// **'当前 SNBT'**
  String get nbt_currentSnbt;

  /// nbt_rconPlaceholder
  ///
  /// In zh, this message translates to:
  /// **'连服务器（RCON）面板将在阶段 3 接入：\n在此输入 host/port/password 连接开启了 RCON 的服务器，\n并把当前编辑的 NBT 经 /give、/data merge 等命令下发。'**
  String get nbt_rconPlaceholder;

  /// nbt_itemId
  ///
  /// In zh, this message translates to:
  /// **'物品 ID'**
  String get nbt_itemId;

  /// nbt_itemCount
  ///
  /// In zh, this message translates to:
  /// **'数量 Count'**
  String get nbt_itemCount;

  /// nbt_itemCustomName
  ///
  /// In zh, this message translates to:
  /// **'自定义名称 custom_name'**
  String get nbt_itemCustomName;

  /// nbt_itemLore
  ///
  /// In zh, this message translates to:
  /// **'Lore（逗号分隔）'**
  String get nbt_itemLore;

  /// nbt_itemUnbreakable
  ///
  /// In zh, this message translates to:
  /// **'是否损坏 Unbreakable'**
  String get nbt_itemUnbreakable;

  /// nbt_itemFireResistant
  ///
  /// In zh, this message translates to:
  /// **'防火 Fire-resistant'**
  String get nbt_itemFireResistant;

  /// nbt_itemEnchantments
  ///
  /// In zh, this message translates to:
  /// **'附魔（JSON 数组）'**
  String get nbt_itemEnchantments;

  /// nbt_itemDamage
  ///
  /// In zh, this message translates to:
  /// **'伤害值 damage'**
  String get nbt_itemDamage;

  /// nbt_entityCustomName
  ///
  /// In zh, this message translates to:
  /// **'自定义名称 CustomName'**
  String get nbt_entityCustomName;

  /// nbt_entityHealth
  ///
  /// In zh, this message translates to:
  /// **'生命值 Health'**
  String get nbt_entityHealth;

  /// nbt_entitySilent
  ///
  /// In zh, this message translates to:
  /// **'静音 Silent'**
  String get nbt_entitySilent;

  /// nbt_entityGlowing
  ///
  /// In zh, this message translates to:
  /// **'发光 Glowing'**
  String get nbt_entityGlowing;

  /// nbt_entityNoGravity
  ///
  /// In zh, this message translates to:
  /// **'无重力 NoGravity'**
  String get nbt_entityNoGravity;

  /// nbt_entityInvulnerable
  ///
  /// In zh, this message translates to:
  /// **'无敌 Invulnerable'**
  String get nbt_entityInvulnerable;

  /// nbt_entityPoiCounted
  ///
  /// In zh, this message translates to:
  /// **'已捕获 Poicounted'**
  String get nbt_entityPoiCounted;

  /// nbt_villagerProfession
  ///
  /// In zh, this message translates to:
  /// **'职业 profession'**
  String get nbt_villagerProfession;

  /// nbt_villagerLevel
  ///
  /// In zh, this message translates to:
  /// **'等级 level（经验）'**
  String get nbt_villagerLevel;

  /// nbt_villagerType
  ///
  /// In zh, this message translates to:
  /// **'村民类型 type'**
  String get nbt_villagerType;

  /// nbt_villagerOffers
  ///
  /// In zh, this message translates to:
  /// **'交易数量 Offers（JSON）'**
  String get nbt_villagerOffers;

  /// configEditor_noConfigFiles
  ///
  /// In zh, this message translates to:
  /// **'该目录中暂无配置文件'**
  String get configEditor_noConfigFiles;

  /// configEditor_configGeneratedAfterStart
  ///
  /// In zh, this message translates to:
  /// **'启动服务器后会生成配置文件'**
  String get configEditor_configGeneratedAfterStart;

  /// configEditor_configFiles
  ///
  /// In zh, this message translates to:
  /// **'配置文件'**
  String get configEditor_configFiles;

  /// configEditor_importCsv
  ///
  /// In zh, this message translates to:
  /// **'导入CSV注释'**
  String get configEditor_importCsv;

  /// configEditor_undo
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get configEditor_undo;

  /// configEditor_searchHint
  ///
  /// In zh, this message translates to:
  /// **'搜索配置项（中英文均可）'**
  String get configEditor_searchHint;

  /// configEditor_unsavedChanges
  ///
  /// In zh, this message translates to:
  /// **'未保存的修改'**
  String get configEditor_unsavedChanges;

  /// configEditor_discardConfirm
  ///
  /// In zh, this message translates to:
  /// **'当前文件有未保存的修改，是否丢弃？'**
  String get configEditor_discardConfirm;

  /// configEditor_discard
  ///
  /// In zh, this message translates to:
  /// **'丢弃'**
  String get configEditor_discard;

  /// configEditor_parseFailedTextMode
  ///
  /// In zh, this message translates to:
  /// **'解析失败，已切换到文本模式'**
  String get configEditor_parseFailedTextMode;

  /// configEditor_emptyOrUnparseable
  ///
  /// In zh, this message translates to:
  /// **'该文件为空或无法解析为表单，请切换到文本模式编辑'**
  String get configEditor_emptyOrUnparseable;

  /// remoteTab_selectJarToUpload
  ///
  /// In zh, this message translates to:
  /// **'选择要上传的 .jar 文件'**
  String get remoteTab_selectJarToUpload;

  /// remoteTab_saveFile
  ///
  /// In zh, this message translates to:
  /// **'保存文件'**
  String get remoteTab_saveFile;

  /// remoteTab_deleteFileHint
  ///
  /// In zh, this message translates to:
  /// **'将从节点实例中删除该文件。'**
  String get remoteTab_deleteFileHint;

  /// remoteTab_deleteZipHint
  ///
  /// In zh, this message translates to:
  /// **'将从节点实例中删除该压缩包。'**
  String get remoteTab_deleteZipHint;

  /// remoteTab_plugins
  ///
  /// In zh, this message translates to:
  /// **'插件（plugins/）'**
  String get remoteTab_plugins;

  /// remoteTab_mods
  ///
  /// In zh, this message translates to:
  /// **'Mod（mods/）'**
  String get remoteTab_mods;

  /// remoteTab_metaDetectionHint
  ///
  /// In zh, this message translates to:
  /// **'已从 jar 元数据检测（plugin.yml / fabric.mod.json 等）。上传的 .jar 会直接写入节点实例对应目录。'**
  String get remoteTab_metaDetectionHint;

  /// remoteTab_fileListHint
  ///
  /// In zh, this message translates to:
  /// **'节点未提供插件元数据（版本过旧？），仅显示文件列表。上传的 .jar 会直接写入节点实例对应目录（mods 支持版本子目录，此处统一列出）。'**
  String get remoteTab_fileListHint;

  /// remoteTab_uploadJar
  ///
  /// In zh, this message translates to:
  /// **'上传 .jar'**
  String get remoteTab_uploadJar;

  /// remoteTab_emptyNoDetection
  ///
  /// In zh, this message translates to:
  /// **'（空）未检测到插件/Mod'**
  String get remoteTab_emptyNoDetection;

  /// remoteTab_download
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get remoteTab_download;

  /// remoteTab_delete
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get remoteTab_delete;

  /// remoteTab_empty
  ///
  /// In zh, this message translates to:
  /// **'（空）'**
  String get remoteTab_empty;

  /// remoteTab_selectRestoreZip
  ///
  /// In zh, this message translates to:
  /// **'选择要恢复的备份 (.zip)'**
  String get remoteTab_selectRestoreZip;

  /// remoteTab_restoreBackupTitle
  ///
  /// In zh, this message translates to:
  /// **'恢复备份？'**
  String get remoteTab_restoreBackupTitle;

  /// remoteTab_restoreBackupContent
  ///
  /// In zh, this message translates to:
  /// **'将把压缩包上传到实例根目录并解压，同名文件会被覆盖。建议先停止实例再恢复。'**
  String get remoteTab_restoreBackupContent;

  /// remoteTab_restore
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get remoteTab_restore;

  /// remoteTab_statusCreatingSnapshot
  ///
  /// In zh, this message translates to:
  /// **'创建快照中…'**
  String get remoteTab_statusCreatingSnapshot;

  /// remoteTab_restoreSnapshotTitle
  ///
  /// In zh, this message translates to:
  /// **'恢复快照？'**
  String get remoteTab_restoreSnapshotTitle;

  /// remoteTab_statusRestoringSnapshot
  ///
  /// In zh, this message translates to:
  /// **'恢复快照中…'**
  String get remoteTab_statusRestoringSnapshot;

  /// remoteTab_saveSnapshot
  ///
  /// In zh, this message translates to:
  /// **'保存快照'**
  String get remoteTab_saveSnapshot;

  /// remoteTab_statusDownloadingSnapshot
  ///
  /// In zh, this message translates to:
  /// **'下载快照中…'**
  String get remoteTab_statusDownloadingSnapshot;

  /// remoteTab_deleteSnapshotHint
  ///
  /// In zh, this message translates to:
  /// **'将从节点快照区永久删除，不可恢复。'**
  String get remoteTab_deleteSnapshotHint;

  /// remoteTab_instanceBackup
  ///
  /// In zh, this message translates to:
  /// **'实例备份'**
  String get remoteTab_instanceBackup;

  /// remoteTab_instanceBackupDesc
  ///
  /// In zh, this message translates to:
  /// **'备份在节点端压缩整个实例目录后下载到本地；恢复会覆盖同名文件，建议先停止实例。'**
  String get remoteTab_instanceBackupDesc;

  /// remoteTab_startBackup
  ///
  /// In zh, this message translates to:
  /// **'开始备份'**
  String get remoteTab_startBackup;

  /// remoteTab_restoreBackup
  ///
  /// In zh, this message translates to:
  /// **'恢复备份'**
  String get remoteTab_restoreBackup;

  /// remoteTab_statusProcessing
  ///
  /// In zh, this message translates to:
  /// **'处理中…'**
  String get remoteTab_statusProcessing;

  /// remoteTab_nodeSnapshot
  ///
  /// In zh, this message translates to:
  /// **'节点端快照'**
  String get remoteTab_nodeSnapshot;

  /// No description provided for @remoteTab_nodeSnapshotDesc.
  ///
  /// In zh, this message translates to:
  /// **'快照由节点在 {data}/backups/<实例> 保管，恢复会先停止实例再覆盖。'**
  String remoteTab_nodeSnapshotDesc(String data);

  /// remoteTab_createSnapshot
  ///
  /// In zh, this message translates to:
  /// **'创建快照'**
  String get remoteTab_createSnapshot;

  /// remoteTab_noSnapshots
  ///
  /// In zh, this message translates to:
  /// **'（暂无快照）'**
  String get remoteTab_noSnapshots;

  /// remoteTab_nodeBackupFiles
  ///
  /// In zh, this message translates to:
  /// **'节点端备份文件'**
  String get remoteTab_nodeBackupFiles;

  /// remoteTab_noZipBackups
  ///
  /// In zh, this message translates to:
  /// **'（暂无 .zip 备份文件）'**
  String get remoteTab_noZipBackups;

  /// remoteTab_backupRestored
  ///
  /// In zh, this message translates to:
  /// **'备份已恢复'**
  String get remoteTab_backupRestored;

  /// No description provided for @nbt_searchResults.
  ///
  /// In zh, this message translates to:
  /// **'搜索结果（{count}）'**
  String nbt_searchResults(int count);

  /// No description provided for @nbt_imported.
  ///
  /// In zh, this message translates to:
  /// **'已导入 {name}'**
  String nbt_imported(String name);

  /// No description provided for @nbt_importFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败'**
  String nbt_importFailed(String e);

  /// No description provided for @nbt_parseFailed.
  ///
  /// In zh, this message translates to:
  /// **'解析失败'**
  String nbt_parseFailed(String e);

  /// No description provided for @nbt_exported.
  ///
  /// In zh, this message translates to:
  /// **'已导出 {path}'**
  String nbt_exported(String path);

  /// No description provided for @nbt_exportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败'**
  String nbt_exportFailed(String e);

  /// No description provided for @nbt_generateSnbtFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成 SNBT 失败'**
  String nbt_generateSnbtFailed(String e);

  /// No description provided for @nbt_searchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败'**
  String nbt_searchFailed(String e);

  /// No description provided for @nbt_editValueTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑值（{type}）'**
  String nbt_editValueTitle(String type);

  /// No description provided for @configEditor_saved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {name}'**
  String configEditor_saved(String name);

  /// No description provided for @configEditor_saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String configEditor_saveFailed(String e);

  /// No description provided for @configEditor_importedAnnotations.
  ///
  /// In zh, this message translates to:
  /// **'已导入 {count} 条注释'**
  String configEditor_importedAnnotations(int count);

  /// No description provided for @configEditor_importFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败'**
  String configEditor_importFailed(String e);

  /// No description provided for @configEditor_noMatch.
  ///
  /// In zh, this message translates to:
  /// **'未找到匹配「{query}」的配置项'**
  String configEditor_noMatch(String query);

  /// No description provided for @remoteTab_downloadedTo.
  ///
  /// In zh, this message translates to:
  /// **'已下载到 {path}'**
  String remoteTab_downloadedTo(String path);

  /// No description provided for @remoteTab_deleteJar.
  ///
  /// In zh, this message translates to:
  /// **'删除 {name}？'**
  String remoteTab_deleteJar(String name);

  /// No description provided for @remoteTab_statusDownloadingEntry.
  ///
  /// In zh, this message translates to:
  /// **'下载 {name}…'**
  String remoteTab_statusDownloadingEntry(String name);

  /// No description provided for @remoteTab_deleteZip.
  ///
  /// In zh, this message translates to:
  /// **'删除 {name}？'**
  String remoteTab_deleteZip(String name);

  /// No description provided for @remoteTab_restoreSnapshotContent.
  ///
  /// In zh, this message translates to:
  /// **'将停止实例并解压覆盖「{name}」到实例目录，恢复后实例保持停止。'**
  String remoteTab_restoreSnapshotContent(String name);

  /// No description provided for @remoteTab_deleteSnapshot.
  ///
  /// In zh, this message translates to:
  /// **'删除快照 {name}？'**
  String remoteTab_deleteSnapshot(String name);

  /// home_mcpRequestTitle
  ///
  /// In zh, this message translates to:
  /// **'AI 申请执行敏感操作'**
  String get home_mcpRequestTitle;

  /// home_mcpDeny
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get home_mcpDeny;

  /// home_mcpAllow
  ///
  /// In zh, this message translates to:
  /// **'允许'**
  String get home_mcpAllow;

  /// home_navInstances
  ///
  /// In zh, this message translates to:
  /// **'实例'**
  String get home_navInstances;

  /// home_navNodes
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get home_navNodes;

  /// home_navMarket
  ///
  /// In zh, this message translates to:
  /// **'市场'**
  String get home_navMarket;

  /// home_navDatabase
  ///
  /// In zh, this message translates to:
  /// **'数据库'**
  String get home_navDatabase;

  /// home_navAi
  ///
  /// In zh, this message translates to:
  /// **'AI'**
  String get home_navAi;

  /// home_navFrp
  ///
  /// In zh, this message translates to:
  /// **'FRP'**
  String get home_navFrp;

  /// home_navHome
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get home_navHome;

  /// home_navContainers
  ///
  /// In zh, this message translates to:
  /// **'容器'**
  String get home_navContainers;

  /// home_navOrchestration
  ///
  /// In zh, this message translates to:
  /// **'编排'**
  String get home_navOrchestration;

  /// home_newInstance
  ///
  /// In zh, this message translates to:
  /// **'新建实例'**
  String get home_newInstance;

  /// home_nbtEditor
  ///
  /// In zh, this message translates to:
  /// **'NBT 编辑器'**
  String get home_nbtEditor;

  /// common_settings
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get common_settings;

  /// instanceDetail_title
  ///
  /// In zh, this message translates to:
  /// **'实例详情'**
  String get instanceDetail_title;

  /// instanceDetail_notFound
  ///
  /// In zh, this message translates to:
  /// **'实例不存在'**
  String get instanceDetail_notFound;

  /// instanceDetail_adoptedTooltip
  ///
  /// In zh, this message translates to:
  /// **'该进程由上次启动的 IriX 遗留，已接管其日志；stdin 已断开，无法发送指令，仅可强制停止'**
  String get instanceDetail_adoptedTooltip;

  /// instanceDetail_adopted
  ///
  /// In zh, this message translates to:
  /// **'已接管'**
  String get instanceDetail_adopted;

  /// instanceDetail_closeAi
  ///
  /// In zh, this message translates to:
  /// **'关闭 AI 助手'**
  String get instanceDetail_closeAi;

  /// instanceDetail_openAi
  ///
  /// In zh, this message translates to:
  /// **'打开 AI 助手'**
  String get instanceDetail_openAi;

  /// instanceDetail_tabOverview
  ///
  /// In zh, this message translates to:
  /// **'总览'**
  String get instanceDetail_tabOverview;

  /// instanceDetail_tabConfig
  ///
  /// In zh, this message translates to:
  /// **'配置'**
  String get instanceDetail_tabConfig;

  /// instanceDetail_tabPlugins
  ///
  /// In zh, this message translates to:
  /// **'插件/Mod'**
  String get instanceDetail_tabPlugins;

  /// instanceDetail_tabFiles
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get instanceDetail_tabFiles;

  /// instanceDetail_tabBackup
  ///
  /// In zh, this message translates to:
  /// **'备份'**
  String get instanceDetail_tabBackup;

  /// instanceDetail_tabSettings
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get instanceDetail_tabSettings;

  /// instanceDetail_commandHintAdopted
  ///
  /// In zh, this message translates to:
  /// **'已接管的进程无法发送指令（请使用强制停止）'**
  String get instanceDetail_commandHintAdopted;

  /// instanceDetail_commandHint
  ///
  /// In zh, this message translates to:
  /// **'输入服务器指令（无需 /）后按回车'**
  String get instanceDetail_commandHint;

  /// instanceDetail_control
  ///
  /// In zh, this message translates to:
  /// **'控制'**
  String get instanceDetail_control;

  /// instanceDetail_start
  ///
  /// In zh, this message translates to:
  /// **'启动'**
  String get instanceDetail_start;

  /// instanceDetail_restart
  ///
  /// In zh, this message translates to:
  /// **'重启'**
  String get instanceDetail_restart;

  /// instanceDetail_stop
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get instanceDetail_stop;

  /// instanceDetail_forceStop
  ///
  /// In zh, this message translates to:
  /// **'强制停止'**
  String get instanceDetail_forceStop;

  /// instanceDetail_currentStatus
  ///
  /// In zh, this message translates to:
  /// **'当前状态'**
  String get instanceDetail_currentStatus;

  /// instanceDetail_adoptedStatusNote
  ///
  /// In zh, this message translates to:
  /// **'该进程由上次启动的 IriX 遗留，已接管其日志；stdin 已断开，无法发送指令。'**
  String get instanceDetail_adoptedStatusNote;

  /// instanceDetail_selectAtLeastOne
  ///
  /// In zh, this message translates to:
  /// **'请至少选择一个文件或文件夹'**
  String get instanceDetail_selectAtLeastOne;

  /// instanceDetail_backupCancelled
  ///
  /// In zh, this message translates to:
  /// **'备份已取消'**
  String get instanceDetail_backupCancelled;

  /// instanceDetail_selectAll
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get instanceDetail_selectAll;

  /// instanceDetail_emptyRoot
  ///
  /// In zh, this message translates to:
  /// **'根目录为空'**
  String get instanceDetail_emptyRoot;

  /// instanceDetail_folder
  ///
  /// In zh, this message translates to:
  /// **'文件夹'**
  String get instanceDetail_folder;

  /// instanceDetail_file
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get instanceDetail_file;

  /// instanceDetail_startBackup
  ///
  /// In zh, this message translates to:
  /// **'开始备份'**
  String get instanceDetail_startBackup;

  /// instanceDetail_backingUp
  ///
  /// In zh, this message translates to:
  /// **'正在备份...'**
  String get instanceDetail_backingUp;

  /// instanceDetail_maxMemory
  ///
  /// In zh, this message translates to:
  /// **'最大内存'**
  String get instanceDetail_maxMemory;

  /// instanceDetail_notSet
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get instanceDetail_notSet;

  /// instanceDetail_noXmxHint
  ///
  /// In zh, this message translates to:
  /// **'当前启动命令未指定 -Xmx，拖动滑块以设置内存'**
  String get instanceDetail_noXmxHint;

  /// instanceDetail_startCommand
  ///
  /// In zh, this message translates to:
  /// **'启动命令'**
  String get instanceDetail_startCommand;

  /// instanceDetail_startCommandHelper
  ///
  /// In zh, this message translates to:
  /// **'如：java -Xmx2G -jar paper.jar nogui'**
  String get instanceDetail_startCommandHelper;

  /// instanceDetail_deleteInstance
  ///
  /// In zh, this message translates to:
  /// **'删除实例'**
  String get instanceDetail_deleteInstance;

  /// instanceDetail_stopBeforeSwitch
  ///
  /// In zh, this message translates to:
  /// **'请先停止服务器再切换运行方式'**
  String get instanceDetail_stopBeforeSwitch;

  /// instanceDetail_runMode
  ///
  /// In zh, this message translates to:
  /// **'运行方式'**
  String get instanceDetail_runMode;

  /// instanceDetail_nativeProcess
  ///
  /// In zh, this message translates to:
  /// **'原生进程'**
  String get instanceDetail_nativeProcess;

  /// instanceDetail_nativeProcessDesc
  ///
  /// In zh, this message translates to:
  /// **'直接以 java 进程运行（默认）'**
  String get instanceDetail_nativeProcessDesc;

  /// instanceDetail_dockerContainer
  ///
  /// In zh, this message translates to:
  /// **'Docker 容器'**
  String get instanceDetail_dockerContainer;

  /// instanceDetail_dockerDesc
  ///
  /// In zh, this message translates to:
  /// **'服务器运行在 Docker 容器中，启停/控制台/文件走容器'**
  String get instanceDetail_dockerDesc;

  /// instanceDetail_dockerNotFound
  ///
  /// In zh, this message translates to:
  /// **'未检测到 Docker CLI，请先安装并启动 Docker Desktop'**
  String get instanceDetail_dockerNotFound;

  /// instanceDetail_unavailable
  ///
  /// In zh, this message translates to:
  /// **'不可用'**
  String get instanceDetail_unavailable;

  /// instanceDetail_containerConfig
  ///
  /// In zh, this message translates to:
  /// **'容器配置'**
  String get instanceDetail_containerConfig;

  /// instanceDetail_containerConfigSaved
  ///
  /// In zh, this message translates to:
  /// **'容器配置已保存'**
  String get instanceDetail_containerConfigSaved;

  /// instanceDetail_image
  ///
  /// In zh, this message translates to:
  /// **'镜像'**
  String get instanceDetail_image;

  /// instanceDetail_imageHelper
  ///
  /// In zh, this message translates to:
  /// **'如 itzg/minecraft-server:latest'**
  String get instanceDetail_imageHelper;

  /// instanceDetail_containerName
  ///
  /// In zh, this message translates to:
  /// **'容器名称（留空自动生成）'**
  String get instanceDetail_containerName;

  /// instanceDetail_portMappingHelper
  ///
  /// In zh, this message translates to:
  /// **'宿主机端口:容器端口，多个用逗号分隔，如 25565:25565, 8123:8123'**
  String get instanceDetail_portMappingHelper;

  /// instanceDetail_volumeMountHelper
  ///
  /// In zh, this message translates to:
  /// **'宿主机路径:容器路径；留空默认挂载实例目录到 /data'**
  String get instanceDetail_volumeMountHelper;

  /// instanceDetail_workdirHelper
  ///
  /// In zh, this message translates to:
  /// **'如 /data，强制在数据目录启动'**
  String get instanceDetail_workdirHelper;

  /// instanceDetail_containerNameDerived
  ///
  /// In zh, this message translates to:
  /// **'容器由实例名派生，如 xmc-<名称>-<id后缀>'**
  String get instanceDetail_containerNameDerived;

  /// instanceDetail_deleteInstanceConfirm
  ///
  /// In zh, this message translates to:
  /// **'确定要删除此实例吗？'**
  String get instanceDetail_deleteInstanceConfirm;

  /// instanceDetail_deleteFiles
  ///
  /// In zh, this message translates to:
  /// **'同时删除服务器文件'**
  String get instanceDetail_deleteFiles;

  /// instanceDetail_deleteFilesDesc
  ///
  /// In zh, this message translates to:
  /// **'勾选后将删除服务器根目录下的所有文件，包括世界、配置和核心。此操作不可撤销。'**
  String get instanceDetail_deleteFilesDesc;

  /// instanceDetail_nameUpdated
  ///
  /// In zh, this message translates to:
  /// **'实例名称已更新'**
  String get instanceDetail_nameUpdated;

  /// instanceDetail_instanceName
  ///
  /// In zh, this message translates to:
  /// **'实例名称'**
  String get instanceDetail_instanceName;

  /// instanceDetail_backupCompressionLevel
  ///
  /// In zh, this message translates to:
  /// **'备份压缩级别'**
  String get instanceDetail_backupCompressionLevel;

  /// instanceDetail_compressionLevelDesc
  ///
  /// In zh, this message translates to:
  /// **'级别越低压缩越快但文件更大，级别越高压缩比越好但更慢。0=不压缩(仅存储)，6=标准，9=最佳压缩比。'**
  String get instanceDetail_compressionLevelDesc;

  /// instanceDetail_eulaAccepted
  ///
  /// In zh, this message translates to:
  /// **'已同意 EULA'**
  String get instanceDetail_eulaAccepted;

  /// instanceDetail_eulaRevoked
  ///
  /// In zh, this message translates to:
  /// **'已撤销 EULA 同意'**
  String get instanceDetail_eulaRevoked;

  /// instanceDetail_eulaTitle
  ///
  /// In zh, this message translates to:
  /// **'EULA 最终用户许可协议'**
  String get instanceDetail_eulaTitle;

  /// instanceDetail_eulaNotFound
  ///
  /// In zh, this message translates to:
  /// **'未找到 eula.txt，将在同意后自动创建。'**
  String get instanceDetail_eulaNotFound;

  /// instanceDetail_eulaAccept
  ///
  /// In zh, this message translates to:
  /// **'同意 Mojang EULA'**
  String get instanceDetail_eulaAccept;

  /// instanceDetail_eulaAcceptedSubtitle
  ///
  /// In zh, this message translates to:
  /// **'已同意，服务器可正常启动'**
  String get instanceDetail_eulaAcceptedSubtitle;

  /// instanceDetail_eulaNotAcceptedSubtitle
  ///
  /// In zh, this message translates to:
  /// **'未同意，服务器启动后将自动退出'**
  String get instanceDetail_eulaNotAcceptedSubtitle;

  /// instanceDetail_eulaNote
  ///
  /// In zh, this message translates to:
  /// **'同意后将写入 eula=true 到 eula.txt。详见 Mojang EULA。'**
  String get instanceDetail_eulaNote;

  /// nodeDetail_notFoundOrDeleted
  ///
  /// In zh, this message translates to:
  /// **'节点不存在或已被删除'**
  String get nodeDetail_notFoundOrDeleted;

  /// nodeDetail_tabOverview
  ///
  /// In zh, this message translates to:
  /// **'概览'**
  String get nodeDetail_tabOverview;

  /// nodeDetail_tabInstances
  ///
  /// In zh, this message translates to:
  /// **'实例'**
  String get nodeDetail_tabInstances;

  /// nodeDetail_tabUsers
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get nodeDetail_tabUsers;

  /// nodeDetail_tabOps
  ///
  /// In zh, this message translates to:
  /// **'运维'**
  String get nodeDetail_tabOps;

  /// nodeDetail_title
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get nodeDetail_title;

  /// nodeDetail_launchLocal
  ///
  /// In zh, this message translates to:
  /// **'启动本地节点'**
  String get nodeDetail_launchLocal;

  /// nodeDetail_cannotLaunch
  ///
  /// In zh, this message translates to:
  /// **'无法启动'**
  String get nodeDetail_cannotLaunch;

  /// nodeDetail_hostInfo
  ///
  /// In zh, this message translates to:
  /// **'主机信息'**
  String get nodeDetail_hostInfo;

  /// nodeDetail_hostname
  ///
  /// In zh, this message translates to:
  /// **'主机名'**
  String get nodeDetail_hostname;

  /// nodeDetail_system
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get nodeDetail_system;

  /// nodeDetail_platform
  ///
  /// In zh, this message translates to:
  /// **'平台'**
  String get nodeDetail_platform;

  /// nodeDetail_uptime
  ///
  /// In zh, this message translates to:
  /// **'运行时间'**
  String get nodeDetail_uptime;

  /// nodeDetail_resourceUsage
  ///
  /// In zh, this message translates to:
  /// **'资源占用'**
  String get nodeDetail_resourceUsage;

  /// nodeDetail_memory
  ///
  /// In zh, this message translates to:
  /// **'内存'**
  String get nodeDetail_memory;

  /// nodeDetail_cpu
  ///
  /// In zh, this message translates to:
  /// **'CPU'**
  String get nodeDetail_cpu;

  /// nodeDetail_nodeProcessMemory
  ///
  /// In zh, this message translates to:
  /// **'节点进程内存'**
  String get nodeDetail_nodeProcessMemory;

  /// nodeDetail_nodeVersion
  ///
  /// In zh, this message translates to:
  /// **'节点版本'**
  String get nodeDetail_nodeVersion;

  /// nodeDetail_instanceStats
  ///
  /// In zh, this message translates to:
  /// **'实例统计'**
  String get nodeDetail_instanceStats;

  /// nodeDetail_daemons
  ///
  /// In zh, this message translates to:
  /// **'守护进程'**
  String get nodeDetail_daemons;

  /// nodeDetail_daemonList
  ///
  /// In zh, this message translates to:
  /// **'守护进程列表'**
  String get nodeDetail_daemonList;

  /// nodeDetail_versionUnknown
  ///
  /// In zh, this message translates to:
  /// **'版本未知'**
  String get nodeDetail_versionUnknown;

  /// nodeDetail_noDaemonId
  ///
  /// In zh, this message translates to:
  /// **'无法确定守护进程 ID，请检查节点连接'**
  String get nodeDetail_noDaemonId;

  /// nodeDetail_selectDaemonToManage
  ///
  /// In zh, this message translates to:
  /// **'选择守护进程后管理其实例'**
  String get nodeDetail_selectDaemonToManage;

  /// nodeDetail_newInstance
  ///
  /// In zh, this message translates to:
  /// **'新建实例'**
  String get nodeDetail_newInstance;

  /// nodeDetail_noInstances
  ///
  /// In zh, this message translates to:
  /// **'暂无实例\n点击右上角「新建实例」创建'**
  String get nodeDetail_noInstances;

  /// nodeDetail_cwdUnknown
  ///
  /// In zh, this message translates to:
  /// **'工作目录未知'**
  String get nodeDetail_cwdUnknown;

  /// nodeDetail_onlinePlayers
  ///
  /// In zh, this message translates to:
  /// **'在线玩家  /  '**
  String get nodeDetail_onlinePlayers;

  /// nodeDetail_start
  ///
  /// In zh, this message translates to:
  /// **'启动'**
  String get nodeDetail_start;

  /// nodeDetail_stop
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get nodeDetail_stop;

  /// nodeDetail_restart
  ///
  /// In zh, this message translates to:
  /// **'重启'**
  String get nodeDetail_restart;

  /// nodeDetail_kill
  ///
  /// In zh, this message translates to:
  /// **'强杀'**
  String get nodeDetail_kill;

  /// nodeDetail_userManagement
  ///
  /// In zh, this message translates to:
  /// **'用户管理（面板 API）'**
  String get nodeDetail_userManagement;

  /// nodeDetail_newUser
  ///
  /// In zh, this message translates to:
  /// **'新建用户'**
  String get nodeDetail_newUser;

  /// nodeDetail_noUsers
  ///
  /// In zh, this message translates to:
  /// **'暂无用户'**
  String get nodeDetail_noUsers;

  /// nodeDetail_admin
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get nodeDetail_admin;

  /// nodeDetail_normalUser
  ///
  /// In zh, this message translates to:
  /// **'普通用户'**
  String get nodeDetail_normalUser;

  /// nodeDetail_setAdmin
  ///
  /// In zh, this message translates to:
  /// **'设为管理员'**
  String get nodeDetail_setAdmin;

  /// nodeDetail_setNormalUser
  ///
  /// In zh, this message translates to:
  /// **'设为普通用户'**
  String get nodeDetail_setNormalUser;

  /// nodeDetail_unban
  ///
  /// In zh, this message translates to:
  /// **'解除禁用'**
  String get nodeDetail_unban;

  /// nodeDetail_create
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get nodeDetail_create;

  /// nodeDetail_username
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get nodeDetail_username;

  /// nodeDetail_password
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get nodeDetail_password;

  /// nodeDetail_permission
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get nodeDetail_permission;

  /// nodeDetail_instanceName
  ///
  /// In zh, this message translates to:
  /// **'实例名称'**
  String get nodeDetail_instanceName;

  /// nodeDetail_workdirAbsolute
  ///
  /// In zh, this message translates to:
  /// **'工作目录（服务器上的绝对路径）'**
  String get nodeDetail_workdirAbsolute;

  /// nodeDetail_serverCommandHelper
  ///
  /// In zh, this message translates to:
  /// **'启动命令（如 java -Xmx2G -jar server.jar nogui）'**
  String get nodeDetail_serverCommandHelper;

  /// nodeDetail_processType
  ///
  /// In zh, this message translates to:
  /// **'进程类型'**
  String get nodeDetail_processType;

  /// nodeDetail_processUniversal
  ///
  /// In zh, this message translates to:
  /// **'通用（直接运行进程）'**
  String get nodeDetail_processUniversal;

  /// nodeDetail_processDocker
  ///
  /// In zh, this message translates to:
  /// **'Docker（容器内运行）'**
  String get nodeDetail_processDocker;

  /// nodeDetail_dockerImage
  ///
  /// In zh, this message translates to:
  /// **'Docker 镜像（如 mcsm-ubuntu:22.04）'**
  String get nodeDetail_dockerImage;

  /// nodeDetail_memoryLimit
  ///
  /// In zh, this message translates to:
  /// **'内存限制（MB）'**
  String get nodeDetail_memoryLimit;

  /// nodeDetail_networkMode
  ///
  /// In zh, this message translates to:
  /// **'网络模式'**
  String get nodeDetail_networkMode;

  /// nodeDetail_portMappingHelper
  ///
  /// In zh, this message translates to:
  /// **'端口映射（逗号分隔，如 25565:25565/tcp）'**
  String get nodeDetail_portMappingHelper;

  /// nodeDetail_extraVolumes
  ///
  /// In zh, this message translates to:
  /// **'额外挂载卷（逗号分隔，如 /data:/data）'**
  String get nodeDetail_extraVolumes;

  /// nodeDetail_containerNameOptional
  ///
  /// In zh, this message translates to:
  /// **'容器名称（可留空自动生成）'**
  String get nodeDetail_containerNameOptional;

  /// nodeDetail_importFailed
  ///
  /// In zh, this message translates to:
  /// **'导入失败'**
  String get nodeDetail_importFailed;

  /// nodeDetail_gomaxprocs
  ///
  /// In zh, this message translates to:
  /// **'GOMAXPROCS'**
  String get nodeDetail_gomaxprocs;

  /// nodeDetail_gcPercent
  ///
  /// In zh, this message translates to:
  /// **'GC 百分比'**
  String get nodeDetail_gcPercent;

  /// nodeDetail_cpuUsage
  ///
  /// In zh, this message translates to:
  /// **'CPU 占用'**
  String get nodeDetail_cpuUsage;

  /// nodeDetail_goroutines
  ///
  /// In zh, this message translates to:
  /// **'goroutine 数'**
  String get nodeDetail_goroutines;

  /// nodeDetail_heapMemory
  ///
  /// In zh, this message translates to:
  /// **'堆内存'**
  String get nodeDetail_heapMemory;

  /// nodeDetail_cpuCores
  ///
  /// In zh, this message translates to:
  /// **'CPU 核数'**
  String get nodeDetail_cpuCores;

  /// nodeDetail_nodeLoad
  ///
  /// In zh, this message translates to:
  /// **'节点负载'**
  String get nodeDetail_nodeLoad;

  /// nodeDetail_importInstanceTitle
  ///
  /// In zh, this message translates to:
  /// **'从目录导入实例'**
  String get nodeDetail_importInstanceTitle;

  /// nodeDetail_importInstanceDesc
  ///
  /// In zh, this message translates to:
  /// **'指定节点侧已存在的服务端目录，节点扫描特征后创建实例。'**
  String get nodeDetail_importInstanceDesc;

  /// nodeDetail_import
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get nodeDetail_import;

  /// nodeDetail_downloadCoreTitle
  ///
  /// In zh, this message translates to:
  /// **'下载服务端核心到实例'**
  String get nodeDetail_downloadCoreTitle;

  /// nodeDetail_downloadCoreDesc
  ///
  /// In zh, this message translates to:
  /// **'节点直连 URL 下载核心 jar 到实例根目录（支持 sha512 校验）。'**
  String get nodeDetail_downloadCoreDesc;

  /// nodeDetail_downloadCore
  ///
  /// In zh, this message translates to:
  /// **'下载核心'**
  String get nodeDetail_downloadCore;

  /// nodeDetail_nodeLoadDesc
  ///
  /// In zh, this message translates to:
  /// **'守护进程自身负载调谐状态（idle/normal/busy、GOMAXPROCS、GC）。'**
  String get nodeDetail_nodeLoadDesc;

  /// nodeDetail_view
  ///
  /// In zh, this message translates to:
  /// **'查看'**
  String get nodeDetail_view;

  /// nodeDetail_auditLog
  ///
  /// In zh, this message translates to:
  /// **'审计日志'**
  String get nodeDetail_auditLog;

  /// nodeDetail_auditLogDesc
  ///
  /// In zh, this message translates to:
  /// **'记录每一次 API 请求（来源 IP、方法、路径、状态码、耗时）。'**
  String get nodeDetail_auditLogDesc;

  /// nodeDetail_javaRuntime
  ///
  /// In zh, this message translates to:
  /// **'Java 运行时'**
  String get nodeDetail_javaRuntime;

  /// nodeDetail_noJavaRuntime
  ///
  /// In zh, this message translates to:
  /// **'（未检测到 Java 运行时）'**
  String get nodeDetail_noJavaRuntime;

  /// nodeDetail_unavailableParen
  ///
  /// In zh, this message translates to:
  /// **'（不可用）'**
  String get nodeDetail_unavailableParen;

  /// nodeDetail_processing
  ///
  /// In zh, this message translates to:
  /// **'处理中…'**
  String get nodeDetail_processing;

  /// nodeDetail_instanceNameOptional
  ///
  /// In zh, this message translates to:
  /// **'实例名（可空，默认取目录名）'**
  String get nodeDetail_instanceNameOptional;

  /// nodeDetail_nodeDirPath
  ///
  /// In zh, this message translates to:
  /// **'节点侧目录绝对路径'**
  String get nodeDetail_nodeDirPath;

  /// nodeDetail_nodeDirPathHint
  ///
  /// In zh, this message translates to:
  /// **'如 /home/mc/server'**
  String get nodeDetail_nodeDirPathHint;

  /// nodeDetail_targetUuid
  ///
  /// In zh, this message translates to:
  /// **'目标实例 UUID'**
  String get nodeDetail_targetUuid;

  /// nodeDetail_downloadUrl
  ///
  /// In zh, this message translates to:
  /// **'下载链接 (http/https)'**
  String get nodeDetail_downloadUrl;

  /// nodeDetail_fileName
  ///
  /// In zh, this message translates to:
  /// **'文件名（如 server.jar）'**
  String get nodeDetail_fileName;

  /// nodeDetail_sha512
  ///
  /// In zh, this message translates to:
  /// **'sha512 校验（可选）'**
  String get nodeDetail_sha512;

  /// nodeDetail_startDownload
  ///
  /// In zh, this message translates to:
  /// **'开始下载'**
  String get nodeDetail_startDownload;

  /// nodeDetail_auditLogRecent
  ///
  /// In zh, this message translates to:
  /// **'审计日志（最近 200 行）'**
  String get nodeDetail_auditLogRecent;

  /// nodeDetail_noAuditLog
  ///
  /// In zh, this message translates to:
  /// **'（无审计日志）'**
  String get nodeDetail_noAuditLog;

  /// nodeDetail_uninstall
  ///
  /// In zh, this message translates to:
  /// **'卸载'**
  String get nodeDetail_uninstall;

  /// No description provided for @instanceDetail_startFailed.
  ///
  /// In zh, this message translates to:
  /// **'启动失败：'**
  String instanceDetail_startFailed(String error);

  /// No description provided for @instanceDetail_restartFailed.
  ///
  /// In zh, this message translates to:
  /// **'重启失败：'**
  String instanceDetail_restartFailed(String error);

  /// No description provided for @instanceDetail_backupSaved.
  ///
  /// In zh, this message translates to:
  /// **'备份已保存到'**
  String instanceDetail_backupSaved(String path);

  /// No description provided for @instanceDetail_backupFailed.
  ///
  /// In zh, this message translates to:
  /// **'备份失败:'**
  String instanceDetail_backupFailed(String error);

  /// No description provided for @instanceDetail_errorCode.
  ///
  /// In zh, this message translates to:
  /// **'错误码'**
  String instanceDetail_errorCode(int code);

  /// No description provided for @instanceDetail_selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选择  /  项'**
  String instanceDetail_selectedCount(int selected, int total);

  /// No description provided for @instanceDetail_switchedToMode.
  ///
  /// In zh, this message translates to:
  /// **'已切换为「」运行'**
  String instanceDetail_switchedToMode(String mode);

  /// No description provided for @instanceDetail_eulaWriteFailed.
  ///
  /// In zh, this message translates to:
  /// **'写入 eula.txt 失败:'**
  String instanceDetail_eulaWriteFailed(String error);

  /// No description provided for @nodeDetail_onlineWithAddr.
  ///
  /// In zh, this message translates to:
  /// **'节点在线 ·  '**
  String nodeDetail_onlineWithAddr(String address);

  /// No description provided for @nodeDetail_offlineWithError.
  ///
  /// In zh, this message translates to:
  /// **'节点离线：'**
  String nodeDetail_offlineWithError(String error);

  /// No description provided for @nodeDetail_notLocalAddress.
  ///
  /// In zh, this message translates to:
  /// **'「」不是本地地址，请确认 irix-node 已在该服务器上运行。'**
  String nodeDetail_notLocalAddress(String name);

  /// No description provided for @nodeDetail_cannotGetInfo.
  ///
  /// In zh, this message translates to:
  /// **'无法获取节点信息\n'**
  String nodeDetail_cannotGetInfo(String url);

  /// No description provided for @nodeDetail_daemonCount.
  ///
  /// In zh, this message translates to:
  /// **' 个'**
  String nodeDetail_daemonCount(int count);

  /// No description provided for @nodeDetail_runningTotal.
  ///
  /// In zh, this message translates to:
  /// **'运行  / 共  '**
  String nodeDetail_runningTotal(int running, int total);

  /// No description provided for @nodeDetail_daemonListLine.
  ///
  /// In zh, this message translates to:
  /// **' ·  · '**
  String nodeDetail_daemonListLine(
    String status,
    String version,
    String ip,
    int port,
  );

  /// No description provided for @nodeDetail_instanceCount.
  ///
  /// In zh, this message translates to:
  /// **'共  个实例'**
  String nodeDetail_instanceCount(int count);

  /// No description provided for @nodeDetail_deleteUserConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除用户「」？'**
  String nodeDetail_deleteUserConfirm(String username);

  /// No description provided for @nodeDetail_registered.
  ///
  /// In zh, this message translates to:
  /// **'注册  '**
  String nodeDetail_registered(String time);

  /// No description provided for @nodeDetail_instancesCount.
  ///
  /// In zh, this message translates to:
  /// **'实例  个'**
  String nodeDetail_instancesCount(int count);

  /// No description provided for @nodeDetail_installingJdk.
  ///
  /// In zh, this message translates to:
  /// **'安装 JDK  中…'**
  String nodeDetail_installingJdk(int major);

  /// No description provided for @nodeDetail_jdkInstalled.
  ///
  /// In zh, this message translates to:
  /// **'JDK  安装完成'**
  String nodeDetail_jdkInstalled(int major);

  /// No description provided for @nodeDetail_jdkInstallFailed.
  ///
  /// In zh, this message translates to:
  /// **'JDK  安装失败'**
  String nodeDetail_jdkInstallFailed(int major);

  /// No description provided for @nodeDetail_uninstallJdkTitle.
  ///
  /// In zh, this message translates to:
  /// **'卸载 JDK ？'**
  String nodeDetail_uninstallJdkTitle(int major);

  /// No description provided for @nodeDetail_uninstallJdkContent.
  ///
  /// In zh, this message translates to:
  /// **'将从节点 {data}/jdk 删除该版本。'**
  String nodeDetail_uninstallJdkContent(String data);

  /// No description provided for @nodeDetail_importedInstance.
  ///
  /// In zh, this message translates to:
  /// **'已导入实例 ，请在「实例」标签页查看'**
  String nodeDetail_importedInstance(String uuid);

  /// No description provided for @nodeDetail_importFailedWith.
  ///
  /// In zh, this message translates to:
  /// **'导入失败：'**
  String nodeDetail_importFailedWith(String error);

  /// No description provided for @nodeDetail_coreDownloadStarted.
  ///
  /// In zh, this message translates to:
  /// **'已开始下载核心（任务 ），进度见节点日志'**
  String nodeDetail_coreDownloadStarted(String jobId);

  /// No description provided for @nodeDetail_coreDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'核心下载失败：'**
  String nodeDetail_coreDownloadFailed(String error);

  /// No description provided for @nodeDetail_loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取负载失败：'**
  String nodeDetail_loadFailed(String error);

  /// No description provided for @nodeDetail_auditFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取审计日志失败：'**
  String nodeDetail_auditFailed(String error);

  /// No description provided for @nodeDetail_javaRuntimeDesc.
  ///
  /// In zh, this message translates to:
  /// **'检测节点上的 Java 安装；可安装 Adoptium JDK 到 {data}/jdk。'**
  String nodeDetail_javaRuntimeDesc(String data);

  /// No description provided for @nodeDetail_installJdk.
  ///
  /// In zh, this message translates to:
  /// **'安装 JDK  '**
  String nodeDetail_installJdk(int major);

  /// frp_remotePortLabel
  ///
  /// In zh, this message translates to:
  /// **'远程端口'**
  String get frp_remotePortLabel;

  /// nodeDetail_cannotConnect
  ///
  /// In zh, this message translates to:
  /// **'无法连接'**
  String get nodeDetail_cannotConnect;

  /// No description provided for @nodeDetail_uptimeDaysHours.
  ///
  /// In zh, this message translates to:
  /// **'{days}天 {hours}小时'**
  String nodeDetail_uptimeDaysHours(int days, int hours);

  /// No description provided for @nodeDetail_uptimeHoursMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{hours}小时 {minutes}分钟'**
  String nodeDetail_uptimeHoursMinutes(int hours, int minutes);

  /// No description provided for @nodeDetail_uptimeMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes}分钟'**
  String nodeDetail_uptimeMinutes(int minutes);

  /// nodeDetail_startCommandHelper
  ///
  /// In zh, this message translates to:
  /// **'启动命令（如 java -Xmx2G -jar server.jar nogui）'**
  String get nodeDetail_startCommandHelper;

  /// remoteTab_statusListRoot
  ///
  /// In zh, this message translates to:
  /// **'获取实例根目录列表…'**
  String get remoteTab_statusListRoot;

  /// remoteTab_statusCompressing
  ///
  /// In zh, this message translates to:
  /// **'节点端压缩实例目录…（大实例可能较慢）'**
  String get remoteTab_statusCompressing;

  /// remoteTab_saveBackup
  ///
  /// In zh, this message translates to:
  /// **'保存备份'**
  String get remoteTab_saveBackup;

  /// remoteTab_statusDownloading
  ///
  /// In zh, this message translates to:
  /// **'下载备份…'**
  String get remoteTab_statusDownloading;

  /// No description provided for @remoteTab_backupSaved.
  ///
  /// In zh, this message translates to:
  /// **'备份已保存到 {path}'**
  String remoteTab_backupSaved(String path);

  /// clusterHome_title
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get clusterHome_title;

  /// clusterHome_refreshStatus
  ///
  /// In zh, this message translates to:
  /// **'刷新状态'**
  String get clusterHome_refreshStatus;

  /// clusterHome_addNode
  ///
  /// In zh, this message translates to:
  /// **'添加节点'**
  String get clusterHome_addNode;

  /// clusterHome_noNodes
  ///
  /// In zh, this message translates to:
  /// **'还没有节点，点击右上角 + 添加'**
  String get clusterHome_noNodes;

  /// clusterHome_noNodesHint
  ///
  /// In zh, this message translates to:
  /// **'多机模式需要至少 2 个节点（MCSM 面板或 IriX 本地节点）'**
  String get clusterHome_noNodesHint;

  /// clusterHome_monitorMutual
  ///
  /// In zh, this message translates to:
  /// **'节点互相监控'**
  String get clusterHome_monitorMutual;

  /// clusterHome_monitorNoEligible
  ///
  /// In zh, this message translates to:
  /// **'节点 ≥3 台，但均为 MCSM，无可用监控节点（MCSM 不支持节点互联）'**
  String get clusterHome_monitorNoEligible;

  /// clusterHome_monitorInsufficient
  ///
  /// In zh, this message translates to:
  /// **'至少需要 2 个节点才能形成集群'**
  String get clusterHome_monitorInsufficient;

  /// clusterHome_networkThroughput
  ///
  /// In zh, this message translates to:
  /// **'网络吞吐（所有节点）'**
  String get clusterHome_networkThroughput;

  /// clusterHome_resourceOverview
  ///
  /// In zh, this message translates to:
  /// **'节点资源总览'**
  String get clusterHome_resourceOverview;

  /// clusterHome_colNode
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get clusterHome_colNode;

  /// clusterHome_colCpu
  ///
  /// In zh, this message translates to:
  /// **'CPU'**
  String get clusterHome_colCpu;

  /// clusterHome_colMemory
  ///
  /// In zh, this message translates to:
  /// **'内存'**
  String get clusterHome_colMemory;

  /// clusterHome_colDisk
  ///
  /// In zh, this message translates to:
  /// **'磁盘'**
  String get clusterHome_colDisk;

  /// clusterHome_total
  ///
  /// In zh, this message translates to:
  /// **'合计'**
  String get clusterHome_total;

  /// clusterHome_monitor
  ///
  /// In zh, this message translates to:
  /// **'监控'**
  String get clusterHome_monitor;

  /// clusterHome_cpuTooltip
  ///
  /// In zh, this message translates to:
  /// **'CPU {pct}%'**
  String clusterHome_cpuTooltip(Object pct);

  /// clusterHome_memoryTooltip
  ///
  /// In zh, this message translates to:
  /// **'内存 {pct}%（{detail}）'**
  String clusterHome_memoryTooltip(Object detail, Object pct);

  /// clusterHome_diskTooltip
  ///
  /// In zh, this message translates to:
  /// **'磁盘 {pct}%（{detail}）'**
  String clusterHome_diskTooltip(Object detail, Object pct);

  /// clusterInstances_title
  ///
  /// In zh, this message translates to:
  /// **'实例管理'**
  String get clusterInstances_title;

  /// clusterInstances_newInstance
  ///
  /// In zh, this message translates to:
  /// **'新建实例'**
  String get clusterInstances_newInstance;

  /// clusterInstances_empty
  ///
  /// In zh, this message translates to:
  /// **'暂无集群实例，点击右上角「新建实例」'**
  String get clusterInstances_empty;

  /// clusterInstances_noNodeToMigrate
  ///
  /// In zh, this message translates to:
  /// **'没有其它节点可迁移'**
  String get clusterInstances_noNodeToMigrate;

  /// clusterInstances_node
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get clusterInstances_node;

  /// clusterInstances_workdir
  ///
  /// In zh, this message translates to:
  /// **'工作目录（服务器上的绝对路径）'**
  String get clusterInstances_workdir;

  /// clusterInstances_autoAllocate
  ///
  /// In zh, this message translates to:
  /// **'自动（按资源分配）'**
  String get clusterInstances_autoAllocate;

  /// clusterInstances_newClusterInstance
  ///
  /// In zh, this message translates to:
  /// **'新建集群实例'**
  String get clusterInstances_newClusterInstance;

  /// clusterInstances_selectMigrateTarget
  ///
  /// In zh, this message translates to:
  /// **'选择迁移目标节点'**
  String get clusterInstances_selectMigrateTarget;

  /// clusterInstances_migrate
  ///
  /// In zh, this message translates to:
  /// **'迁移'**
  String get clusterInstances_migrate;

  /// clusterContainer_noNodes
  ///
  /// In zh, this message translates to:
  /// **'还没有节点'**
  String get clusterContainer_noNodes;

  /// clusterContainer_noNodesHint
  ///
  /// In zh, this message translates to:
  /// **'添加 Linux 节点管理 Docker、添加 FreeBSD 节点管理 Bastille'**
  String get clusterContainer_noNodesHint;

  /// clusterContainer_addNode
  ///
  /// In zh, this message translates to:
  /// **'添加节点'**
  String get clusterContainer_addNode;

  /// clusterContainer_node
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get clusterContainer_node;

  /// clusterContainer_onlineDetecting
  ///
  /// In zh, this message translates to:
  /// **'在线 · 探测中…'**
  String get clusterContainer_onlineDetecting;

  /// clusterContainer_nodeOffline
  ///
  /// In zh, this message translates to:
  /// **'节点离线：{name}'**
  String clusterContainer_nodeOffline(Object name);

  /// clusterOrch_title
  ///
  /// In zh, this message translates to:
  /// **'编排服务'**
  String get clusterOrch_title;

  /// clusterOrch_subtitle
  ///
  /// In zh, this message translates to:
  /// **'K8s 风格：自动修复崩溃 · 按在线人数弹性开服 · 跨物理机迁移存档'**
  String get clusterOrch_subtitle;

  /// clusterOrch_reconcileNow
  ///
  /// In zh, this message translates to:
  /// **'立即对账'**
  String get clusterOrch_reconcileNow;

  /// clusterOrch_newService
  ///
  /// In zh, this message translates to:
  /// **'新建服务'**
  String get clusterOrch_newService;

  /// clusterOrch_noServices
  ///
  /// In zh, this message translates to:
  /// **'还没有编排服务'**
  String get clusterOrch_noServices;

  /// clusterOrch_noServicesHint
  ///
  /// In zh, this message translates to:
  /// **'新建服务后，引擎将自动调度副本到 Docker / Bastille 节点'**
  String get clusterOrch_noServicesHint;

  /// clusterOrch_migrationTasks
  ///
  /// In zh, this message translates to:
  /// **'迁移任务'**
  String get clusterOrch_migrationTasks;

  /// clusterOrch_runtimeBastille
  ///
  /// In zh, this message translates to:
  /// **'Bastille'**
  String get clusterOrch_runtimeBastille;

  /// clusterOrch_runtimeDocker
  ///
  /// In zh, this message translates to:
  /// **'Docker'**
  String get clusterOrch_runtimeDocker;

  /// clusterOrch_scaleDown
  ///
  /// In zh, this message translates to:
  /// **'缩容'**
  String get clusterOrch_scaleDown;

  /// clusterOrch_scaleUp
  ///
  /// In zh, this message translates to:
  /// **'扩容'**
  String get clusterOrch_scaleUp;

  /// clusterOrch_migrateArchive
  ///
  /// In zh, this message translates to:
  /// **'迁移存档到其它节点'**
  String get clusterOrch_migrateArchive;

  /// clusterOrch_deleteServiceMenuItem
  ///
  /// In zh, this message translates to:
  /// **'删除服务'**
  String get clusterOrch_deleteServiceMenuItem;

  /// clusterOrch_autoHeal
  ///
  /// In zh, this message translates to:
  /// **'自动修复崩溃'**
  String get clusterOrch_autoHeal;

  /// clusterOrch_autoscale
  ///
  /// In zh, this message translates to:
  /// **'弹性开服'**
  String get clusterOrch_autoscale;

  /// clusterOrch_noSchedulableNode
  ///
  /// In zh, this message translates to:
  /// **'无满足条件的节点'**
  String get clusterOrch_noSchedulableNode;

  /// clusterOrch_continueMigration
  ///
  /// In zh, this message translates to:
  /// **'继续执行'**
  String get clusterOrch_continueMigration;

  /// clusterOrch_cancelMigration
  ///
  /// In zh, this message translates to:
  /// **'取消迁移'**
  String get clusterOrch_cancelMigration;

  /// clusterOrch_newServiceDialog
  ///
  /// In zh, this message translates to:
  /// **'新建编排服务'**
  String get clusterOrch_newServiceDialog;

  /// clusterOrch_serviceName
  ///
  /// In zh, this message translates to:
  /// **'服务名称'**
  String get clusterOrch_serviceName;

  /// clusterOrch_runtime
  ///
  /// In zh, this message translates to:
  /// **'运行时'**
  String get clusterOrch_runtime;

  /// clusterOrch_runtimeDockerLinux
  ///
  /// In zh, this message translates to:
  /// **'Docker（Linux 节点）'**
  String get clusterOrch_runtimeDockerLinux;

  /// clusterOrch_runtimeBastilleFbsd
  ///
  /// In zh, this message translates to:
  /// **'Bastille（FreeBSD 节点）'**
  String get clusterOrch_runtimeBastilleFbsd;

  /// clusterOrch_imageOrRelease
  ///
  /// In zh, this message translates to:
  /// **'镜像 / 发行版'**
  String get clusterOrch_imageOrRelease;

  /// clusterOrch_imageHintRelease
  ///
  /// In zh, this message translates to:
  /// **'如 14.2-RELEASE'**
  String get clusterOrch_imageHintRelease;

  /// clusterOrch_imageHintDocker
  ///
  /// In zh, this message translates to:
  /// **'如 itzg/minecraft-server:latest'**
  String get clusterOrch_imageHintDocker;

  /// clusterOrch_portsMapping
  ///
  /// In zh, this message translates to:
  /// **'端口映射（扩容时宿主端口按序号顺延）'**
  String get clusterOrch_portsMapping;

  /// clusterOrch_volumeMount
  ///
  /// In zh, this message translates to:
  /// **'数据目录挂载（宿主机:容器内）'**
  String get clusterOrch_volumeMount;

  /// clusterOrch_volumeMountHint
  ///
  /// In zh, this message translates to:
  /// **'如 /data/mc-survival:/data'**
  String get clusterOrch_volumeMountHint;

  /// clusterOrch_worldDir
  ///
  /// In zh, this message translates to:
  /// **'世界存档目录（容器内，迁移对象）'**
  String get clusterOrch_worldDir;

  /// clusterOrch_bastilleIpBase
  ///
  /// In zh, this message translates to:
  /// **'IP 基址（副本按序号顺延，如 .50 → .51）'**
  String get clusterOrch_bastilleIpBase;

  /// clusterOrch_minReplicas
  ///
  /// In zh, this message translates to:
  /// **'最小副本'**
  String get clusterOrch_minReplicas;

  /// clusterOrch_desiredReplicas
  ///
  /// In zh, this message translates to:
  /// **'期望副本'**
  String get clusterOrch_desiredReplicas;

  /// clusterOrch_maxReplicas
  ///
  /// In zh, this message translates to:
  /// **'最大副本'**
  String get clusterOrch_maxReplicas;

  /// clusterOrch_autoscaleDesc
  ///
  /// In zh, this message translates to:
  /// **'弹性开服（按在线人数扩缩容）'**
  String get clusterOrch_autoscaleDesc;

  /// clusterOrch_targetPlayersPerReplica
  ///
  /// In zh, this message translates to:
  /// **'每副本目标在线人数'**
  String get clusterOrch_targetPlayersPerReplica;

  /// clusterOrch_autoHealDesc
  ///
  /// In zh, this message translates to:
  /// **'自动修复崩溃（指数退避重启）'**
  String get clusterOrch_autoHealDesc;

  /// clusterOrch_migrateToPhysical
  ///
  /// In zh, this message translates to:
  /// **'迁移存档到其它物理机'**
  String get clusterOrch_migrateToPhysical;

  /// clusterOrch_replica
  ///
  /// In zh, this message translates to:
  /// **'副本'**
  String get clusterOrch_replica;

  /// clusterOrch_targetNode
  ///
  /// In zh, this message translates to:
  /// **'目标节点'**
  String get clusterOrch_targetNode;

  /// clusterOrch_migrateFlow
  ///
  /// In zh, this message translates to:
  /// **'迁移流程：停止副本 → 压缩世界存档 → 传输 → 目标节点恢复 → 重建并启动。'**
  String get clusterOrch_migrateFlow;

  /// clusterOrch_startMigration
  ///
  /// In zh, this message translates to:
  /// **'开始迁移'**
  String get clusterOrch_startMigration;

  /// clusterOrch_serviceCreated
  ///
  /// In zh, this message translates to:
  /// **'服务已创建：{name}'**
  String clusterOrch_serviceCreated(Object name);

  /// clusterOrch_createFailed
  ///
  /// In zh, this message translates to:
  /// **'创建失败：{e}'**
  String clusterOrch_createFailed(Object e);

  /// clusterOrch_updateFailed
  ///
  /// In zh, this message translates to:
  /// **'更新失败：{e}'**
  String clusterOrch_updateFailed(Object e);

  /// clusterOrch_deleteService
  ///
  /// In zh, this message translates to:
  /// **'删除服务 {name}'**
  String clusterOrch_deleteService(Object name);

  /// clusterOrch_deleteServiceConfirm
  ///
  /// In zh, this message translates to:
  /// **'将销毁该服务的全部副本（容器 / jail），确定继续？'**
  String get clusterOrch_deleteServiceConfirm;

  /// clusterOrch_migrateNeedTwoNodes
  ///
  /// In zh, this message translates to:
  /// **'迁移需要至少 2 个节点'**
  String get clusterOrch_migrateNeedTwoNodes;

  /// clusterOrch_migrationCreated
  ///
  /// In zh, this message translates to:
  /// **'迁移任务已创建'**
  String get clusterOrch_migrationCreated;

  /// clusterOrch_migrateFailed
  ///
  /// In zh, this message translates to:
  /// **'迁移失败：{e}'**
  String clusterOrch_migrateFailed(Object e);

  /// clusterOrch_deleteFailed
  ///
  /// In zh, this message translates to:
  /// **'删除失败：{e}'**
  String clusterOrch_deleteFailed(Object e);

  /// clusterOrch_nameAndImageRequired
  ///
  /// In zh, this message translates to:
  /// **'名称与镜像 / 发行版不能为空'**
  String get clusterOrch_nameAndImageRequired;

  /// clusterOrch_replicaPending
  ///
  /// In zh, this message translates to:
  /// **'r{indexNo} · 待调度'**
  String clusterOrch_replicaPending(Object indexNo);

  /// clusterOrch_replicaRunning
  ///
  /// In zh, this message translates to:
  /// **'r{indexNo} · {nodeId}（运行中）'**
  String clusterOrch_replicaRunning(Object indexNo, Object nodeId);

  /// remoteInstance_deleteTitle
  ///
  /// In zh, this message translates to:
  /// **'删除实例「{name}」？'**
  String remoteInstance_deleteTitle(Object name);

  /// remoteInstance_deleteContent
  ///
  /// In zh, this message translates to:
  /// **'同时删除实例文件需要面板 API 权限支持。'**
  String get remoteInstance_deleteContent;

  /// remoteInstance_tabConsole
  ///
  /// In zh, this message translates to:
  /// **'控制台'**
  String get remoteInstance_tabConsole;

  /// remoteInstance_noLogOutput
  ///
  /// In zh, this message translates to:
  /// **'（暂无日志输出）'**
  String get remoteInstance_noLogOutput;

  /// remoteInstance_commandInputHint
  ///
  /// In zh, this message translates to:
  /// **'输入命令（如 say hello），回车发送'**
  String get remoteInstance_commandInputHint;

  /// remoteInstance_sendCommand
  ///
  /// In zh, this message translates to:
  /// **'发送命令'**
  String get remoteInstance_sendCommand;

  /// remoteInstance_fInstanceId
  ///
  /// In zh, this message translates to:
  /// **'实例 ID'**
  String get remoteInstance_fInstanceId;

  /// remoteInstance_fName
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get remoteInstance_fName;

  /// remoteInstance_fStartCommand
  ///
  /// In zh, this message translates to:
  /// **'启动命令'**
  String get remoteInstance_fStartCommand;

  /// remoteInstance_fStopCommand
  ///
  /// In zh, this message translates to:
  /// **'停止命令'**
  String get remoteInstance_fStopCommand;

  /// remoteInstance_fWorkdir
  ///
  /// In zh, this message translates to:
  /// **'工作目录'**
  String get remoteInstance_fWorkdir;

  /// remoteInstance_fType
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get remoteInstance_fType;

  /// remoteInstance_fProcessType
  ///
  /// In zh, this message translates to:
  /// **'进程类型'**
  String get remoteInstance_fProcessType;

  /// remoteInstance_fFileEncoding
  ///
  /// In zh, this message translates to:
  /// **'文件编码'**
  String get remoteInstance_fFileEncoding;

  /// remoteInstance_fInputEncoding
  ///
  /// In zh, this message translates to:
  /// **'输入编码'**
  String get remoteInstance_fInputEncoding;

  /// remoteInstance_fOutputEncoding
  ///
  /// In zh, this message translates to:
  /// **'输出编码'**
  String get remoteInstance_fOutputEncoding;

  /// remoteInstance_fAutoStart
  ///
  /// In zh, this message translates to:
  /// **'自动启动'**
  String get remoteInstance_fAutoStart;

  /// remoteInstance_fAutoRestart
  ///
  /// In zh, this message translates to:
  /// **'自动重启'**
  String get remoteInstance_fAutoRestart;

  /// remoteInstance_fStartCount
  ///
  /// In zh, this message translates to:
  /// **'启动次数'**
  String get remoteInstance_fStartCount;

  /// remoteInstance_fPid
  ///
  /// In zh, this message translates to:
  /// **'进程 PID'**
  String get remoteInstance_fPid;

  /// remoteInstance_fContainerName
  ///
  /// In zh, this message translates to:
  /// **'容器名称'**
  String get remoteInstance_fContainerName;

  /// remoteInstance_fImage
  ///
  /// In zh, this message translates to:
  /// **'镜像'**
  String get remoteInstance_fImage;

  /// remoteInstance_fMemoryLimit
  ///
  /// In zh, this message translates to:
  /// **'内存限制'**
  String get remoteInstance_fMemoryLimit;

  /// remoteInstance_fPortMapping
  ///
  /// In zh, this message translates to:
  /// **'端口映射'**
  String get remoteInstance_fPortMapping;

  /// remoteInstance_fExtraVolumes
  ///
  /// In zh, this message translates to:
  /// **'额外挂载卷'**
  String get remoteInstance_fExtraVolumes;

  /// remoteInstance_fNetworkMode
  ///
  /// In zh, this message translates to:
  /// **'网络模式'**
  String get remoteInstance_fNetworkMode;

  /// remoteInstance_editConfig
  ///
  /// In zh, this message translates to:
  /// **'编辑配置'**
  String get remoteInstance_editConfig;

  /// remoteInstance_editConfigDialog
  ///
  /// In zh, this message translates to:
  /// **'编辑实例配置'**
  String get remoteInstance_editConfigDialog;

  /// remoteInstance_autoRestartToggle
  ///
  /// In zh, this message translates to:
  /// **'崩溃后自动重启'**
  String get remoteInstance_autoRestartToggle;

  /// remoteInstance_processUniversal
  ///
  /// In zh, this message translates to:
  /// **'通用（直接运行进程）'**
  String get remoteInstance_processUniversal;

  /// remoteInstance_processDocker
  ///
  /// In zh, this message translates to:
  /// **'Docker（容器内运行）'**
  String get remoteInstance_processDocker;

  /// remoteInstance_dockerImage
  ///
  /// In zh, this message translates to:
  /// **'Docker 镜像（如 mcsm-ubuntu:22.04）'**
  String get remoteInstance_dockerImage;

  /// remoteInstance_memoryLimitMb
  ///
  /// In zh, this message translates to:
  /// **'内存限制（MB）'**
  String get remoteInstance_memoryLimitMb;

  /// remoteInstance_portsMapping
  ///
  /// In zh, this message translates to:
  /// **'端口映射（逗号分隔，如 25565:25565/tcp）'**
  String get remoteInstance_portsMapping;

  /// remoteInstance_extraVolumes
  ///
  /// In zh, this message translates to:
  /// **'额外挂载卷（逗号分隔，如 /data:/data）'**
  String get remoteInstance_extraVolumes;

  /// remoteInstance_containerNameAuto
  ///
  /// In zh, this message translates to:
  /// **'容器名称（可留空自动生成）'**
  String get remoteInstance_containerNameAuto;

  /// remoteFile_noDaemonId
  ///
  /// In zh, this message translates to:
  /// **'无法确定守护进程 ID'**
  String get remoteFile_noDaemonId;

  /// remoteFile_newFolder
  ///
  /// In zh, this message translates to:
  /// **'新建文件夹'**
  String get remoteFile_newFolder;

  /// remoteFile_folderName
  ///
  /// In zh, this message translates to:
  /// **'文件夹名称'**
  String get remoteFile_folderName;

  /// remoteFile_newFile
  ///
  /// In zh, this message translates to:
  /// **'新建文件'**
  String get remoteFile_newFile;

  /// remoteFile_fileName
  ///
  /// In zh, this message translates to:
  /// **'文件名称'**
  String get remoteFile_fileName;

  /// remoteFile_selectFilesToUpload
  ///
  /// In zh, this message translates to:
  /// **'选择要上传的文件'**
  String get remoteFile_selectFilesToUpload;

  /// remoteFile_saveFile
  ///
  /// In zh, this message translates to:
  /// **'保存文件'**
  String get remoteFile_saveFile;

  /// remoteFile_fileTooLarge
  ///
  /// In zh, this message translates to:
  /// **'文件过大（>2MB），请下载后编辑'**
  String get remoteFile_fileTooLarge;

  /// remoteFile_editFile
  ///
  /// In zh, this message translates to:
  /// **'编辑 {name}'**
  String remoteFile_editFile(Object name);

  /// remoteFile_saved
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get remoteFile_saved;

  /// remoteFile_rename
  ///
  /// In zh, this message translates to:
  /// **'重命名 {name}'**
  String remoteFile_rename(Object name);

  /// remoteFile_newName
  ///
  /// In zh, this message translates to:
  /// **'新名称'**
  String get remoteFile_newName;

  /// remoteFile_compress
  ///
  /// In zh, this message translates to:
  /// **'压缩 {name}'**
  String remoteFile_compress(Object name);

  /// remoteFile_archiveName
  ///
  /// In zh, this message translates to:
  /// **'压缩包文件名'**
  String get remoteFile_archiveName;

  /// remoteFile_folder
  ///
  /// In zh, this message translates to:
  /// **'文件夹'**
  String get remoteFile_folder;

  /// remoteFile_download
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get remoteFile_download;

  /// remoteFile_edit
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get remoteFile_edit;

  /// remoteFile_renameAction
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get remoteFile_renameAction;

  /// remoteFile_unzipHere
  ///
  /// In zh, this message translates to:
  /// **'解压到当前目录'**
  String get remoteFile_unzipHere;

  /// remoteFile_compressZip
  ///
  /// In zh, this message translates to:
  /// **'压缩为 ZIP'**
  String get remoteFile_compressZip;

  /// No description provided for @clusterHome_monitorAssigned.
  ///
  /// In zh, this message translates to:
  /// **'已指定监控节点：{name}'**
  String clusterHome_monitorAssigned(String name);

  /// No description provided for @clusterHome_nodeCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 台节点'**
  String clusterHome_nodeCount(int count);

  /// No description provided for @clusterHome_systemInfo.
  ///
  /// In zh, this message translates to:
  /// **'系统：{sys}{ver}'**
  String clusterHome_systemInfo(String sys, String ver);

  /// No description provided for @clusterInstances_cannotOpenDetail.
  ///
  /// In zh, this message translates to:
  /// **'无法打开详情: {e}'**
  String clusterInstances_cannotOpenDetail(String e);

  /// No description provided for @clusterInstances_nodeOf.
  ///
  /// In zh, this message translates to:
  /// **'节点：{name}'**
  String clusterInstances_nodeOf(String name);

  /// No description provided for @clusterInstances_crashLine.
  ///
  /// In zh, this message translates to:
  /// **'崩溃 {count} 次 · 上次同步 {sync}'**
  String clusterInstances_crashLine(int count, String sync);

  /// No description provided for @clusterContainer_onlineWith.
  ///
  /// In zh, this message translates to:
  /// **'在线 · {runtime}'**
  String clusterContainer_onlineWith(String runtime);

  /// No description provided for @clusterOrch_replicaStat.
  ///
  /// In zh, this message translates to:
  /// **'{running}/{desired} 副本 · 在线 {players}（均 {avg}）'**
  String clusterOrch_replicaStat(
    int running,
    int desired,
    int players,
    String avg,
  );

  /// No description provided for @clusterOrch_scaleTarget.
  ///
  /// In zh, this message translates to:
  /// **'目标 {target}/副本 · 阈值 {down}~{up}'**
  String clusterOrch_scaleTarget(int target, int down, int up);

  /// No description provided for @remoteInstance_downloadedTo.
  ///
  /// In zh, this message translates to:
  /// **'已下载到 {path}'**
  String remoteInstance_downloadedTo(String path);

  /// market_typePlugin
  ///
  /// In zh, this message translates to:
  /// **'插件'**
  String get market_typePlugin;

  /// market_sortRelevance
  ///
  /// In zh, this message translates to:
  /// **'相关度'**
  String get market_sortRelevance;

  /// market_sortDownloads
  ///
  /// In zh, this message translates to:
  /// **'下载量'**
  String get market_sortDownloads;

  /// market_sortFollows
  ///
  /// In zh, this message translates to:
  /// **'关注数'**
  String get market_sortFollows;

  /// market_sortNewest
  ///
  /// In zh, this message translates to:
  /// **'最新发布'**
  String get market_sortNewest;

  /// market_sortUpdated
  ///
  /// In zh, this message translates to:
  /// **'最近更新'**
  String get market_sortUpdated;

  /// market_searchHint
  ///
  /// In zh, this message translates to:
  /// **'搜索 Mod / 插件...'**
  String get market_searchHint;

  /// market_type
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get market_type;

  /// market_sort
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get market_sort;

  /// market_loader
  ///
  /// In zh, this message translates to:
  /// **'核心'**
  String get market_loader;

  /// market_all
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get market_all;

  /// market_gameVersion
  ///
  /// In zh, this message translates to:
  /// **'游戏版本'**
  String get market_gameVersion;

  /// market_noResults
  ///
  /// In zh, this message translates to:
  /// **'未找到相关项目'**
  String get market_noResults;

  /// market_downloads
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get market_downloads;

  /// market_stars
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get market_stars;

  /// hangar_downloadRejected
  ///
  /// In zh, this message translates to:
  /// **'下载被拒绝：文件名包含非法路径字符'**
  String get hangar_downloadRejected;

  /// hangar_viewPath
  ///
  /// In zh, this message translates to:
  /// **'查看路径'**
  String get hangar_viewPath;

  /// hangar_description
  ///
  /// In zh, this message translates to:
  /// **'描述'**
  String get hangar_description;

  /// hangar_notFound
  ///
  /// In zh, this message translates to:
  /// **'未找到项目'**
  String get hangar_notFound;

  /// hangar_downloads
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get hangar_downloads;

  /// hangar_stars
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get hangar_stars;

  /// hangar_platform
  ///
  /// In zh, this message translates to:
  /// **'平台'**
  String get hangar_platform;

  /// mod_downloadRejected
  ///
  /// In zh, this message translates to:
  /// **'下载被拒绝：文件名为空或包含非法路径字符'**
  String get mod_downloadRejected;

  /// mod_openDirectory
  ///
  /// In zh, this message translates to:
  /// **'打开目录'**
  String get mod_openDirectory;

  /// mod_notFound
  ///
  /// In zh, this message translates to:
  /// **'未找到项目'**
  String get mod_notFound;

  /// mod_description
  ///
  /// In zh, this message translates to:
  /// **'描述'**
  String get mod_description;

  /// mod_versionList
  ///
  /// In zh, this message translates to:
  /// **'版本列表'**
  String get mod_versionList;

  /// mod_downloads
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get mod_downloads;

  /// mod_follows
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get mod_follows;

  /// pluginsUI_empty
  ///
  /// In zh, this message translates to:
  /// **'暂无插件 / Mod'**
  String get pluginsUI_empty;

  /// pluginsUI_emptyHint
  ///
  /// In zh, this message translates to:
  /// **'将插件放入 plugins/、Mod 放入 mods/ 后重新扫描'**
  String get pluginsUI_emptyHint;

  /// pluginsUI_sectionPlugins
  ///
  /// In zh, this message translates to:
  /// **'插件'**
  String get pluginsUI_sectionPlugins;

  /// pluginsUI_sectionMods
  ///
  /// In zh, this message translates to:
  /// **'Mod'**
  String get pluginsUI_sectionMods;

  /// pluginsUI_kindPlugin
  ///
  /// In zh, this message translates to:
  /// **'插件'**
  String get pluginsUI_kindPlugin;

  /// pluginsUI_noConfig
  ///
  /// In zh, this message translates to:
  /// **'无配置'**
  String get pluginsUI_noConfig;

  /// pluginsUI_configOnly
  ///
  /// In zh, this message translates to:
  /// **'仅配置'**
  String get pluginsUI_configOnly;

  /// download_title
  ///
  /// In zh, this message translates to:
  /// **'下载核心'**
  String get download_title;

  /// download_step1
  ///
  /// In zh, this message translates to:
  /// **'第一步 · 选择核心与版本'**
  String get download_step1;

  /// download_source
  ///
  /// In zh, this message translates to:
  /// **'下载来源'**
  String get download_source;

  /// download_mslSource
  ///
  /// In zh, this message translates to:
  /// **'MSL 镜像源'**
  String get download_mslSource;

  /// download_mslAttribution
  ///
  /// In zh, this message translates to:
  /// **'本服务由 MSL 开服器提供'**
  String get download_mslAttribution;

  /// download_serverCore
  ///
  /// In zh, this message translates to:
  /// **'服务器核心'**
  String get download_serverCore;

  /// download_selectCore
  ///
  /// In zh, this message translates to:
  /// **'请选择核心'**
  String get download_selectCore;

  /// download_serverVersion
  ///
  /// In zh, this message translates to:
  /// **'服务器版本'**
  String get download_serverVersion;

  /// download_selectCoreFirst
  ///
  /// In zh, this message translates to:
  /// **'请先选择核心'**
  String get download_selectCoreFirst;

  /// download_noVersionsForCore
  ///
  /// In zh, this message translates to:
  /// **'该核心暂无可用版本'**
  String get download_noVersionsForCore;

  /// download_selectVersion
  ///
  /// In zh, this message translates to:
  /// **'请选择版本'**
  String get download_selectVersion;

  /// download_nextStep
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get download_nextStep;

  /// download_scenario
  ///
  /// In zh, this message translates to:
  /// **'适用场景'**
  String get download_scenario;

  /// No description provided for @download_scenarioWithCategory.
  ///
  /// In zh, this message translates to:
  /// **'{scenario}（{category}）'**
  String download_scenarioWithCategory(String scenario, String category);

  /// download_loadFailed
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get download_loadFailed;

  /// download_description
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get download_description;

  /// download_downloadFailed
  ///
  /// In zh, this message translates to:
  /// **'下载失败'**
  String get download_downloadFailed;

  /// download_step2
  ///
  /// In zh, this message translates to:
  /// **'第二步 · 下载核心文件'**
  String get download_step2;

  /// download_downloadingHint
  ///
  /// In zh, this message translates to:
  /// **'正在下载…请勿离开'**
  String get download_downloadingHint;

  /// download_step3
  ///
  /// In zh, this message translates to:
  /// **'第三步 · 编辑启动命令'**
  String get download_step3;

  /// download_command
  ///
  /// In zh, this message translates to:
  /// **'启动命令'**
  String get download_command;

  /// download_finishCreate
  ///
  /// In zh, this message translates to:
  /// **'完成并创建实例'**
  String get download_finishCreate;

  /// dbScreen_saved
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get dbScreen_saved;

  /// dbScreen_deleteTitle
  ///
  /// In zh, this message translates to:
  /// **'删除连接'**
  String get dbScreen_deleteTitle;

  /// dbScreen_deleted
  ///
  /// In zh, this message translates to:
  /// **'已删除'**
  String get dbScreen_deleted;

  /// dbScreen_connectionFailed
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get dbScreen_connectionFailed;

  /// dbScreen_title
  ///
  /// In zh, this message translates to:
  /// **'数据库'**
  String get dbScreen_title;

  /// dbScreen_addConnection
  ///
  /// In zh, this message translates to:
  /// **'添加连接'**
  String get dbScreen_addConnection;

  /// dbScreen_manageHint
  ///
  /// In zh, this message translates to:
  /// **'管理 MySQL / MariaDB / PostgreSQL / Redis 服务器连接'**
  String get dbScreen_manageHint;

  /// dbScreen_emptyTitle
  ///
  /// In zh, this message translates to:
  /// **'还没有数据库连接'**
  String get dbScreen_emptyTitle;

  /// dbScreen_emptyAddHint
  ///
  /// In zh, this message translates to:
  /// **'点击右上角添加'**
  String get dbScreen_emptyAddHint;

  /// dbScreen_connect
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get dbScreen_connect;

  /// dbScreen_nameRequired
  ///
  /// In zh, this message translates to:
  /// **'请输入名称'**
  String get dbScreen_nameRequired;

  /// dbScreen_hostRequired
  ///
  /// In zh, this message translates to:
  /// **'请输入主机地址'**
  String get dbScreen_hostRequired;

  /// dbScreen_portRange
  ///
  /// In zh, this message translates to:
  /// **'端口需在 1-65535 之间'**
  String get dbScreen_portRange;

  /// dbScreen_editTitle
  ///
  /// In zh, this message translates to:
  /// **'编辑连接'**
  String get dbScreen_editTitle;

  /// dbScreen_host
  ///
  /// In zh, this message translates to:
  /// **'主机'**
  String get dbScreen_host;

  /// dbScreen_hostHint
  ///
  /// In zh, this message translates to:
  /// **'例如 127.0.0.1'**
  String get dbScreen_hostHint;

  /// dbScreen_port
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get dbScreen_port;

  /// dbScreen_usernameOptional
  ///
  /// In zh, this message translates to:
  /// **'用户名（可选）'**
  String get dbScreen_usernameOptional;

  /// dbScreen_passwordOptional
  ///
  /// In zh, this message translates to:
  /// **'密码（可选）'**
  String get dbScreen_passwordOptional;

  /// dbScreen_databaseNameOptional
  ///
  /// In zh, this message translates to:
  /// **'数据库名（可选）'**
  String get dbScreen_databaseNameOptional;

  /// dbScreen_useSsl
  ///
  /// In zh, this message translates to:
  /// **'使用 SSL 连接'**
  String get dbScreen_useSsl;

  /// dbScreen_sslSubtitle
  ///
  /// In zh, this message translates to:
  /// **'加密传输（MySQL/MariaDB/PostgreSQL/Redis，验证服务器证书）'**
  String get dbScreen_sslSubtitle;

  /// nodes_title
  ///
  /// In zh, this message translates to:
  /// **'节点'**
  String get nodes_title;

  /// nodes_refreshStatus
  ///
  /// In zh, this message translates to:
  /// **'刷新状态'**
  String get nodes_refreshStatus;

  /// nodes_addNode
  ///
  /// In zh, this message translates to:
  /// **'添加节点'**
  String get nodes_addNode;

  /// nodes_empty
  ///
  /// In zh, this message translates to:
  /// **'还没有节点，点击右上角 + 添加'**
  String get nodes_empty;

  /// nodes_emptyHint
  ///
  /// In zh, this message translates to:
  /// **'MCSM：连接 MCSManager 面板\nNode：本地 Go 语言节点（node/ 目录）'**
  String get nodes_emptyHint;

  /// nodes_daemonRunning
  ///
  /// In zh, this message translates to:
  /// **'本地节点守护进程正在运行'**
  String get nodes_daemonRunning;

  /// nodes_daemonHint
  ///
  /// In zh, this message translates to:
  /// **'提示：Node 类型节点需要先运行 node/ 目录构建的 irix-node 服务'**
  String get nodes_daemonHint;

  /// No description provided for @hangar_installedToNode.
  ///
  /// In zh, this message translates to:
  /// **'已安装到节点 {nodeName} 的 plugins/'**
  String hangar_installedToNode(String nodeName);

  /// No description provided for @hangar_downloadedTo.
  ///
  /// In zh, this message translates to:
  /// **'已下载到 {path}'**
  String hangar_downloadedTo(String path);

  /// No description provided for @hangar_directory.
  ///
  /// In zh, this message translates to:
  /// **'目录: {path}'**
  String hangar_directory(String path);

  /// No description provided for @hangar_downloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败: {error}'**
  String hangar_downloadFailed(String error);

  /// No description provided for @hangar_publishedOn.
  ///
  /// In zh, this message translates to:
  /// **'发布于 {date}'**
  String hangar_publishedOn(String date);

  /// No description provided for @hangar_versionList.
  ///
  /// In zh, this message translates to:
  /// **'版本列表 ({count})'**
  String hangar_versionList(int count);

  /// No description provided for @mod_downloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败: {error}'**
  String mod_downloadFailed(String error);

  /// No description provided for @mod_downloadedTo.
  ///
  /// In zh, this message translates to:
  /// **'已下载到 {path}'**
  String mod_downloadedTo(String path);

  /// No description provided for @mod_installedToNode.
  ///
  /// In zh, this message translates to:
  /// **'已安装到节点 {nodeName} 的 {dir}/'**
  String mod_installedToNode(String nodeName, String dir);

  /// No description provided for @mod_directory.
  ///
  /// In zh, this message translates to:
  /// **'目录: {path}'**
  String mod_directory(String path);

  /// No description provided for @mod_publishedOn.
  ///
  /// In zh, this message translates to:
  /// **'发布于 {date}'**
  String mod_publishedOn(String date);

  /// No description provided for @pluginsUI_noConfigFiles.
  ///
  /// In zh, this message translates to:
  /// **'{name} 暂无可管理的配置文件'**
  String pluginsUI_noConfigFiles(String name);

  /// No description provided for @download_downloaded.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {size}'**
  String download_downloaded(String size);

  /// No description provided for @download_speed.
  ///
  /// In zh, this message translates to:
  /// **'速度 {speed}/s'**
  String download_speed(String speed);

  /// No description provided for @download_coreFile.
  ///
  /// In zh, this message translates to:
  /// **'核心文件：{fileName}'**
  String download_coreFile(String fileName);

  /// No description provided for @dbScreen_deleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除 \"{name}\"？此操作不会影响远程服务器。'**
  String dbScreen_deleteConfirm(String name);

  /// newInstance_download
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get newInstance_download;

  /// newInstance_downloadDesc
  ///
  /// In zh, this message translates to:
  /// **'自动下载核心并新建服务器实例'**
  String get newInstance_downloadDesc;

  /// newInstance_import
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get newInstance_import;

  /// newInstance_importDesc
  ///
  /// In zh, this message translates to:
  /// **'导入一个服务器核心新建服务器实例'**
  String get newInstance_importDesc;

  /// importCore_title
  ///
  /// In zh, this message translates to:
  /// **'导入核心'**
  String get importCore_title;

  /// importCore_coreFile
  ///
  /// In zh, this message translates to:
  /// **'核心文件'**
  String get importCore_coreFile;

  /// importCore_coreFileHint
  ///
  /// In zh, this message translates to:
  /// **'选择 .jar 核心文件'**
  String get importCore_coreFileHint;

  /// importCore_browse
  ///
  /// In zh, this message translates to:
  /// **'浏览'**
  String get importCore_browse;

  /// importCore_rootPath
  ///
  /// In zh, this message translates to:
  /// **'服务器根目录路径'**
  String get importCore_rootPath;

  /// importCore_rootPathHint
  ///
  /// In zh, this message translates to:
  /// **'选择或输入服务器根目录'**
  String get importCore_rootPathHint;

  /// importCore_startCommandHint
  ///
  /// In zh, this message translates to:
  /// **'java -Xmx2G -jar <jar文件名> nogui'**
  String get importCore_startCommandHint;

  /// importCore_creating
  ///
  /// In zh, this message translates to:
  /// **'创建中…'**
  String get importCore_creating;

  /// importCore_createInstance
  ///
  /// In zh, this message translates to:
  /// **'创建实例'**
  String get importCore_createInstance;

  /// importCore_desc
  ///
  /// In zh, this message translates to:
  /// **'导入已下载的核心 .jar 文件并基于它创建一个新实例。'**
  String get importCore_desc;

  /// importCore_fillAllFields
  ///
  /// In zh, this message translates to:
  /// **'请填写核心文件、服务器根目录路径与启动命令'**
  String get importCore_fillAllFields;

  /// importInstance_title
  ///
  /// In zh, this message translates to:
  /// **'导入实例'**
  String get importInstance_title;

  /// importInstance_instanceName
  ///
  /// In zh, this message translates to:
  /// **'实例名称'**
  String get importInstance_instanceName;

  /// importInstance_instanceNameHint
  ///
  /// In zh, this message translates to:
  /// **'留空则自动分配随机名称'**
  String get importInstance_instanceNameHint;

  /// importInstance_rootPath
  ///
  /// In zh, this message translates to:
  /// **'服务器根目录路径'**
  String get importInstance_rootPath;

  /// importInstance_rootPathHint
  ///
  /// In zh, this message translates to:
  /// **'选择或输入服务器根目录'**
  String get importInstance_rootPathHint;

  /// importInstance_startCommandHint
  ///
  /// In zh, this message translates to:
  /// **'java -Xmx2G -jar server.jar nogui'**
  String get importInstance_startCommandHint;

  /// importInstance_browse
  ///
  /// In zh, this message translates to:
  /// **'浏览'**
  String get importInstance_browse;

  /// importInstance_creating
  ///
  /// In zh, this message translates to:
  /// **'创建中…'**
  String get importInstance_creating;

  /// importInstance_createInstance
  ///
  /// In zh, this message translates to:
  /// **'创建实例'**
  String get importInstance_createInstance;

  /// importInstance_desc
  ///
  /// In zh, this message translates to:
  /// **'导入一个已存在的服务器目录，使用其原有文件结构。'**
  String get importInstance_desc;

  /// importInstance_fillRequired
  ///
  /// In zh, this message translates to:
  /// **'请填写服务器根目录路径与启动命令'**
  String get importInstance_fillRequired;

  /// trash_title
  ///
  /// In zh, this message translates to:
  /// **'回收站'**
  String get trash_title;

  /// trash_purge
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get trash_purge;

  /// trash_empty
  ///
  /// In zh, this message translates to:
  /// **'回收站为空'**
  String get trash_empty;

  /// trash_purgeTitle
  ///
  /// In zh, this message translates to:
  /// **'清空回收站'**
  String get trash_purgeTitle;

  /// trash_purgeAllConfirm
  ///
  /// In zh, this message translates to:
  /// **'确定要永久删除所有实例回收站中的文件吗？此操作不可撤销。'**
  String get trash_purgeAllConfirm;

  /// trash_purgeScopeConfirm
  ///
  /// In zh, this message translates to:
  /// **'确定要永久删除该实例回收站中的所有文件吗？此操作不可撤销。'**
  String get trash_purgeScopeConfirm;

  /// trash_purged
  ///
  /// In zh, this message translates to:
  /// **'回收站已清空'**
  String get trash_purged;

  /// trash_restore
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get trash_restore;

  /// trash_permanentlyDelete
  ///
  /// In zh, this message translates to:
  /// **'永久删除'**
  String get trash_permanentlyDelete;

  /// archive_selectExtractDir
  ///
  /// In zh, this message translates to:
  /// **'选择解压目标文件夹'**
  String get archive_selectExtractDir;

  /// archive_extractTo
  ///
  /// In zh, this message translates to:
  /// **'解压到...'**
  String get archive_extractTo;

  /// archive_cannotOpen
  ///
  /// In zh, this message translates to:
  /// **'无法打开压缩文件'**
  String get archive_cannotOpen;

  /// archive_invalidArchiveHint
  ///
  /// In zh, this message translates to:
  /// **'请确认该文件是有效的 ZIP/JAR 归档文件'**
  String get archive_invalidArchiveHint;

  /// archive_emptyArchive
  ///
  /// In zh, this message translates to:
  /// **'归档文件为空'**
  String get archive_emptyArchive;

  /// archive_colName
  ///
  /// In zh, this message translates to:
  /// **'文件名'**
  String get archive_colName;

  /// archive_colSize
  ///
  /// In zh, this message translates to:
  /// **'大小'**
  String get archive_colSize;

  /// archive_colModified
  ///
  /// In zh, this message translates to:
  /// **'修改时间'**
  String get archive_colModified;

  /// textEditor_undo
  ///
  /// In zh, this message translates to:
  /// **'撤回'**
  String get textEditor_undo;

  /// textEditor_cannotRead
  ///
  /// In zh, this message translates to:
  /// **'无法读取文件'**
  String get textEditor_cannotRead;

  /// onboarding_title
  ///
  /// In zh, this message translates to:
  /// **'IriX'**
  String get onboarding_title;

  /// onboarding_create
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get onboarding_create;

  /// onboarding_createDesc
  ///
  /// In zh, this message translates to:
  /// **'新建一个MC服务器实例'**
  String get onboarding_createDesc;

  /// onboarding_import
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get onboarding_import;

  /// onboarding_importDesc
  ///
  /// In zh, this message translates to:
  /// **'导入一个MC服务器实例'**
  String get onboarding_importDesc;

  /// remoteTab_restoreFailed
  ///
  /// In zh, this message translates to:
  /// **'恢复失败'**
  String get remoteTab_restoreFailed;

  /// remoteTab_snapshotFailed
  ///
  /// In zh, this message translates to:
  /// **'快照失败'**
  String get remoteTab_snapshotFailed;

  /// remoteTab_unzippingOnNode
  ///
  /// In zh, this message translates to:
  /// **'节点端解压中…'**
  String get remoteTab_unzippingOnNode;

  /// remoteTab_uploadingBackup
  ///
  /// In zh, this message translates to:
  /// **'上传备份…'**
  String get remoteTab_uploadingBackup;

  /// No description provided for @trash_purgeFailed.
  ///
  /// In zh, this message translates to:
  /// **'清空失败: {e}'**
  String trash_purgeFailed(String e);

  /// No description provided for @trash_restored.
  ///
  /// In zh, this message translates to:
  /// **'已恢复 \"{path}\"'**
  String trash_restored(String path);

  /// No description provided for @trash_restoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败: {e}'**
  String trash_restoreFailed(String e);

  /// No description provided for @trash_permanentlyDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已永久删除 \"{path}\"'**
  String trash_permanentlyDeleted(String path);

  /// No description provided for @trash_deleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败: {e}'**
  String trash_deleteFailed(String e);

  /// No description provided for @trash_deletedAt.
  ///
  /// In zh, this message translates to:
  /// **'删除于 {date}'**
  String trash_deletedAt(String date);

  /// No description provided for @trash_groupHeader.
  ///
  /// In zh, this message translates to:
  /// **'{label} · {count} 项'**
  String trash_groupHeader(String label, int count);

  /// No description provided for @trash_today.
  ///
  /// In zh, this message translates to:
  /// **'今天 {time}'**
  String trash_today(String time);

  /// No description provided for @trash_yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天 {time}'**
  String trash_yesterday(String time);

  /// No description provided for @archive_extracted.
  ///
  /// In zh, this message translates to:
  /// **'已解压: {name}'**
  String archive_extracted(String name);

  /// No description provided for @archive_extractFailed.
  ///
  /// In zh, this message translates to:
  /// **'解压失败: {e}'**
  String archive_extractFailed(String e);

  /// No description provided for @archive_entryCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个条目'**
  String archive_entryCount(int count);

  /// No description provided for @archive_fileNotFound.
  ///
  /// In zh, this message translates to:
  /// **'文件不存在: {path}'**
  String archive_fileNotFound(String path);

  /// common_download
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get common_download;

  /// No description provided for @remoteFile_downloadedTo.
  ///
  /// In zh, this message translates to:
  /// **'已下载到 {path}'**
  String remoteFile_downloadedTo(String path);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
