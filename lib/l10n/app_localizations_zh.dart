// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get common_save => '保存';

  @override
  String get common_cancel => '取消';

  @override
  String get common_delete => '删除';

  @override
  String get common_edit => '编辑';

  @override
  String get common_refresh => '刷新';

  @override
  String get common_retry => '重试';

  @override
  String get common_confirm => '确定';

  @override
  String get common_close => '关闭';

  @override
  String get common_add => '添加';

  @override
  String get common_search => '搜索';

  @override
  String get common_name => '名称';

  @override
  String get common_status => '状态';

  @override
  String get common_action => '操作';

  @override
  String get common_loading => '加载中…';

  @override
  String get common_error => '错误';

  @override
  String get common_success => '成功';

  @override
  String get common_copy => '复制';

  @override
  String get common_remove => '移除';

  @override
  String get common_ok => '好的';

  @override
  String get common_back => '返回';

  @override
  String get common_reset => '重置';

  @override
  String get common_apply => '应用';

  @override
  String get common_confirmDelete => '确认删除';

  @override
  String get common_open => '打开';

  @override
  String get common_enabled => '已启用';

  @override
  String get common_disabled => '已关闭';

  @override
  String common_deleteItemConfirm(String name) {
    return '确定删除「$name」吗？此操作不可撤销。';
  }

  @override
  String common_itemCount(int count) {
    return '$count 个项目';
  }

  @override
  String common_timeMinutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String common_timeHoursAgo(int hours) {
    return '$hours 小时前';
  }

  @override
  String common_timeDaysAgo(int days) {
    return '$days 天前';
  }

  @override
  String common_timeMonthsAgo(int months) {
    return '$months 个月前';
  }

  @override
  String common_timeYearsAgo(int years) {
    return '$years 年前';
  }

  @override
  String get common_language => '界面语言';

  @override
  String get common_languageSystem => '跟随系统';

  @override
  String get common_languageChinese => '简体中文';

  @override
  String get common_languageEnglish => 'English';

  @override
  String get settings_title => '设置';

  @override
  String get settings_multiMode => '多机管理模式';

  @override
  String get settings_multiModeOn => '实例分布到多个节点，自动分配资源、崩溃迁移与数据同步';

  @override
  String get settings_singleMode => '单机模式：实例在本机运行';

  @override
  String get settings_multiModeHint => '多机模式需至少 2 个节点，可在「主页」中添加。';

  @override
  String get settings_vault => 'Vault 加密保险库';

  @override
  String get settings_vaultOn => '已启用：节点详情 / 解锁 / 初始化 / 证书绑定等保险库能力可用';

  @override
  String get settings_vaultOff => '关闭：不展示保险库相关能力（节点需以 -vault 开启并配置 TLS）';

  @override
  String settings_downloadThreads(int count) {
    return '下载线程数: $count';
  }

  @override
  String get settings_downloadThreadsHint => '多线程分片断点续传；服务端不支持 Range 时自动回退单线程。';

  @override
  String settings_dbPageSize(int count) {
    return '数据库每页行数: $count';
  }

  @override
  String get settings_dbPageSizeHint => '浏览数据库表数据时每页显示的行数。';

  @override
  String get settings_font => '字体';

  @override
  String get settings_fontHint =>
      '终端（控制台 / 日志 / 代码）与其余界面字体分开设置；其余界面默认 MiSans，终端默认 JetBrains Mono。';

  @override
  String get settings_uiFont => '界面字体';

  @override
  String get settings_terminalFont => '终端字体';

  @override
  String get settings_fontFallbackHint =>
      '未安装的系统字体（如 JetBrains Mono）会自动回退到默认字体。';

  @override
  String get node_renameTitle => '重命名节点';

  @override
  String get node_nameHint => '节点名称';

  @override
  String node_deleteConfirmTitle(String name) {
    return '删除节点「$name」？';
  }

  @override
  String get node_deleteConfirmContent => '仅删除本地保存的节点信息，不会影响服务器上的数据。';

  @override
  String get node_online => '在线';

  @override
  String get node_offline => '离线';

  @override
  String get node_renameMenu => '重命名';

  @override
  String get node_deleteMenu => '删除';

  @override
  String get container_tabContainers => '容器';

  @override
  String get container_tabRelease => '发行';

  @override
  String get container_tabForward => '转发';

  @override
  String get container_tabSettings => '设置';

  @override
  String get container_tabImages => '镜像';

  @override
  String get container_tabVolumes => '卷';

  @override
  String get container_tabNetworks => '网络';

  @override
  String get container_jailList => 'Jail 列表';

  @override
  String get container_containerList => '容器列表';

  @override
  String get container_import => '导入';

  @override
  String get container_createJail => '创建 Jail';

  @override
  String get container_createContainer => '创建容器';

  @override
  String get container_noJails => '暂无 Jail';

  @override
  String get container_noContainers => '暂无容器';

  @override
  String get container_bootstrappedReleases => '已 Bootstrap 的发行版';

  @override
  String get container_imageList => '镜像列表';

  @override
  String get container_bootstrap => 'Bootstrap';

  @override
  String get container_pull => '拉取';

  @override
  String get container_build => '构建';

  @override
  String get container_noReleases => '暂无发行版，点击 Bootstrap 拉取（如 14.2-RELEASE）';

  @override
  String get container_noImages => '暂无镜像';

  @override
  String get container_deleteImage => '删除镜像';

  @override
  String get container_bootstrapRelease => 'Bootstrap 发行版';

  @override
  String get container_pullImage => '拉取镜像';

  @override
  String get container_releaseName => '发行版名称';

  @override
  String get container_imageName => '镜像名称';

  @override
  String get container_releaseNameHint => '如 14.2-RELEASE';

  @override
  String get container_imageNameHint => '如 itzg/minecraft-server:latest';

  @override
  String get container_rdrRules => '端口转发规则（bastille rdr）';

  @override
  String get container_addForward => '添加转发';

  @override
  String get container_noRdrRules => '暂无转发规则';

  @override
  String get container_deleteForward => '删除转发';

  @override
  String get container_forwardDeleted => '转发规则已删除';

  @override
  String get container_forwardAdded => '转发规则已添加';

  @override
  String get container_deleteVolume => '删除卷';

  @override
  String get container_volumeList => '卷列表';

  @override
  String get container_networkList => '网络列表';

  @override
  String get container_noVolumes => '暂无卷';

  @override
  String get container_noNetworks => '暂无网络';

  @override
  String get container_start => '启动';

  @override
  String get container_stop => '停止';

  @override
  String get container_manageDetail => '管理（详情）';

  @override
  String get container_moreActions => '更多操作';

  @override
  String get container_restart => '重启';

  @override
  String get container_clone => '克隆';

  @override
  String get container_resourceLimit => '资源限制';

  @override
  String get container_exportArchive => '导出归档';

  @override
  String get container_status => '状态';

  @override
  String get container_image => '镜像';

  @override
  String get container_ports => '端口';

  @override
  String get container_createdAt => '创建时间';

  @override
  String get container_confirmOperation => '确认操作';

  @override
  String get container_exportSavedPath => '归档已保存到节点上的路径：';

  @override
  String get container_redetect => '重新检测';

  @override
  String get container_envUnavailableBastille =>
      'Bastille 运行在 FreeBSD 节点上：请在「节点管理」中添加在线 FreeBSD 节点（irix-node）后，从节点详情页的「容器」Tab 管理 jail。';

  @override
  String get container_envUnavailableDocker =>
      '本机使用 Docker 环境：安装并启动 Docker Desktop（或安装 docker CLI）后点击「重新检测」即可使用全部容器功能。';

  @override
  String get container_nameHelperBastille => '仅字母、数字、- 和 _，不能为纯数字';

  @override
  String get container_release => '发行版';

  @override
  String get container_imageHelper => '如 itzg/minecraft-server:latest';

  @override
  String get container_releaseHelper => '如 14.2-RELEASE（需先 Bootstrap）';

  @override
  String get container_ipAddress => 'IP 地址';

  @override
  String get container_ipHelper => '含前缀，如 192.168.1.50/24';

  @override
  String get container_jailType => 'Jail 类型';

  @override
  String get container_jailTypeThin => 'thin — 符号链接样板（默认）';

  @override
  String get container_jailTypeThick => 'thick — 厚容器（-T 解压样板）';

  @override
  String get container_jailTypeClone => 'clone — 克隆现有发行版';

  @override
  String get container_jailTypeEmpty => 'empty — 空容器（-E，仅需名称）';

  @override
  String get container_jailTypeLinux => 'linux — Linux Jail（-L）';

  @override
  String get container_vnetMode => 'VNET 模式';

  @override
  String get container_vnetModeNone => '不使用 VNET（共享宿主网络）';

  @override
  String get container_vnetModeVnet => 'VNET（-V，网卡须为物理网卡）';

  @override
  String get container_vnetModeBridge => '桥接 VNET（-B，网卡须为桥接网卡）';

  @override
  String get container_bridgeNic => '桥接网卡';

  @override
  String get container_physicalNic => '物理网卡';

  @override
  String get container_bridgeNicHint => '如 bridge0';

  @override
  String get container_physicalNicHint => '如 em0';

  @override
  String get container_portMapping => '端口映射';

  @override
  String get container_portMappingHelper => '宿主机端口:容器端口，多个用逗号分隔';

  @override
  String get container_portMappingHelperBastille =>
      '宿主机端口:jail 端口，多个用逗号分隔；创建后经 rdr 自动应用';

  @override
  String get container_dataMount => '数据目录挂载（nullfs）';

  @override
  String get container_volumeMount => '卷挂载';

  @override
  String get container_dataMountHelper => '宿主机路径:jail 内路径，多个用逗号分隔';

  @override
  String get container_volumeMountHelper => '宿主机路径:容器路径，多个用逗号分隔';

  @override
  String get container_envVars => '环境变量';

  @override
  String get container_envVarsHelper => '每行一个 KEY=VALUE，如 MEMORY=2G、EULA=TRUE';

  @override
  String get container_restartPolicy => '重启策略';

  @override
  String get container_restartNo => 'no — 不自动重启';

  @override
  String get container_restartUnlessStopped => 'unless-stopped — 退出自动重启';

  @override
  String get container_restartAlways => 'always — 总是重启';

  @override
  String get container_restartOnFailure => 'on-failure — 异常退出时重启';

  @override
  String get container_startCommand => '启动命令（留空用镜像默认）';

  @override
  String get container_workdir => '工作目录（留空默认）';

  @override
  String get container_workdirHelper => '如 /data —— 强制在挂载的数据目录内启动';

  @override
  String get container_memoryLimit => '内存上限（MB，留空不限）';

  @override
  String get container_cpuCores => 'CPU 核数（留空不限）';

  @override
  String get container_diskLimit => '磁盘上限（MB，留空不限）';

  @override
  String get container_diskLimitHelper => '依赖存储驱动支持 size 配额';

  @override
  String get container_diskLimitHelperBastille => 'ZFS 数据集配额';

  @override
  String get container_createHintBastille =>
      '提示：thin（默认）/ thick（-T）/ clone（-C）/ empty（-E，仅需名称）/ linux（-L）为互斥的创建方式；Linux Jail 不能与 VNET（-V/-B）同时使用；VNET 需先完成「设置」页的网络初始化，IP 必须含子网掩码。';

  @override
  String get container_enterJailName => '请填写 Jail 名称';

  @override
  String get container_nameAndImageRequired => '名称与镜像 / 发行版不能为空';

  @override
  String get container_jailNameRule => 'Jail 名仅允许字母、数字、- 和 _，且不能为纯数字';

  @override
  String get container_jailIpRequired => 'Bastille 创建 Jail 必须显式声明 IP 地址';

  @override
  String get container_linuxVnetConflict => 'Linux Jail（-L）不能与 VNET（-V/-B）同时使用';

  @override
  String get container_enterBridgeNic => '请填写桥接网卡名称';

  @override
  String get container_enterPhysicalNic => '请填写物理网卡名称';

  @override
  String get container_vnetIpMustContainMask =>
      'VNET Jail 的 IP 必须含子网掩码，如 192.168.1.50/24';

  @override
  String get container_newName => '新名称';

  @override
  String get container_notPureNumber => '不能为纯数字';

  @override
  String get container_newIp => '新 IP 地址（留空沿用源，需含前缀）';

  @override
  String get container_newIpHint => '如 192.168.1.51/24';

  @override
  String get container_resourceLimits => '资源限制';

  @override
  String get container_memoryLimitKeep => '内存上限（MB，留空不变）';

  @override
  String get container_cpuCoresKeep => 'CPU 核数（留空不变）';

  @override
  String get container_diskLimitKeep => '磁盘上限（MB，留空不变）';

  @override
  String get container_diskLimitKeepHelper => 'Docker 不支持热更新磁盘上限';

  @override
  String get container_jail => 'Jail';

  @override
  String get container_protocol => '协议';

  @override
  String get container_hostPort => '宿主机端口';

  @override
  String get container_jailPort => 'Jail 内端口';

  @override
  String get container_archivePath => '归档路径（节点上的归档文件）';

  @override
  String get container_archivePathHint =>
      '如 /usr/local/bastille/backups/xxx.txz';

  @override
  String get container_specifyRelease => '指定发行版（留空按归档内名称）';

  @override
  String get container_specifyReleaseHint => '如 14.2-RELEASE';

  @override
  String get container_skipChecksum => '跳过校验和验证（-f / --force）';

  @override
  String get container_importJail => '导入 Jail';

  @override
  String get container_setupDefaultTitle => '一键默认初始化';

  @override
  String get container_setupDefaultDesc =>
      '不带选项执行 bastille setup：自动配置 loopback（bastille0）、firewall 与 storage。多数场景足够使用。';

  @override
  String get container_setupDefaultRun => '执行 bastille setup';

  @override
  String get container_setupFirewallTitle => '防火墙（firewall）';

  @override
  String get container_setupFirewallDesc =>
      '配置 PF 防火墙：启用服务并生成默认 pf.conf —— 端口转发（bastille rdr）的前提。';

  @override
  String get container_setupFirewallRun => '执行 bastille setup firewall';

  @override
  String get container_setupVnetTitle => 'VNET 网络（vnet）';

  @override
  String get container_setupVnetDesc =>
      '为 VNET jail（-V）配置宿主网络。参数为可选项（部分版本为交互式，由服务端注入）。';

  @override
  String get container_setupVnetRun => '执行 bastille setup vnet';

  @override
  String get container_setupBridgeTitle => '桥接网络（bridge）';

  @override
  String get container_setupBridgeDesc =>
      '配置桥接网卡 —— 桥接 VNET jail（-B）的前提。需先在系统上创建 bridge 接口（如 ifconfig bridge create）。';

  @override
  String get container_setupBridgeRun => '执行 bastille setup bridge';

  @override
  String get container_setupSharedTitle => '共享网卡（shared）';

  @override
  String get container_setupSharedDesc =>
      '将指定网卡设为共享接口：create 未指定 INTERFACE 时默认使用。与 loopback 互斥（配置其一将禁用另一项）。';

  @override
  String get container_setupSharedRun => '执行 bastille setup shared';

  @override
  String get container_setupLinuxTitle => 'Linux Jail（linux）';

  @override
  String get container_setupLinuxDesc =>
      '初始化 Linuxulator —— 创建 Linux jail（-L）的前提：加载所需内核模块并安装 debootstrap 包。';

  @override
  String get container_setupLinuxRun => '执行 bastille setup linux';

  @override
  String get container_setupFieldExtIf => '外网网卡';

  @override
  String get container_setupFieldExtIfHint => '如 em0';

  @override
  String get container_setupFieldTunIf => '桥接网卡';

  @override
  String get container_setupFieldTunIfHint => '默认 bastille0';

  @override
  String get container_setupFieldAddr => '网段';

  @override
  String get container_setupFieldAddrHint => '如 10.99.0.0/24';

  @override
  String get container_setupFieldNic => '网卡';

  @override
  String get container_enterNicName => '请填写网卡名称';

  @override
  String get container_initDone => '初始化完成';

  @override
  String get container_initFailed => '初始化失败';

  @override
  String get container_buildImage => '构建镜像';

  @override
  String get container_tag => '标签';

  @override
  String get container_dockerfile => 'Dockerfile';

  @override
  String get container_buildContextNote =>
      '构建上下文为 stdin（与 MCSM dockerFile 一致）；需要 COPY 本地文件时请把文件放进镜像基础层。';

  @override
  String get container_startBuild => '开始构建';

  @override
  String get container_buildDone => '构建完成';

  @override
  String get container_buildFailed => '构建失败';

  @override
  String get container_building => '构建中...';

  @override
  String get container_waitingBuildOutput => '等待构建输出...';

  @override
  String get container_buildInBackground => '后台构建';

  @override
  String container_operationSuccess(String name) {
    return '操作成功：$name';
  }

  @override
  String container_created(String name) {
    return '已创建：$name';
  }

  @override
  String container_cloned(String name) {
    return '已克隆为：$name';
  }

  @override
  String container_limitsUpdated(String name) {
    return '资源限制已更新：$name';
  }

  @override
  String container_exportDone(String name) {
    return '导出完成：$name';
  }

  @override
  String container_importDone(String name) {
    return '导入完成：$name';
  }

  @override
  String container_buildTitle(String imageName) {
    return '构建 $imageName';
  }

  @override
  String container_envUnavailable(String name) {
    return '$name 不可用';
  }

  @override
  String container_envLabel(String name) {
    return '$name 环境';
  }

  @override
  String container_deleteConfirmContainer(String name) {
    return '确定删除容器 $name 吗？';
  }

  @override
  String container_deleteConfirmJail(String name) {
    return '确定删除 Jail $name 吗？';
  }

  @override
  String container_deleteVolumeConfirm(String name) {
    return '确定删除卷 $name 吗？';
  }

  @override
  String container_bootstrapSubmitted(String name) {
    return 'Bootstrap 任务已提交：$name（后台进行，稍后刷新列表）';
  }

  @override
  String container_pullDone(String name) {
    return '镜像拉取完成：$name';
  }

  @override
  String container_cloneTitle(String source) {
    return '克隆 $source';
  }

  @override
  String container_portFormatError(String port) {
    return '端口格式错误：$port（应为 宿主机:容器端口）';
  }

  @override
  String container_deleteImageConfirm(String tag) {
    return '确定删除镜像 $tag 吗？';
  }

  @override
  String container_rdrSubtitle(String proto, int hostPort, int containerPort) {
    return '$proto  宿主机 $hostPort → jail $containerPort';
  }

  @override
  String container_deleteForwardConfirm(
    String container,
    String proto,
    int hostPort,
    int containerPort,
  ) {
    return '确定删除 $container 的 $proto $hostPort→$containerPort 吗？';
  }

  @override
  String get addNode_title => '添加节点';

  @override
  String get addNode_fillAddressFirst => '请先填写地址';

  @override
  String get addNode_connectSuccess => '连接成功';

  @override
  String get addNode_connectFailed => '连接失败，请检查地址与 API Key';

  @override
  String get addNode_fillNodeAddress => '请填写节点地址';

  @override
  String get addNode_mcsmApiKeyRequired => 'MCSM 节点需要填写 API Key';

  @override
  String get addNode_remoteNodeKeyRequired => '远程 Node 节点必须填写密钥（仅本机回环地址可留空）';

  @override
  String get addNode_plaintextWarningTitle => '明文连接警告';

  @override
  String get addNode_plaintextWarningContent =>
      '该节点地址使用明文 HTTP（非 https），API 密钥与全部控制流量（含文件读写、命令执行）可被同网段窃听或篡改。';

  @override
  String get addNode_continueAnyway => '仍然继续';

  @override
  String get addNode_cancelledEnableHttps => '已取消：请为节点启用 HTTPS';

  @override
  String get addNode_prevStep => '上一步';

  @override
  String get addNode_nextStep => '下一步';

  @override
  String get addNode_testConnection => '测试连接';

  @override
  String get addNode_finish => '完成';

  @override
  String get addNode_stepType => '类型';

  @override
  String get addNode_stepName => '名称';

  @override
  String get addNode_stepKey => 'Key';

  @override
  String get addNode_selectType => '选择节点类型';

  @override
  String get addNode_mcsmSubtitle => '连接远程 MCSManager 面板\n需填写面板 API Key';

  @override
  String get addNode_nodeSubtitle => 'IriX 本地 Go 语言节点\n本机回环可免密钥，远程必须配置密钥';

  @override
  String get addNode_nameHint => '例如：我的面板 / 本地节点';

  @override
  String get addNode_address => '节点地址';

  @override
  String get addNode_mcsmAddressHelper =>
      'MCSManager 面板地址（含端口，如 23333）；远程建议使用 https';

  @override
  String get addNode_nodeAddressHelper => '本地节点守护进程地址（默认 12346 端口）';

  @override
  String get addNode_keyTitle => '节点 Key / API Key';

  @override
  String get addNode_mcsmKeyHint => 'MCSManager 用户 API Key';

  @override
  String get addNode_nodeKeyHint => '本地节点密钥（本机回环可留空）';

  @override
  String get addNode_copiedApiKey => '已复制 API Key';

  @override
  String get addNode_show => '显示';

  @override
  String get addNode_hide => '隐藏';

  @override
  String get addNode_mcsmKeyHelper => '在 MCSManager 面板「用户信息」中生成并复制';

  @override
  String get addNode_nodeKeyHelper => '远程节点必须填写密钥；仅 127.0.0.1 本机回环可留空';

  @override
  String get wizard_title => '首次配置引导';

  @override
  String get wizard_detectingNat => '正在检测 NAT 类型...';

  @override
  String get wizard_jdk8Note => 'Minecraft 1.16.5 及更早版本';

  @override
  String get wizard_jdk17Note => 'Minecraft 1.18+ 官方推荐';

  @override
  String get wizard_jdk21Note => 'Minecraft 1.20.5+ 推荐';

  @override
  String get wizard_jdk25Note => '最新 LTS（新版本服务端）';

  @override
  String get wizard_skipThisStep => '跳过此步';

  @override
  String get wizard_skipHint => '提示：可随时点击左上角「跳过」退出引导。';

  @override
  String get wizard_stepCreateInstance => '第 5 步 · 创建第一个实例';

  @override
  String get wizard_createInstanceDesc =>
      '下载或导入服务端核心，创建你的第一个 Minecraft 服务器实例。\n完成后将自动检测网络环境（NAT 类型）并给出内网穿透建议。';

  @override
  String get wizard_createFirstInstance => '创建第一个实例';

  @override
  String get wizard_noInstanceCreated => '还没有创建实例，请先完成实例创建';

  @override
  String get wizard_done => '引导完成！';

  @override
  String get wizard_natUncertain => '（结果不确定）';

  @override
  String get wizard_frpNeeded =>
      '你的网络处于 NAT 之后，好友可能无法直接连接服务器。\n是否需要配置 FRP 内网穿透，让外网玩家可以加入？';

  @override
  String get wizard_frpNotNeeded => '你的网络为公网直连，玩家可直接通过你的公网 IP 连接，无需内网穿透。';

  @override
  String get wizard_configureFrp => '需要，去配置 FRP';

  @override
  String get wizard_notNow => '暂不需要';

  @override
  String get wizard_adoptiumSource => '来自 Adoptium（Eclipse Temurin），下载约 200MB';

  @override
  String get wizard_unknownError => '未知错误';

  @override
  String get common_skip => '跳过';

  @override
  String wizard_totalSteps(int count) {
    return '共 $count 步，按顺序完成';
  }

  @override
  String wizard_installJdk(String name) {
    return '安装 $name';
  }

  @override
  String wizard_stepInstallJdk(int step, String name) {
    return '第 $step 步 · 安装 $name';
  }

  @override
  String wizard_startInstall(String name) {
    return '开始安装 $name';
  }

  @override
  String wizard_downloading(String name, String percent) {
    return '正在下载 $name ... $percent%';
  }

  @override
  String wizard_jdkInstalled(String name) {
    return '$name 已安装';
  }

  @override
  String wizard_installFailed(String error) {
    return '安装失败：$error';
  }

  @override
  String wizard_natType(String label) {
    return 'NAT 类型：$label';
  }

  @override
  String wizard_natMapped(String addr) {
    return '（$addr）';
  }

  @override
  String wizard_stepNumber(int index, String title) {
    return '$index. $title';
  }

  @override
  String get ai_stop => '停止';

  @override
  String get ai_clearConversation => '清空对话';

  @override
  String get ai_modelMcpSettings => '模型与 MCP 设置';

  @override
  String get ai_closePanel => '关闭 AI 面板';

  @override
  String get ai_addModel => '添加模型';

  @override
  String get ai_startChat => '开始和 AI 对话吧';

  @override
  String get ai_addModelFirst => '请先添加模型';

  @override
  String get ai_emptyHintHasModel => '可以让 AI 查看日志、分析报错、管理文件';

  @override
  String get ai_emptyHintNoModel =>
      '配置 OpenAI 兼容 API 模型（DeepSeek / OpenAI / Ollama 等）后即可使用';

  @override
  String get ai_thinking => 'AI 思考中…';

  @override
  String get ai_compressingHistory => '对话历史较长，正在压缩…';

  @override
  String get ai_requestSensitiveOp => 'AI 申请执行敏感操作';

  @override
  String get ai_deny => '拒绝';

  @override
  String get ai_allow => '允许';

  @override
  String get ai_viewLog => '看日志';

  @override
  String get ai_viewLogHint => '从实例 logs/ 文件夹挑选日志，解析后发送给 AI 分析';

  @override
  String get ai_pickLogFileTooltip => '选择日志文件（.log / .log.gz），解析后发送给 AI';

  @override
  String get ai_askHint => '向 AI 提问…';

  @override
  String get ai_addModelToChat => '请先添加模型再开始对话';

  @override
  String get ai_title => 'AI 助手';

  @override
  String get ai_milvusSaved => 'Milvus 连接已保存';

  @override
  String get ai_configMilvusFirst => '请先在上方配置 Milvus 连接再导入知识库';

  @override
  String get ai_addModelForEmbedding => '请先添加 AI 模型，知识库导入需要调用 Embedding 接口';

  @override
  String get ai_knowledgeImported => '知识库导入完成';

  @override
  String get ai_deleteDocumentTitle => '删除文档';

  @override
  String get ai_settingsTitle => 'AI 设置';

  @override
  String get ai_models => '模型';

  @override
  String get ai_noModelsYet => '还没有模型，点击右上角「添加模型」';

  @override
  String get ai_knowledgeBase => '知识库';

  @override
  String get ai_importing => '导入中…';

  @override
  String get ai_importDoc => '导入文档';

  @override
  String get ai_milvusConnection => '向量库（Milvus）连接';

  @override
  String get ai_milvusAddress => 'Milvus 地址';

  @override
  String get ai_milvusToken => 'Token（可选）';

  @override
  String get ai_milvusCollection => '集合名称';

  @override
  String get ai_saving => '保存中…';

  @override
  String get ai_saveConnection => '保存连接';

  @override
  String get ai_milvusNotConfigured => '尚未配置 Milvus 连接，导入/检索知识库前请先保存';

  @override
  String get ai_knowledgeEmpty =>
      '知识库为空。导入 .txt/.md 文档后，AI 对话时可检索知识库内容。\n（需在模型设置中配置 Embedding 模型，或留空使用同名模型）';

  @override
  String get ai_localMcpServer => '本地 MCP 服务器';

  @override
  String get ai_port => '端口';

  @override
  String get ai_mcpNotRunning => '未运行';

  @override
  String get ai_copyEndpoint => '复制端点';

  @override
  String get ai_mcpConfigNote =>
      '在 Claude Desktop / Cursor 等工具中配置（已启用鉴权，token 每次启动随机生成）：';

  @override
  String get ai_mcpConfigNoteTail => '点击复制按钮可直接复制完整配置。';

  @override
  String get ai_selectLogFile => '选择日志文件（logs/）';

  @override
  String get ai_noLogFiles => 'logs/ 文件夹内没有 .log / .log.gz 文件';

  @override
  String get ai_send => '发送';

  @override
  String get ai_deleteModelTitle => '删除模型';

  @override
  String get ai_mcpConfigCopied => '已复制 MCP 完整配置（含鉴权 token）';

  @override
  String get ai_milvusTokenHint => '未启用鉴权可留空';

  @override
  String get frp_title => 'FRP 端口映射';

  @override
  String get frp_logoutTitle => '退出登录';

  @override
  String get frp_logoutConfirm => '确定要退出登录吗？';

  @override
  String get frp_logout => '退出';

  @override
  String get frp_tunnelCreated => '隧道创建成功';

  @override
  String get frp_addTunnel => '添加隧道';

  @override
  String get frp_openfrpDisclaimer => '此项目由社区开发，OpenFrp 官方不负责除节点问题以外的技术支持';

  @override
  String get frp_log => '日志';

  @override
  String get frp_clearMemoryLog => '清空内存日志';

  @override
  String get frp_noLogYet => '暂无日志\n\n点击左侧隧道卡片可查看对应日志';

  @override
  String get frp_portMapping => '端口映射';

  @override
  String get frp_loginPromptCustom =>
      '配置你的 frps 服务器地址与认证 token，\n隧道保存在本地，一键启动 frpc 实现内网穿透。';

  @override
  String get frp_loginPromptChml =>
      '登录 ChmlFrp 账号后可为服务器创建端口映射（隧道），\n并在 IriX 内一键启动 frpc 实现内网穿透。';

  @override
  String get frp_loginPromptOpen =>
      '登录 OpenFrp 后可为服务器创建端口映射（隧道），\n并在 IriX 内一键启动 frpc 实现内网穿透。';

  @override
  String get frp_configFrps => '配置 frps';

  @override
  String get frp_login => '登录';

  @override
  String get frp_noAccountRegister => '还没有账号？去注册';

  @override
  String get frp_traffic => '剩余流量';

  @override
  String get frp_tunnels => '隧道';

  @override
  String get frp_status => '状态';

  @override
  String get frp_noTunnelsYet => '还没有隧道';

  @override
  String get frp_addTunnelHint => '点击右上角「添加隧道」创建端口映射';

  @override
  String get frp_online => '在线';

  @override
  String get frp_connecting => '连接中';

  @override
  String get frp_offline => '离线';

  @override
  String get frp_start => '启动';

  @override
  String get frp_stop => '停止';

  @override
  String get frp_encrypt => '加密';

  @override
  String get frp_compress => '压缩';

  @override
  String get frp_disabledLabel => '未启用';

  @override
  String get frp_requestingAuth => '正在请求授权…';

  @override
  String get frp_cannotOpenBrowser => '无法打开浏览器，请重试';

  @override
  String get frp_authorizedDecrypting => '已授权，正在解密…';

  @override
  String get frp_waitingBrowserAuth => '等待浏览器授权…';

  @override
  String get frp_authTimeout => '授权超时，请重试';

  @override
  String get frp_loginOpenFrpTitle => '登录 OpenFrp';

  @override
  String get frp_openfrpAuthDesc =>
      '点击下方按钮后将在浏览器中打开 OpenFrp 授权页：\n登录并在授权页确认后，IriX 会自动完成登录，无需复制任何内容。\n轮询最长 5 分钟，超时或取消需重新发起。';

  @override
  String get frp_authorizeInBrowser => '在浏览器中授权';

  @override
  String get frp_enterServerAddress => '请输入服务器地址';

  @override
  String get frp_configSelfHosted => '配置自建 frps';

  @override
  String get frp_serverAddress => '服务器地址';

  @override
  String get frp_authToken => '认证 token';

  @override
  String get frp_authTokenHint => 'frps 配置中的 auth.token（可留空）';

  @override
  String get frp_selfHostedHint => '隧道将保存在本地，启动时生成 frpc TOML 配置并运行。';

  @override
  String get frp_authCallbackTimeout => '等待网页授权超时或已取消';

  @override
  String get frp_noAccessToken => '授权回调中未获取到 access_token，请重试';

  @override
  String get frp_loginChmlFrpTitle => '登录 ChmlFrp';

  @override
  String get frp_chmlfrpAuthDesc =>
      '点击下方按钮后将在浏览器中打开 ChmlFrp 授权页：\n登录并授权后会自动跳回 IriX，无需复制粘贴任何内容。';

  @override
  String get frp_chmlfrpNoRegister => 'IriX 不提供 ChmlFrp 账号注册，请前往官网注册后登录。';

  @override
  String get frp_loginSakuraFrpTitle => '登录 SakuraFrp';

  @override
  String get frp_accessToken => '访问密钥 (Access Token)';

  @override
  String get frp_accessTokenHint => '粘贴 SakuraFrp 访问密钥';

  @override
  String get frp_show => '显示';

  @override
  String get frp_hide => '隐藏';

  @override
  String get frp_sakurafrpTokenHint =>
      '获取方式：打开 SakuraFrp 控制台 → 账户信息 → 访问密钥，点击复制后粘贴到此处。';

  @override
  String get frp_loginHayFrpTitle => '登录 HayFrp';

  @override
  String get frp_usernameOrEmail => '用户名或邮箱';

  @override
  String get frp_password => '密码';

  @override
  String get frp_hayfrpTokenHint => '登录获取的 Token 有效期 7 天，每次登录会使上次 Token 失效。';

  @override
  String get frp_tunnelNameRule => '隧道名称仅支持英文、数字、- 和 _';

  @override
  String get frp_selectNode => '请选择节点';

  @override
  String get frp_enterLocalAddr => '请输入本地地址';

  @override
  String get frp_localPortRange => '本地端口需在 1-65535 之间';

  @override
  String get frp_webNeedsDomain => 'HTTP/HTTPS 隧道需要填写绑定域名';

  @override
  String get frp_remotePortRange => '远程端口需在 1-65535 之间';

  @override
  String get frp_tunnelName => '隧道名称';

  @override
  String get frp_tunnelNameHint => '例如 my_server（不支持中文）';

  @override
  String get frp_tunnelType => '隧道类型';

  @override
  String get frp_localAddress => '本地地址';

  @override
  String get frp_selectInstance => '选择实例';

  @override
  String get frp_manualInput => '手动填写';

  @override
  String get frp_localPort => '本地端口';

  @override
  String get frp_localPortExample => '例如 25565';

  @override
  String get frp_localPortAuto => '本地端口（自动读取）';

  @override
  String get frp_remotePortHint => '开放给外部的端口';

  @override
  String get frp_bindDomain => '绑定域名';

  @override
  String get frp_noAvailableNodes => '没有可用的节点';

  @override
  String get frp_node => '节点';

  @override
  String get frp_noAvailableInstances =>
      '没有可用实例（需存在 server.properties 才能自动读取端口）';

  @override
  String get frp_instanceAutoPort => '实例（自动读取 server-port）';

  @override
  String get frp_create => '创建';

  @override
  String get frp_cannotOpenRegisterPage => '无法打开注册页面';

  @override
  String get frp_deleteTunnelTitle => '删除隧道';

  @override
  String get frp_enterAccessToken => '请输入访问密钥';

  @override
  String get frp_enterUsernamePassword => '请输入用户名和密码';

  @override
  String ai_logParseFailed(String e) {
    return '日志解析失败: $e';
  }

  @override
  String ai_compressedHistory(String summary) {
    return '已压缩对话历史：$summary';
  }

  @override
  String ai_saveFailed(String e) {
    return '保存失败: $e';
  }

  @override
  String ai_readFileFailed(String e) {
    return '读取文件失败: $e';
  }

  @override
  String ai_importFailed(String e) {
    return '导入失败: $e';
  }

  @override
  String ai_deleteDocumentConfirm(String title) {
    return '确定从知识库删除 \"$title\" 吗？';
  }

  @override
  String ai_deleteFailed(String e) {
    return '删除失败: $e';
  }

  @override
  String ai_deleteModelConfirm(String name) {
    return '确定删除模型 \"$name\" 吗？';
  }

  @override
  String ai_mcpStartFailed(String e) {
    return 'MCP 服务器启动失败: $e';
  }

  @override
  String ai_modelSubtitle(String baseUrl, int contextWindow) {
    return '$baseUrl\n上下文窗口: $contextWindow tokens';
  }

  @override
  String ai_milvusConfigured(String uri) {
    return '已配置 Milvus 连接：$uri';
  }

  @override
  String ai_docSubtitle(int chunkCount, String createdAt) {
    return '$chunkCount 个分块 · $createdAt';
  }

  @override
  String ai_mcpRunning(String endpoint) {
    return '运行中 $endpoint';
  }

  @override
  String frp_loginFailed(String e) {
    return '登录失败: $e';
  }

  @override
  String frp_createFailed(String e) {
    return '创建失败: $e';
  }

  @override
  String frp_deleteFailed(String e) {
    return '删除失败: $e';
  }

  @override
  String frp_startFailed(String e) {
    return '启动失败: $e';
  }

  @override
  String frp_deleteTunnelConfirm(String name) {
    return '确定删除隧道 \"$name\" 吗？';
  }

  @override
  String frp_deleted(String name) {
    return '已删除 $name';
  }

  @override
  String frp_domainLabel(String domain) {
    return '域名: $domain';
  }

  @override
  String frp_remotePort(String port) {
    return '远程端口 $port';
  }

  @override
  String frp_localMapping(String localAddr, int localPort, String remoteText) {
    return '本地 $localAddr:$localPort  →  $remoteText';
  }

  @override
  String frp_connectAddress(String address) {
    return '连接地址 $address';
  }

  @override
  String frp_nodeLoadFailed(String error) {
    return '节点加载失败: $error';
  }

  @override
  String frp_instancePort(String name, int port) {
    return '$name · 端口 $port';
  }

  @override
  String frp_tunnelCount(int count) {
    return '隧道 ($count)';
  }

  @override
  String get dbDetail_connectionInfo => '连接信息';

  @override
  String get dbDetail_connected => '已连接';

  @override
  String get dbDetail_type => '类型';

  @override
  String get dbDetail_address => '地址';

  @override
  String get dbDetail_user => '用户';

  @override
  String get dbDetail_database => '数据库';

  @override
  String get dbDetail_none => '无';

  @override
  String get dbDetail_testConnection => '测试连接';

  @override
  String get dbDetail_runSql => '执行 SQL';

  @override
  String get dbDetail_userManagement => '用户管理';

  @override
  String get dbDetail_newUser => '新建用户';

  @override
  String get dbDetail_redisNoUserManagement => 'Redis 不支持用户管理';

  @override
  String get dbDetail_noUsers => '暂无用户';

  @override
  String get dbDetail_view => '查看';

  @override
  String get dbDetail_noData => '无数据';

  @override
  String get dbDetail_databases => '数据库';

  @override
  String get dbDetail_newDatabase => '新建数据库';

  @override
  String get dbDetail_noDatabases => '未找到数据库';

  @override
  String get dbDetail_noTables => '该数据库没有表';

  @override
  String get dbDetail_addRow => '添加行';

  @override
  String get dbDetail_noDataInTable => '该表没有数据';

  @override
  String get dbDetail_noDataInPage => '当前页无数据';

  @override
  String get dbDetail_prevPage => '上一页';

  @override
  String get dbDetail_nextPage => '下一页';

  @override
  String get dbDetail_saved => '已保存';

  @override
  String get dbDetail_noMatchingRow => '未找到匹配行，数据未修改';

  @override
  String get dbDetail_rowAdded => '已添加行';

  @override
  String get dbDetail_deleteRow => '删除行';

  @override
  String get dbDetail_deleteRowConfirm => '确定要删除这一行吗？此操作不可恢复！';

  @override
  String get dbDetail_connectionSuccess => '连接成功';

  @override
  String get dbDetail_dropDatabaseTitle => '删除数据库';

  @override
  String get dbDetail_dropUserTitle => '删除用户';

  @override
  String get dbDetail_searchKeyPrefix => '前缀搜索 Key';

  @override
  String get dbDetail_addRedisKey => '添加 Key';

  @override
  String get dbDetail_noMatchingKeys => '没有匹配的 Key';

  @override
  String get dbDetail_emptyValue => '(空)';

  @override
  String get dbDetail_keyRequired => 'Key 不能为空';

  @override
  String get dbDetail_keyName => 'Key 名称';

  @override
  String get dbDetail_value => '值';

  @override
  String get dbDetail_usernameRequired => '请输入用户名';

  @override
  String get dbDetail_passwordRequired => '请输入密码';

  @override
  String get dbDetail_hostRequired => '请输入登录主机';

  @override
  String get dbDetail_username => '用户名';

  @override
  String get dbDetail_password => '密码';

  @override
  String get dbDetail_loginHost => '登录主机';

  @override
  String get dbDetail_loginHostHint => '例如 % 或 localhost';

  @override
  String get dbDetail_create => '创建';

  @override
  String get dbDetail_databaseNameRequired => '请输入数据库名称';

  @override
  String get dbDetail_databaseName => '数据库名称';

  @override
  String get dbDetail_databaseNameHintPg => '小写字母/数字/下划线';

  @override
  String get dbDetail_databaseNameHint => '例如 minecraft';

  @override
  String get dbDetail_databaseAccount => '数据库专用账号';

  @override
  String get dbDetail_autoGenerate => '自动生成';

  @override
  String get dbDetail_custom => '自定义';

  @override
  String get dbDetail_regenerate => '重新生成';

  @override
  String get dbDetail_databaseAccountNote => '将创建独立数据库并授予该账号全部权限';

  @override
  String get dbDetail_execute => '执行';

  @override
  String get dbDetail_selectDatabase => '选择数据库';

  @override
  String get dbDetail_resultShownAfterRun => '执行后在此显示结果';

  @override
  String get dbDetail_queryNoRows => '查询返回 0 行';

  @override
  String get jailDetail_tabRun => '运行';

  @override
  String get jailDetail_tabFiles => '文件';

  @override
  String get jailDetail_tabConsole => '控制台';

  @override
  String get jailDetail_tabPackages => '软件包';

  @override
  String get jailDetail_tabMounts => '挂载';

  @override
  String get jailDetail_tabSettings => '设置';

  @override
  String get jailDetail_running => '运行中';

  @override
  String get jailDetail_stopped => '已停止';

  @override
  String get jailDetail_sectionInstanceMount => '实例挂载（bastille mount）';

  @override
  String get jailDetail_selectInstance => '选择节点实例（自动填充路径与命令）';

  @override
  String get jailDetail_loadingInstances => '正在加载实例列表…';

  @override
  String get jailDetail_manualFill => '手动填写（不选择实例）';

  @override
  String get jailDetail_hostPath => '实例目录（节点上的宿主机路径）';

  @override
  String get jailDetail_hostPathHint =>
      '如 /usr/local/irix-node/instances/mc-survival';

  @override
  String get jailDetail_jailPath => 'Jail 内路径（默认 /data）';

  @override
  String get jailDetail_mounted => '已挂载';

  @override
  String get jailDetail_notMounted => '未挂载';

  @override
  String get jailDetail_mountButton => '挂载';

  @override
  String get jailDetail_unmountButton => '卸载';

  @override
  String get jailDetail_sectionRunInstance => '在 Jail 内运行实例（bastille cmd）';

  @override
  String get jailDetail_startCommand => '启动命令';

  @override
  String get jailDetail_startCommandHint =>
      '如 java -Xmx2G -jar server.jar nogui';

  @override
  String get jailDetail_workdir => '运行目录（容器内工作目录，默认 /data）';

  @override
  String get jailDetail_watchdog => '看门狗：进程退出后自动停止 Jail';

  @override
  String get jailDetail_watchdogSubtitle =>
      '容器内进程（如 MC 服务端）停止运行后，自动执行 bastille stop';

  @override
  String get jailDetail_startRun => '启动运行';

  @override
  String get jailDetail_stopProcess => '停止进程';

  @override
  String get jailDetail_sessionRunning => '会话运行中';

  @override
  String get jailDetail_sessionEnded => '会话已结束';

  @override
  String get jailDetail_runHint =>
      '提示：未挂载实例目录时，启动运行会自动挂载（默认 /data）。查看输出 / 发送命令请在下方控制台进行。';

  @override
  String get jailDetail_sessionConsole => '运行会话控制台';

  @override
  String get jailDetail_sessionNoOutput => '（尚未启动运行，输出将显示在这里）';

  @override
  String get jailDetail_commandInputHint => '输入命令（如 say hello），回车发送';

  @override
  String get jailDetail_jailPathLabel => 'Jail 内路径';

  @override
  String get jailDetail_jailPathHint => '如 /data 或 /usr/local/bin';

  @override
  String get jailDetail_goto => '跳转';

  @override
  String get jailDetail_mountPoints => '挂载点：';

  @override
  String get jailDetail_upload => '上传';

  @override
  String get jailDetail_newFolder => '新建目录';

  @override
  String get jailDetail_newFile => '新建文件';

  @override
  String get jailDetail_upLevel => '返回上级';

  @override
  String get jailDetail_download => '下载';

  @override
  String get jailDetail_fillHostPath => '请填写实例目录（节点上的宿主机路径）';

  @override
  String get jailDetail_jailNotRunning => 'Jail 未运行，请先在顶部启动 Jail';

  @override
  String get jailDetail_fillStartCommand =>
      '请填写启动命令（如 java -Xmx2G -jar server.jar nogui）';

  @override
  String get jailDetail_mountInstanceFailed => '实例目录挂载失败';

  @override
  String get jailDetail_noSessionId => '节点未返回会话 id：可能节点版本过旧，缺少运行会话接口';

  @override
  String get jailDetail_runStartedWatch => '已在 Jail 内启动';

  @override
  String get jailDetail_watchdogSuffix => '（看门狗开启：进程退出后自动停止 Jail）';

  @override
  String get jailDetail_jailStoppedSuffix => '，Jail 已停止';

  @override
  String get jailDetail_startFailed => '启动失败';

  @override
  String get jailDetail_noRunningSession => '没有运行中的会话';

  @override
  String get jailDetail_sendFailed => '发送失败';

  @override
  String get jailDetail_noConsoleLog => '（Jail 未运行，无控制台日志）';

  @override
  String get jailDetail_noOutput => '（无输出）';

  @override
  String get jailDetail_execFailed => '执行失败';

  @override
  String get jailDetail_fillPkgName => '请填写包名（如 openjdk17-jre）';

  @override
  String get jailDetail_procMounted => '/proc 已挂载';

  @override
  String get jailDetail_procfsMounted => '已挂载 procfs → /proc';

  @override
  String get jailDetail_loadFilesFailed => '加载文件列表失败';

  @override
  String get jailDetail_folderName => '目录名称';

  @override
  String get jailDetail_fileName => '文件名称';

  @override
  String get jailDetail_uploadFailed => '上传失败';

  @override
  String get jailDetail_saveFile => '保存文件';

  @override
  String get jailDetail_downloadFailed => '下载失败';

  @override
  String get jailDetail_fileTooLarge => '文件过大（>2MB），请下载后编辑';

  @override
  String get jailDetail_readFileFailed => '读取文件失败';

  @override
  String get jailDetail_saveFailed => '保存失败';

  @override
  String get jailDetail_editText => '编辑（文本）';

  @override
  String get jailDetail_downloadLocal => '下载到本地';

  @override
  String get jailDetail_folder => '目录';

  @override
  String get jailDetail_file => '文件';

  @override
  String get jailDetail_deleteFailed => '删除失败';

  @override
  String get jailDetail_removeConfigContent => '从 jail.conf 中移除该参数（下次启动生效）。';

  @override
  String get jailDetail_configTitle => 'Jail 配置（bastille config）';

  @override
  String get jailDetail_addConfig => '添加配置项';

  @override
  String get jailDetail_noConfig => '暂无配置项，点击「添加配置项」';

  @override
  String get jailDetail_removeConfig => '删除配置项';

  @override
  String get jailDetail_consoleHint =>
      'Jail 系统控制台日志（bastille console 视角）· 下方命令在 jail 内执行（sh 语义）';

  @override
  String get jailDetail_noLogOutput => '（暂无日志输出）';

  @override
  String get jailDetail_consoleCmdHint =>
      'jail 内执行命令（如 ls /data、java -version）';

  @override
  String get jailDetail_runCommand => '执行命令';

  @override
  String get jailDetail_refreshLog => '刷新日志';

  @override
  String get jailDetail_pkgManage => '软件包管理（bastille pkg）';

  @override
  String get jailDetail_pkgName => '包名（逗号 / 空格分隔）';

  @override
  String get jailDetail_pkgNameHint => '如 openjdk17-jre openjdk21-jre';

  @override
  String get jailDetail_pkgInstall => '安装（install）';

  @override
  String get jailDetail_pkgDelete => '删除（delete）';

  @override
  String get jailDetail_pkgUpdate => '更新索引（update）';

  @override
  String get jailDetail_pkgUpgrade => '升级全部（upgrade）';

  @override
  String get jailDetail_pkgAutoremove => '清理无用依赖（autoremove）';

  @override
  String get jailDetail_executing => '执行中…';

  @override
  String get jailDetail_execute => '执行';

  @override
  String get jailDetail_detectJava => '检测 Java';

  @override
  String get jailDetail_javaEnv => 'Java 环境';

  @override
  String get jailDetail_mountProc => '挂载 /proc（procfs）';

  @override
  String get jailDetail_mountProcSubtitle =>
      '部分 Java 版本 / JVM 特性（GC 日志等）需要 jail 内有 /proc；仅需执行一次，写入 fstab 后重启自动生效。';

  @override
  String get jailDetail_installJava => '安装 Java 运行环境';

  @override
  String get jailDetail_installJavaSubtitle =>
      '在「操作」选择安装，包名填写 openjdk17-jre 等（见上方快捷包），然后点击「执行」。安装完成后可用「检测 Java」验证。';

  @override
  String get jailDetail_mountListTitle => '挂载列表（bastille mount / fstab）';

  @override
  String get jailDetail_noMounts => '暂无挂载，点击「添加挂载」';

  @override
  String get jailDetail_openDir => '打开目录（文件 Tab）';

  @override
  String get jailDetail_fstabPersist => 'fstab 持久化（重启自动挂载）';

  @override
  String get jailDetail_tempMount => '仅当前挂载（重启后需重新挂载）';

  @override
  String get jailDetail_addMount => '添加挂载';

  @override
  String get jailDetail_fstype => '文件系统类型';

  @override
  String get jailDetail_fstypeNullfs => 'nullfs（宿主机目录）';

  @override
  String get jailDetail_fstypeProcfs => 'procfs（/proc，Java 需要）';

  @override
  String get jailDetail_srcPath => '宿主机源路径';

  @override
  String get jailDetail_dstPath => 'Jail 内目标路径';

  @override
  String get jailDetail_dstPathHint => '如 /data 或 /proc';

  @override
  String get jailDetail_mountOption => '挂载选项（默认 rw）';

  @override
  String get jailDetail_fstabPersistSubtitle =>
      '写入 fstab：jail 启动时自动挂载，重启不丢失（推荐）';

  @override
  String get jailDetail_nullfsHint =>
      '提示：nullfs 实时挂载需要 jail 运行中；jail 未运行时只能写入 fstab（下次启动生效）。挂载后可在「文件」Tab 查看目录内容。';

  @override
  String get jailDetail_unmountTitle => '卸载挂载';

  @override
  String get jailDetail_configKey => '配置键（如 ip4.addr、hostname）';

  @override
  String get jailDetail_configValue => '配置值';

  @override
  String get jailDetail_configValueHint => '如 192.168.1.51/24、yes';

  @override
  String get jailDetail_clearOutput => '清空输出';

  @override
  String get jailDetail_noRunningSessionInput => '（无运行中的会话）';

  @override
  String get jailDetail_send => '发送';

  @override
  String get jailDetail_mountAddedPersist => '挂载已添加（fstab 持久化，重启自动挂载）';

  @override
  String get jailDetail_mountAddedTemp => '挂载已添加（仅当前挂载，重启后需重新挂载）';

  @override
  String get jailDetail_operationFailed => '操作失败';

  @override
  String get jailDetail_stopFailed => '停止失败';

  @override
  String get jailDetail_configHintIp4Addr => 'IPv4 地址（如 192.168.1.50/24）';

  @override
  String get jailDetail_configHintIp6Addr => 'IPv6 地址';

  @override
  String get jailDetail_configHintHostname => 'jail 主机名';

  @override
  String get jailDetail_configHintExecStart => '启动时执行的命令';

  @override
  String get jailDetail_configHintExecStop => '停止时执行的命令';

  @override
  String get jailDetail_configHintExecConsolelog => '控制台日志路径';

  @override
  String get jailDetail_configHintAutostart => '开机自启（yes/no）';

  @override
  String get jailDetail_configHintAllowMount => '允许 jail 内挂载';

  @override
  String get jailDetail_configHintAllowMountProcfs => '允许挂载 procfs';

  @override
  String get jailDetail_configHintVnet => 'VNET 网络模式';

  @override
  String get jailDetail_configHintInterface => '网络接口';

  @override
  String get jailDetail_configHintSecurelevel => '安全级别';

  @override
  String dbDetail_title(String name) {
    return '$name - 数据库';
  }

  @override
  String dbDetail_databasePrefix(String name) {
    return '数据库: $name';
  }

  @override
  String dbDetail_tablePrefix(String name) {
    return '表: $name';
  }

  @override
  String dbDetail_pageInfo(int page, int maxPage, int totalRows, int pageSize) {
    return '第 $page / $maxPage 页 · 共 $totalRows 行 · 每页 $pageSize 行';
  }

  @override
  String dbDetail_saveFailed(String error) {
    return '保存失败: $error';
  }

  @override
  String dbDetail_addFailed(String error) {
    return '添加失败: $error';
  }

  @override
  String dbDetail_rowsDeleted(int count) {
    return '已删除 $count 行';
  }

  @override
  String dbDetail_connectionFailed(String error) {
    return '连接失败: $error';
  }

  @override
  String dbDetail_databaseCreated(String name) {
    return '已创建数据库 $name';
  }

  @override
  String dbDetail_createFailed(String error) {
    return '创建失败: $error';
  }

  @override
  String dbDetail_dropDatabaseConfirm(String name) {
    return '确定要删除数据库 $name 吗？\n此操作不可恢复！';
  }

  @override
  String dbDetail_databaseDeleted(String name) {
    return '已删除数据库 $name';
  }

  @override
  String dbDetail_deleteFailed(String error) {
    return '删除失败: $error';
  }

  @override
  String dbDetail_redisKeyDeleted(String name) {
    return '已删除 $name';
  }

  @override
  String dbDetail_userCreated(String name) {
    return '已创建用户 $name';
  }

  @override
  String dbDetail_dropUserConfirm(String name) {
    return '确定要删除用户 $name 吗？';
  }

  @override
  String dbDetail_userDeleted(String name) {
    return '已删除用户 $name';
  }

  @override
  String dbDetail_affectedRows(int count) {
    return '受影响行数: $count';
  }

  @override
  String jailDetail_releaseOf(String name) {
    return '发行版 $name';
  }

  @override
  String jailDetail_forwardOf(String ports) {
    return '转发 $ports';
  }

  @override
  String jailDetail_pathEmpty(String path) {
    return '$path 为空\n挂载实例目录后，文件会出现在这里';
  }

  @override
  String jailDetail_mountedPersist(String src, String dst) {
    return '已挂载 $src → $dst（fstab 持久化，重启不丢失）';
  }

  @override
  String jailDetail_unmounted(String path) {
    return '已卸载 $path';
  }

  @override
  String jailDetail_processExited(String code) {
    return '容器内进程已退出（exit $code）';
  }

  @override
  String jailDetail_execFailedDetail(String error) {
    return '执行失败：$error';
  }

  @override
  String jailDetail_detectFailedDetail(String error) {
    return '检测失败：$error';
  }

  @override
  String jailDetail_locatedAt(String path) {
    return '位于 $path';
  }

  @override
  String jailDetail_selectUpload(String path) {
    return '选择要上传到 $path 的文件';
  }

  @override
  String jailDetail_uploadedFiles(int count, String path) {
    return '已上传 $count 个文件到 $path';
  }

  @override
  String jailDetail_downloadedTo(String path) {
    return '已下载到 $path';
  }

  @override
  String jailDetail_editFile(String name) {
    return '编辑 $name';
  }

  @override
  String jailDetail_savedFile(String name) {
    return '已保存 $name';
  }

  @override
  String jailDetail_deleteConfirm(String type) {
    return '删除$type？';
  }

  @override
  String jailDetail_deletePathConfirm(String path, bool dir) {
    return '确定删除 $path 吗？\n$dir';
  }

  @override
  String jailDetail_deletedPath(String path) {
    return '已删除 $path';
  }

  @override
  String jailDetail_configSaved(String key) {
    return '已保存 $key';
  }

  @override
  String jailDetail_removeConfigTitle(String key) {
    return '删除配置项 $key？';
  }

  @override
  String jailDetail_configRemoved(String key) {
    return '已删除 $key';
  }

  @override
  String jailDetail_configAdded(String key) {
    return '已添加 $key';
  }

  @override
  String jailDetail_optionOf(String options) {
    return '选项 $options';
  }

  @override
  String jailDetail_unmountConfirm(String display) {
    return '确定卸载 $display 吗？\n（fstab 条目也会一并移除）';
  }

  @override
  String get nbt_title => 'NBT 编辑器';

  @override
  String get nbt_importNbt => '导入 .nbt';

  @override
  String get nbt_pasteSnbt => '粘贴 SNBT';

  @override
  String get nbt_exportNbt => '导出 .nbt';

  @override
  String get nbt_exportViewSnbt => '导出/查看 SNBT';

  @override
  String get nbt_domainTree => '通用树';

  @override
  String get nbt_domainItem => '物品';

  @override
  String get nbt_domainEntity => '实体';

  @override
  String get nbt_domainVillager => '村民交易';

  @override
  String get nbt_domainRcon => '连服务器';

  @override
  String get nbt_mode => '模式';

  @override
  String get nbt_advancedTree => '高级树';

  @override
  String get nbt_simpleMode => '简易模式';

  @override
  String get nbt_treeOnlyAdvanced => '通用树模式仅提供高级树编辑。';

  @override
  String get nbt_searchPath => '搜索路径…';

  @override
  String get nbt_root => '(root)';

  @override
  String get nbt_emptyList => '(空列表)';

  @override
  String get nbt_emptyCompound => '(空 Compound)';

  @override
  String get nbt_editValue => '编辑值';

  @override
  String get nbt_addChild => '添加子节点';

  @override
  String get nbt_type => '类型';

  @override
  String get nbt_keyName => '键名';

  @override
  String get nbt_rootUndeletable => '根节点不可删除';

  @override
  String get nbt_loadFailed => '加载失败';

  @override
  String get nbt_snbtParsed => '已解析 SNBT';

  @override
  String get nbt_currentSnbt => '当前 SNBT';

  @override
  String get nbt_rconPlaceholder =>
      '连服务器（RCON）面板将在阶段 3 接入：\n在此输入 host/port/password 连接开启了 RCON 的服务器，\n并把当前编辑的 NBT 经 /give、/data merge 等命令下发。';

  @override
  String get nbt_itemId => '物品 ID';

  @override
  String get nbt_itemCount => '数量 Count';

  @override
  String get nbt_itemCustomName => '自定义名称 custom_name';

  @override
  String get nbt_itemLore => 'Lore（逗号分隔）';

  @override
  String get nbt_itemUnbreakable => '是否损坏 Unbreakable';

  @override
  String get nbt_itemFireResistant => '防火 Fire-resistant';

  @override
  String get nbt_itemEnchantments => '附魔（JSON 数组）';

  @override
  String get nbt_itemDamage => '伤害值 damage';

  @override
  String get nbt_entityCustomName => '自定义名称 CustomName';

  @override
  String get nbt_entityHealth => '生命值 Health';

  @override
  String get nbt_entitySilent => '静音 Silent';

  @override
  String get nbt_entityGlowing => '发光 Glowing';

  @override
  String get nbt_entityNoGravity => '无重力 NoGravity';

  @override
  String get nbt_entityInvulnerable => '无敌 Invulnerable';

  @override
  String get nbt_entityPoiCounted => '已捕获 Poicounted';

  @override
  String get nbt_villagerProfession => '职业 profession';

  @override
  String get nbt_villagerLevel => '等级 level（经验）';

  @override
  String get nbt_villagerType => '村民类型 type';

  @override
  String get nbt_villagerOffers => '交易数量 Offers（JSON）';

  @override
  String get configEditor_noConfigFiles => '该目录中暂无配置文件';

  @override
  String get configEditor_configGeneratedAfterStart => '启动服务器后会生成配置文件';

  @override
  String get configEditor_configFiles => '配置文件';

  @override
  String get configEditor_importCsv => '导入CSV注释';

  @override
  String get configEditor_undo => '撤销';

  @override
  String get configEditor_searchHint => '搜索配置项（中英文均可）';

  @override
  String get configEditor_unsavedChanges => '未保存的修改';

  @override
  String get configEditor_discardConfirm => '当前文件有未保存的修改，是否丢弃？';

  @override
  String get configEditor_discard => '丢弃';

  @override
  String get configEditor_parseFailedTextMode => '解析失败，已切换到文本模式';

  @override
  String get configEditor_emptyOrUnparseable => '该文件为空或无法解析为表单，请切换到文本模式编辑';

  @override
  String get remoteTab_selectJarToUpload => '选择要上传的 .jar 文件';

  @override
  String get remoteTab_saveFile => '保存文件';

  @override
  String get remoteTab_deleteFileHint => '将从节点实例中删除该文件。';

  @override
  String get remoteTab_deleteZipHint => '将从节点实例中删除该压缩包。';

  @override
  String get remoteTab_plugins => '插件（plugins/）';

  @override
  String get remoteTab_mods => 'Mod（mods/）';

  @override
  String get remoteTab_metaDetectionHint =>
      '已从 jar 元数据检测（plugin.yml / fabric.mod.json 等）。上传的 .jar 会直接写入节点实例对应目录。';

  @override
  String get remoteTab_fileListHint =>
      '节点未提供插件元数据（版本过旧？），仅显示文件列表。上传的 .jar 会直接写入节点实例对应目录（mods 支持版本子目录，此处统一列出）。';

  @override
  String get remoteTab_uploadJar => '上传 .jar';

  @override
  String get remoteTab_emptyNoDetection => '（空）未检测到插件/Mod';

  @override
  String get remoteTab_download => '下载';

  @override
  String get remoteTab_delete => '删除';

  @override
  String get remoteTab_empty => '（空）';

  @override
  String get remoteTab_selectRestoreZip => '选择要恢复的备份 (.zip)';

  @override
  String get remoteTab_restoreBackupTitle => '恢复备份？';

  @override
  String get remoteTab_restoreBackupContent =>
      '将把压缩包上传到实例根目录并解压，同名文件会被覆盖。建议先停止实例再恢复。';

  @override
  String get remoteTab_restore => '恢复';

  @override
  String get remoteTab_statusCreatingSnapshot => '创建快照中…';

  @override
  String get remoteTab_restoreSnapshotTitle => '恢复快照？';

  @override
  String get remoteTab_statusRestoringSnapshot => '恢复快照中…';

  @override
  String get remoteTab_saveSnapshot => '保存快照';

  @override
  String get remoteTab_statusDownloadingSnapshot => '下载快照中…';

  @override
  String get remoteTab_deleteSnapshotHint => '将从节点快照区永久删除，不可恢复。';

  @override
  String get remoteTab_instanceBackup => '实例备份';

  @override
  String get remoteTab_instanceBackupDesc =>
      '备份在节点端压缩整个实例目录后下载到本地；恢复会覆盖同名文件，建议先停止实例。';

  @override
  String get remoteTab_startBackup => '开始备份';

  @override
  String get remoteTab_restoreBackup => '恢复备份';

  @override
  String get remoteTab_statusProcessing => '处理中…';

  @override
  String get remoteTab_nodeSnapshot => '节点端快照';

  @override
  String remoteTab_nodeSnapshotDesc(String data) {
    return '快照由节点在 $data/backups/<实例> 保管，恢复会先停止实例再覆盖。';
  }

  @override
  String get remoteTab_createSnapshot => '创建快照';

  @override
  String get remoteTab_noSnapshots => '（暂无快照）';

  @override
  String get remoteTab_nodeBackupFiles => '节点端备份文件';

  @override
  String get remoteTab_noZipBackups => '（暂无 .zip 备份文件）';

  @override
  String get remoteTab_backupRestored => '备份已恢复';

  @override
  String nbt_searchResults(int count) {
    return '搜索结果（$count）';
  }

  @override
  String nbt_imported(String name) {
    return '已导入 $name';
  }

  @override
  String nbt_importFailed(String e) {
    return '导入失败';
  }

  @override
  String nbt_parseFailed(String e) {
    return '解析失败';
  }

  @override
  String nbt_exported(String path) {
    return '已导出 $path';
  }

  @override
  String nbt_exportFailed(String e) {
    return '导出失败';
  }

  @override
  String nbt_generateSnbtFailed(String e) {
    return '生成 SNBT 失败';
  }

  @override
  String nbt_searchFailed(String e) {
    return '搜索失败';
  }

  @override
  String nbt_editValueTitle(String type) {
    return '编辑值（$type）';
  }

  @override
  String configEditor_saved(String name) {
    return '已保存 $name';
  }

  @override
  String configEditor_saveFailed(String e) {
    return '保存失败';
  }

  @override
  String configEditor_importedAnnotations(int count) {
    return '已导入 $count 条注释';
  }

  @override
  String configEditor_importFailed(String e) {
    return '导入失败';
  }

  @override
  String configEditor_noMatch(String query) {
    return '未找到匹配「$query」的配置项';
  }

  @override
  String remoteTab_downloadedTo(String path) {
    return '已下载到 $path';
  }

  @override
  String remoteTab_deleteJar(String name) {
    return '删除 $name？';
  }

  @override
  String remoteTab_statusDownloadingEntry(String name) {
    return '下载 $name…';
  }

  @override
  String remoteTab_deleteZip(String name) {
    return '删除 $name？';
  }

  @override
  String remoteTab_restoreSnapshotContent(String name) {
    return '将停止实例并解压覆盖「$name」到实例目录，恢复后实例保持停止。';
  }

  @override
  String remoteTab_deleteSnapshot(String name) {
    return '删除快照 $name？';
  }

  @override
  String get home_mcpRequestTitle => 'AI 申请执行敏感操作';

  @override
  String get home_mcpDeny => '拒绝';

  @override
  String get home_mcpAllow => '允许';

  @override
  String get home_navInstances => '实例';

  @override
  String get home_navNodes => '节点';

  @override
  String get home_navMarket => '市场';

  @override
  String get home_navDatabase => '数据库';

  @override
  String get home_navAi => 'AI';

  @override
  String get home_navFrp => 'FRP';

  @override
  String get home_navHome => '主页';

  @override
  String get home_navContainers => '容器';

  @override
  String get home_navOrchestration => '编排';

  @override
  String get home_newInstance => '新建实例';

  @override
  String get home_nbtEditor => 'NBT 编辑器';

  @override
  String get common_settings => '设置';

  @override
  String get instanceDetail_title => '实例详情';

  @override
  String get instanceDetail_notFound => '实例不存在';

  @override
  String get instanceDetail_adoptedTooltip =>
      '该进程由上次启动的 IriX 遗留，已接管其日志；stdin 已断开，无法发送指令，仅可强制停止';

  @override
  String get instanceDetail_adopted => '已接管';

  @override
  String get instanceDetail_closeAi => '关闭 AI 助手';

  @override
  String get instanceDetail_openAi => '打开 AI 助手';

  @override
  String get instanceDetail_tabOverview => '总览';

  @override
  String get instanceDetail_tabConfig => '配置';

  @override
  String get instanceDetail_tabPlugins => '插件/Mod';

  @override
  String get instanceDetail_tabFiles => '文件';

  @override
  String get instanceDetail_tabBackup => '备份';

  @override
  String get instanceDetail_tabSettings => '设置';

  @override
  String get instanceDetail_commandHintAdopted => '已接管的进程无法发送指令（请使用强制停止）';

  @override
  String get instanceDetail_commandHint => '输入服务器指令（无需 /）后按回车';

  @override
  String get instanceDetail_control => '控制';

  @override
  String get instanceDetail_start => '启动';

  @override
  String get instanceDetail_restart => '重启';

  @override
  String get instanceDetail_stop => '停止';

  @override
  String get instanceDetail_forceStop => '强制停止';

  @override
  String get instanceDetail_currentStatus => '当前状态';

  @override
  String get instanceDetail_adoptedStatusNote =>
      '该进程由上次启动的 IriX 遗留，已接管其日志；stdin 已断开，无法发送指令。';

  @override
  String get instanceDetail_selectAtLeastOne => '请至少选择一个文件或文件夹';

  @override
  String get instanceDetail_backupCancelled => '备份已取消';

  @override
  String get instanceDetail_selectAll => '全选';

  @override
  String get instanceDetail_emptyRoot => '根目录为空';

  @override
  String get instanceDetail_folder => '文件夹';

  @override
  String get instanceDetail_file => '文件';

  @override
  String get instanceDetail_startBackup => '开始备份';

  @override
  String get instanceDetail_backingUp => '正在备份...';

  @override
  String get instanceDetail_maxMemory => '最大内存';

  @override
  String get instanceDetail_notSet => '未设置';

  @override
  String get instanceDetail_noXmxHint => '当前启动命令未指定 -Xmx，拖动滑块以设置内存';

  @override
  String get instanceDetail_startCommand => '启动命令';

  @override
  String get instanceDetail_startCommandHelper =>
      '如：java -Xmx2G -jar paper.jar nogui';

  @override
  String get instanceDetail_deleteInstance => '删除实例';

  @override
  String get instanceDetail_stopBeforeSwitch => '请先停止服务器再切换运行方式';

  @override
  String get instanceDetail_runMode => '运行方式';

  @override
  String get instanceDetail_nativeProcess => '原生进程';

  @override
  String get instanceDetail_nativeProcessDesc => '直接以 java 进程运行（默认）';

  @override
  String get instanceDetail_dockerContainer => 'Docker 容器';

  @override
  String get instanceDetail_dockerDesc => '服务器运行在 Docker 容器中，启停/控制台/文件走容器';

  @override
  String get instanceDetail_dockerNotFound =>
      '未检测到 Docker CLI，请先安装并启动 Docker Desktop';

  @override
  String get instanceDetail_unavailable => '不可用';

  @override
  String get instanceDetail_containerConfig => '容器配置';

  @override
  String get instanceDetail_containerConfigSaved => '容器配置已保存';

  @override
  String get instanceDetail_image => '镜像';

  @override
  String get instanceDetail_imageHelper => '如 itzg/minecraft-server:latest';

  @override
  String get instanceDetail_containerName => '容器名称（留空自动生成）';

  @override
  String get instanceDetail_portMappingHelper =>
      '宿主机端口:容器端口，多个用逗号分隔，如 25565:25565, 8123:8123';

  @override
  String get instanceDetail_volumeMountHelper => '宿主机路径:容器路径；留空默认挂载实例目录到 /data';

  @override
  String get instanceDetail_workdirHelper => '如 /data，强制在数据目录启动';

  @override
  String get instanceDetail_containerNameDerived =>
      '容器由实例名派生，如 xmc-<名称>-<id后缀>';

  @override
  String get instanceDetail_deleteInstanceConfirm => '确定要删除此实例吗？';

  @override
  String get instanceDetail_deleteFiles => '同时删除服务器文件';

  @override
  String get instanceDetail_deleteFilesDesc =>
      '勾选后将删除服务器根目录下的所有文件，包括世界、配置和核心。此操作不可撤销。';

  @override
  String get instanceDetail_nameUpdated => '实例名称已更新';

  @override
  String get instanceDetail_instanceName => '实例名称';

  @override
  String get instanceDetail_backupCompressionLevel => '备份压缩级别';

  @override
  String get instanceDetail_compressionLevelDesc =>
      '级别越低压缩越快但文件更大，级别越高压缩比越好但更慢。0=不压缩(仅存储)，6=标准，9=最佳压缩比。';

  @override
  String get instanceDetail_eulaAccepted => '已同意 EULA';

  @override
  String get instanceDetail_eulaRevoked => '已撤销 EULA 同意';

  @override
  String get instanceDetail_eulaTitle => 'EULA 最终用户许可协议';

  @override
  String get instanceDetail_eulaNotFound => '未找到 eula.txt，将在同意后自动创建。';

  @override
  String get instanceDetail_eulaAccept => '同意 Mojang EULA';

  @override
  String get instanceDetail_eulaAcceptedSubtitle => '已同意，服务器可正常启动';

  @override
  String get instanceDetail_eulaNotAcceptedSubtitle => '未同意，服务器启动后将自动退出';

  @override
  String get instanceDetail_eulaNote =>
      '同意后将写入 eula=true 到 eula.txt。详见 Mojang EULA。';

  @override
  String get nodeDetail_notFoundOrDeleted => '节点不存在或已被删除';

  @override
  String get nodeDetail_tabOverview => '概览';

  @override
  String get nodeDetail_tabInstances => '实例';

  @override
  String get nodeDetail_tabUsers => '用户';

  @override
  String get nodeDetail_tabOps => '运维';

  @override
  String get nodeDetail_title => '节点';

  @override
  String get nodeDetail_launchLocal => '启动本地节点';

  @override
  String get nodeDetail_cannotLaunch => '无法启动';

  @override
  String get nodeDetail_hostInfo => '主机信息';

  @override
  String get nodeDetail_hostname => '主机名';

  @override
  String get nodeDetail_system => '系统';

  @override
  String get nodeDetail_platform => '平台';

  @override
  String get nodeDetail_uptime => '运行时间';

  @override
  String get nodeDetail_resourceUsage => '资源占用';

  @override
  String get nodeDetail_memory => '内存';

  @override
  String get nodeDetail_cpu => 'CPU';

  @override
  String get nodeDetail_nodeProcessMemory => '节点进程内存';

  @override
  String get nodeDetail_nodeVersion => '节点版本';

  @override
  String get nodeDetail_instanceStats => '实例统计';

  @override
  String get nodeDetail_daemons => '守护进程';

  @override
  String get nodeDetail_daemonList => '守护进程列表';

  @override
  String get nodeDetail_versionUnknown => '版本未知';

  @override
  String get nodeDetail_noDaemonId => '无法确定守护进程 ID，请检查节点连接';

  @override
  String get nodeDetail_selectDaemonToManage => '选择守护进程后管理其实例';

  @override
  String get nodeDetail_newInstance => '新建实例';

  @override
  String get nodeDetail_noInstances => '暂无实例\n点击右上角「新建实例」创建';

  @override
  String get nodeDetail_cwdUnknown => '工作目录未知';

  @override
  String get nodeDetail_onlinePlayers => '在线玩家  /  ';

  @override
  String get nodeDetail_start => '启动';

  @override
  String get nodeDetail_stop => '停止';

  @override
  String get nodeDetail_restart => '重启';

  @override
  String get nodeDetail_kill => '强杀';

  @override
  String get nodeDetail_userManagement => '用户管理（面板 API）';

  @override
  String get nodeDetail_newUser => '新建用户';

  @override
  String get nodeDetail_noUsers => '暂无用户';

  @override
  String get nodeDetail_admin => '管理员';

  @override
  String get nodeDetail_normalUser => '普通用户';

  @override
  String get nodeDetail_setAdmin => '设为管理员';

  @override
  String get nodeDetail_setNormalUser => '设为普通用户';

  @override
  String get nodeDetail_unban => '解除禁用';

  @override
  String get nodeDetail_create => '创建';

  @override
  String get nodeDetail_username => '用户名';

  @override
  String get nodeDetail_password => '密码';

  @override
  String get nodeDetail_permission => '权限';

  @override
  String get nodeDetail_instanceName => '实例名称';

  @override
  String get nodeDetail_workdirAbsolute => '工作目录（服务器上的绝对路径）';

  @override
  String get nodeDetail_serverCommandHelper =>
      '启动命令（如 java -Xmx2G -jar server.jar nogui）';

  @override
  String get nodeDetail_processType => '进程类型';

  @override
  String get nodeDetail_processUniversal => '通用（直接运行进程）';

  @override
  String get nodeDetail_processDocker => 'Docker（容器内运行）';

  @override
  String get nodeDetail_dockerImage => 'Docker 镜像（如 mcsm-ubuntu:22.04）';

  @override
  String get nodeDetail_memoryLimit => '内存限制（MB）';

  @override
  String get nodeDetail_networkMode => '网络模式';

  @override
  String get nodeDetail_portMappingHelper => '端口映射（逗号分隔，如 25565:25565/tcp）';

  @override
  String get nodeDetail_extraVolumes => '额外挂载卷（逗号分隔，如 /data:/data）';

  @override
  String get nodeDetail_containerNameOptional => '容器名称（可留空自动生成）';

  @override
  String get nodeDetail_importFailed => '导入失败';

  @override
  String get nodeDetail_gomaxprocs => 'GOMAXPROCS';

  @override
  String get nodeDetail_gcPercent => 'GC 百分比';

  @override
  String get nodeDetail_cpuUsage => 'CPU 占用';

  @override
  String get nodeDetail_goroutines => 'goroutine 数';

  @override
  String get nodeDetail_heapMemory => '堆内存';

  @override
  String get nodeDetail_cpuCores => 'CPU 核数';

  @override
  String get nodeDetail_nodeLoad => '节点负载';

  @override
  String get nodeDetail_importInstanceTitle => '从目录导入实例';

  @override
  String get nodeDetail_importInstanceDesc => '指定节点侧已存在的服务端目录，节点扫描特征后创建实例。';

  @override
  String get nodeDetail_import => '导入';

  @override
  String get nodeDetail_downloadCoreTitle => '下载服务端核心到实例';

  @override
  String get nodeDetail_downloadCoreDesc =>
      '节点直连 URL 下载核心 jar 到实例根目录（支持 sha512 校验）。';

  @override
  String get nodeDetail_downloadCore => '下载核心';

  @override
  String get nodeDetail_nodeLoadDesc =>
      '守护进程自身负载调谐状态（idle/normal/busy、GOMAXPROCS、GC）。';

  @override
  String get nodeDetail_view => '查看';

  @override
  String get nodeDetail_auditLog => '审计日志';

  @override
  String get nodeDetail_auditLogDesc => '记录每一次 API 请求（来源 IP、方法、路径、状态码、耗时）。';

  @override
  String get nodeDetail_javaRuntime => 'Java 运行时';

  @override
  String get nodeDetail_noJavaRuntime => '（未检测到 Java 运行时）';

  @override
  String get nodeDetail_unavailableParen => '（不可用）';

  @override
  String get nodeDetail_processing => '处理中…';

  @override
  String get nodeDetail_instanceNameOptional => '实例名（可空，默认取目录名）';

  @override
  String get nodeDetail_nodeDirPath => '节点侧目录绝对路径';

  @override
  String get nodeDetail_nodeDirPathHint => '如 /home/mc/server';

  @override
  String get nodeDetail_targetUuid => '目标实例 UUID';

  @override
  String get nodeDetail_downloadUrl => '下载链接 (http/https)';

  @override
  String get nodeDetail_fileName => '文件名（如 server.jar）';

  @override
  String get nodeDetail_sha512 => 'sha512 校验（可选）';

  @override
  String get nodeDetail_startDownload => '开始下载';

  @override
  String get nodeDetail_auditLogRecent => '审计日志（最近 200 行）';

  @override
  String get nodeDetail_noAuditLog => '（无审计日志）';

  @override
  String get nodeDetail_uninstall => '卸载';

  @override
  String instanceDetail_startFailed(String error) {
    return '启动失败：';
  }

  @override
  String instanceDetail_restartFailed(String error) {
    return '重启失败：';
  }

  @override
  String instanceDetail_backupSaved(String path) {
    return '备份已保存到';
  }

  @override
  String instanceDetail_backupFailed(String error) {
    return '备份失败:';
  }

  @override
  String instanceDetail_errorCode(int code) {
    return '错误码';
  }

  @override
  String instanceDetail_selectedCount(int selected, int total) {
    return '已选择  /  项';
  }

  @override
  String instanceDetail_switchedToMode(String mode) {
    return '已切换为「」运行';
  }

  @override
  String instanceDetail_eulaWriteFailed(String error) {
    return '写入 eula.txt 失败:';
  }

  @override
  String nodeDetail_onlineWithAddr(String address) {
    return '节点在线 ·  ';
  }

  @override
  String nodeDetail_offlineWithError(String error) {
    return '节点离线：';
  }

  @override
  String nodeDetail_notLocalAddress(String name) {
    return '「」不是本地地址，请确认 irix-node 已在该服务器上运行。';
  }

  @override
  String nodeDetail_cannotGetInfo(String url) {
    return '无法获取节点信息\n';
  }

  @override
  String nodeDetail_daemonCount(int count) {
    return ' 个';
  }

  @override
  String nodeDetail_runningTotal(int running, int total) {
    return '运行  / 共  ';
  }

  @override
  String nodeDetail_daemonListLine(
    String status,
    String version,
    String ip,
    int port,
  ) {
    return ' ·  · ';
  }

  @override
  String nodeDetail_instanceCount(int count) {
    return '共  个实例';
  }

  @override
  String nodeDetail_deleteUserConfirm(String username) {
    return '删除用户「」？';
  }

  @override
  String nodeDetail_registered(String time) {
    return '注册  ';
  }

  @override
  String nodeDetail_instancesCount(int count) {
    return '实例  个';
  }

  @override
  String nodeDetail_installingJdk(int major) {
    return '安装 JDK  中…';
  }

  @override
  String nodeDetail_jdkInstalled(int major) {
    return 'JDK  安装完成';
  }

  @override
  String nodeDetail_jdkInstallFailed(int major) {
    return 'JDK  安装失败';
  }

  @override
  String nodeDetail_uninstallJdkTitle(int major) {
    return '卸载 JDK ？';
  }

  @override
  String nodeDetail_uninstallJdkContent(String data) {
    return '将从节点 $data/jdk 删除该版本。';
  }

  @override
  String nodeDetail_importedInstance(String uuid) {
    return '已导入实例 ，请在「实例」标签页查看';
  }

  @override
  String nodeDetail_importFailedWith(String error) {
    return '导入失败：';
  }

  @override
  String nodeDetail_coreDownloadStarted(String jobId) {
    return '已开始下载核心（任务 ），进度见节点日志';
  }

  @override
  String nodeDetail_coreDownloadFailed(String error) {
    return '核心下载失败：';
  }

  @override
  String nodeDetail_loadFailed(String error) {
    return '读取负载失败：';
  }

  @override
  String nodeDetail_auditFailed(String error) {
    return '读取审计日志失败：';
  }

  @override
  String nodeDetail_javaRuntimeDesc(String data) {
    return '检测节点上的 Java 安装；可安装 Adoptium JDK 到 $data/jdk。';
  }

  @override
  String nodeDetail_installJdk(int major) {
    return '安装 JDK  ';
  }

  @override
  String get frp_remotePortLabel => '远程端口';

  @override
  String get nodeDetail_cannotConnect => '无法连接';

  @override
  String nodeDetail_uptimeDaysHours(int days, int hours) {
    return '$days天 $hours小时';
  }

  @override
  String nodeDetail_uptimeHoursMinutes(int hours, int minutes) {
    return '$hours小时 $minutes分钟';
  }

  @override
  String nodeDetail_uptimeMinutes(int minutes) {
    return '$minutes分钟';
  }

  @override
  String get nodeDetail_startCommandHelper =>
      '启动命令（如 java -Xmx2G -jar server.jar nogui）';

  @override
  String get remoteTab_statusListRoot => '获取实例根目录列表…';

  @override
  String get remoteTab_statusCompressing => '节点端压缩实例目录…（大实例可能较慢）';

  @override
  String get remoteTab_saveBackup => '保存备份';

  @override
  String get remoteTab_statusDownloading => '下载备份…';

  @override
  String remoteTab_backupSaved(String path) {
    return '备份已保存到 $path';
  }

  @override
  String get clusterHome_title => '主页';

  @override
  String get clusterHome_refreshStatus => '刷新状态';

  @override
  String get clusterHome_addNode => '添加节点';

  @override
  String get clusterHome_noNodes => '还没有节点，点击右上角 + 添加';

  @override
  String get clusterHome_noNodesHint => '多机模式需要至少 2 个节点（MCSM 面板或 IriX 本地节点）';

  @override
  String get clusterHome_monitorMutual => '节点互相监控';

  @override
  String get clusterHome_monitorNoEligible =>
      '节点 ≥3 台，但均为 MCSM，无可用监控节点（MCSM 不支持节点互联）';

  @override
  String get clusterHome_monitorInsufficient => '至少需要 2 个节点才能形成集群';

  @override
  String get clusterHome_networkThroughput => '网络吞吐（所有节点）';

  @override
  String get clusterHome_resourceOverview => '节点资源总览';

  @override
  String get clusterHome_colNode => '节点';

  @override
  String get clusterHome_colCpu => 'CPU';

  @override
  String get clusterHome_colMemory => '内存';

  @override
  String get clusterHome_colDisk => '磁盘';

  @override
  String get clusterHome_total => '合计';

  @override
  String get clusterHome_monitor => '监控';

  @override
  String clusterHome_cpuTooltip(Object pct) {
    return 'CPU $pct%';
  }

  @override
  String clusterHome_memoryTooltip(Object detail, Object pct) {
    return '内存 $pct%（$detail）';
  }

  @override
  String clusterHome_diskTooltip(Object detail, Object pct) {
    return '磁盘 $pct%（$detail）';
  }

  @override
  String get clusterInstances_title => '实例管理';

  @override
  String get clusterInstances_newInstance => '新建实例';

  @override
  String get clusterInstances_empty => '暂无集群实例，点击右上角「新建实例」';

  @override
  String get clusterInstances_noNodeToMigrate => '没有其它节点可迁移';

  @override
  String get clusterInstances_node => '节点';

  @override
  String get clusterInstances_workdir => '工作目录（服务器上的绝对路径）';

  @override
  String get clusterInstances_autoAllocate => '自动（按资源分配）';

  @override
  String get clusterInstances_newClusterInstance => '新建集群实例';

  @override
  String get clusterInstances_selectMigrateTarget => '选择迁移目标节点';

  @override
  String get clusterInstances_migrate => '迁移';

  @override
  String get clusterContainer_noNodes => '还没有节点';

  @override
  String get clusterContainer_noNodesHint =>
      '添加 Linux 节点管理 Docker、添加 FreeBSD 节点管理 Bastille';

  @override
  String get clusterContainer_addNode => '添加节点';

  @override
  String get clusterContainer_node => '节点';

  @override
  String get clusterContainer_onlineDetecting => '在线 · 探测中…';

  @override
  String clusterContainer_nodeOffline(Object name) {
    return '节点离线：$name';
  }

  @override
  String get clusterOrch_title => '编排服务';

  @override
  String get clusterOrch_subtitle => 'K8s 风格：自动修复崩溃 · 按在线人数弹性开服 · 跨物理机迁移存档';

  @override
  String get clusterOrch_reconcileNow => '立即对账';

  @override
  String get clusterOrch_newService => '新建服务';

  @override
  String get clusterOrch_noServices => '还没有编排服务';

  @override
  String get clusterOrch_noServicesHint =>
      '新建服务后，引擎将自动调度副本到 Docker / Bastille 节点';

  @override
  String get clusterOrch_migrationTasks => '迁移任务';

  @override
  String get clusterOrch_runtimeBastille => 'Bastille';

  @override
  String get clusterOrch_runtimeDocker => 'Docker';

  @override
  String get clusterOrch_scaleDown => '缩容';

  @override
  String get clusterOrch_scaleUp => '扩容';

  @override
  String get clusterOrch_migrateArchive => '迁移存档到其它节点';

  @override
  String get clusterOrch_deleteServiceMenuItem => '删除服务';

  @override
  String get clusterOrch_autoHeal => '自动修复崩溃';

  @override
  String get clusterOrch_autoscale => '弹性开服';

  @override
  String get clusterOrch_noSchedulableNode => '无满足条件的节点';

  @override
  String get clusterOrch_continueMigration => '继续执行';

  @override
  String get clusterOrch_cancelMigration => '取消迁移';

  @override
  String get clusterOrch_newServiceDialog => '新建编排服务';

  @override
  String get clusterOrch_serviceName => '服务名称';

  @override
  String get clusterOrch_runtime => '运行时';

  @override
  String get clusterOrch_runtimeDockerLinux => 'Docker（Linux 节点）';

  @override
  String get clusterOrch_runtimeBastilleFbsd => 'Bastille（FreeBSD 节点）';

  @override
  String get clusterOrch_imageOrRelease => '镜像 / 发行版';

  @override
  String get clusterOrch_imageHintRelease => '如 14.2-RELEASE';

  @override
  String get clusterOrch_imageHintDocker => '如 itzg/minecraft-server:latest';

  @override
  String get clusterOrch_portsMapping => '端口映射（扩容时宿主端口按序号顺延）';

  @override
  String get clusterOrch_volumeMount => '数据目录挂载（宿主机:容器内）';

  @override
  String get clusterOrch_volumeMountHint => '如 /data/mc-survival:/data';

  @override
  String get clusterOrch_worldDir => '世界存档目录（容器内，迁移对象）';

  @override
  String get clusterOrch_bastilleIpBase => 'IP 基址（副本按序号顺延，如 .50 → .51）';

  @override
  String get clusterOrch_minReplicas => '最小副本';

  @override
  String get clusterOrch_desiredReplicas => '期望副本';

  @override
  String get clusterOrch_maxReplicas => '最大副本';

  @override
  String get clusterOrch_autoscaleDesc => '弹性开服（按在线人数扩缩容）';

  @override
  String get clusterOrch_targetPlayersPerReplica => '每副本目标在线人数';

  @override
  String get clusterOrch_autoHealDesc => '自动修复崩溃（指数退避重启）';

  @override
  String get clusterOrch_migrateToPhysical => '迁移存档到其它物理机';

  @override
  String get clusterOrch_replica => '副本';

  @override
  String get clusterOrch_targetNode => '目标节点';

  @override
  String get clusterOrch_migrateFlow =>
      '迁移流程：停止副本 → 压缩世界存档 → 传输 → 目标节点恢复 → 重建并启动。';

  @override
  String get clusterOrch_startMigration => '开始迁移';

  @override
  String clusterOrch_serviceCreated(Object name) {
    return '服务已创建：$name';
  }

  @override
  String clusterOrch_createFailed(Object e) {
    return '创建失败：$e';
  }

  @override
  String clusterOrch_updateFailed(Object e) {
    return '更新失败：$e';
  }

  @override
  String clusterOrch_deleteService(Object name) {
    return '删除服务 $name';
  }

  @override
  String get clusterOrch_deleteServiceConfirm => '将销毁该服务的全部副本（容器 / jail），确定继续？';

  @override
  String get clusterOrch_migrateNeedTwoNodes => '迁移需要至少 2 个节点';

  @override
  String get clusterOrch_migrationCreated => '迁移任务已创建';

  @override
  String clusterOrch_migrateFailed(Object e) {
    return '迁移失败：$e';
  }

  @override
  String clusterOrch_deleteFailed(Object e) {
    return '删除失败：$e';
  }

  @override
  String get clusterOrch_nameAndImageRequired => '名称与镜像 / 发行版不能为空';

  @override
  String clusterOrch_replicaPending(Object indexNo) {
    return 'r$indexNo · 待调度';
  }

  @override
  String clusterOrch_replicaRunning(Object indexNo, Object nodeId) {
    return 'r$indexNo · $nodeId（运行中）';
  }

  @override
  String remoteInstance_deleteTitle(Object name) {
    return '删除实例「$name」？';
  }

  @override
  String get remoteInstance_deleteContent => '同时删除实例文件需要面板 API 权限支持。';

  @override
  String get remoteInstance_tabConsole => '控制台';

  @override
  String get remoteInstance_noLogOutput => '（暂无日志输出）';

  @override
  String get remoteInstance_commandInputHint => '输入命令（如 say hello），回车发送';

  @override
  String get remoteInstance_sendCommand => '发送命令';

  @override
  String get remoteInstance_fInstanceId => '实例 ID';

  @override
  String get remoteInstance_fName => '名称';

  @override
  String get remoteInstance_fStartCommand => '启动命令';

  @override
  String get remoteInstance_fStopCommand => '停止命令';

  @override
  String get remoteInstance_fWorkdir => '工作目录';

  @override
  String get remoteInstance_fType => '类型';

  @override
  String get remoteInstance_fProcessType => '进程类型';

  @override
  String get remoteInstance_fFileEncoding => '文件编码';

  @override
  String get remoteInstance_fInputEncoding => '输入编码';

  @override
  String get remoteInstance_fOutputEncoding => '输出编码';

  @override
  String get remoteInstance_fAutoStart => '自动启动';

  @override
  String get remoteInstance_fAutoRestart => '自动重启';

  @override
  String get remoteInstance_fStartCount => '启动次数';

  @override
  String get remoteInstance_fPid => '进程 PID';

  @override
  String get remoteInstance_fContainerName => '容器名称';

  @override
  String get remoteInstance_fImage => '镜像';

  @override
  String get remoteInstance_fMemoryLimit => '内存限制';

  @override
  String get remoteInstance_fPortMapping => '端口映射';

  @override
  String get remoteInstance_fExtraVolumes => '额外挂载卷';

  @override
  String get remoteInstance_fNetworkMode => '网络模式';

  @override
  String get remoteInstance_editConfig => '编辑配置';

  @override
  String get remoteInstance_editConfigDialog => '编辑实例配置';

  @override
  String get remoteInstance_autoRestartToggle => '崩溃后自动重启';

  @override
  String get remoteInstance_processUniversal => '通用（直接运行进程）';

  @override
  String get remoteInstance_processDocker => 'Docker（容器内运行）';

  @override
  String get remoteInstance_dockerImage => 'Docker 镜像（如 mcsm-ubuntu:22.04）';

  @override
  String get remoteInstance_memoryLimitMb => '内存限制（MB）';

  @override
  String get remoteInstance_portsMapping => '端口映射（逗号分隔，如 25565:25565/tcp）';

  @override
  String get remoteInstance_extraVolumes => '额外挂载卷（逗号分隔，如 /data:/data）';

  @override
  String get remoteInstance_containerNameAuto => '容器名称（可留空自动生成）';

  @override
  String get remoteFile_noDaemonId => '无法确定守护进程 ID';

  @override
  String get remoteFile_newFolder => '新建文件夹';

  @override
  String get remoteFile_folderName => '文件夹名称';

  @override
  String get remoteFile_newFile => '新建文件';

  @override
  String get remoteFile_fileName => '文件名称';

  @override
  String get remoteFile_selectFilesToUpload => '选择要上传的文件';

  @override
  String get remoteFile_saveFile => '保存文件';

  @override
  String get remoteFile_fileTooLarge => '文件过大（>2MB），请下载后编辑';

  @override
  String remoteFile_editFile(Object name) {
    return '编辑 $name';
  }

  @override
  String get remoteFile_saved => '已保存';

  @override
  String remoteFile_rename(Object name) {
    return '重命名 $name';
  }

  @override
  String get remoteFile_newName => '新名称';

  @override
  String remoteFile_compress(Object name) {
    return '压缩 $name';
  }

  @override
  String get remoteFile_archiveName => '压缩包文件名';

  @override
  String get remoteFile_folder => '文件夹';

  @override
  String get remoteFile_download => '下载';

  @override
  String get remoteFile_edit => '编辑';

  @override
  String get remoteFile_renameAction => '重命名';

  @override
  String get remoteFile_unzipHere => '解压到当前目录';

  @override
  String get remoteFile_compressZip => '压缩为 ZIP';

  @override
  String clusterHome_monitorAssigned(String name) {
    return '已指定监控节点：$name';
  }

  @override
  String clusterHome_nodeCount(int count) {
    return '$count 台节点';
  }

  @override
  String clusterHome_systemInfo(String sys, String ver) {
    return '系统：$sys$ver';
  }

  @override
  String clusterInstances_cannotOpenDetail(String e) {
    return '无法打开详情: $e';
  }

  @override
  String clusterInstances_nodeOf(String name) {
    return '节点：$name';
  }

  @override
  String clusterInstances_crashLine(int count, String sync) {
    return '崩溃 $count 次 · 上次同步 $sync';
  }

  @override
  String clusterContainer_onlineWith(String runtime) {
    return '在线 · $runtime';
  }

  @override
  String clusterOrch_replicaStat(
    int running,
    int desired,
    int players,
    String avg,
  ) {
    return '$running/$desired 副本 · 在线 $players（均 $avg）';
  }

  @override
  String clusterOrch_scaleTarget(int target, int down, int up) {
    return '目标 $target/副本 · 阈值 $down~$up';
  }

  @override
  String remoteInstance_downloadedTo(String path) {
    return '已下载到 $path';
  }

  @override
  String get market_typePlugin => '插件';

  @override
  String get market_sortRelevance => '相关度';

  @override
  String get market_sortDownloads => '下载量';

  @override
  String get market_sortFollows => '关注数';

  @override
  String get market_sortNewest => '最新发布';

  @override
  String get market_sortUpdated => '最近更新';

  @override
  String get market_searchHint => '搜索 Mod / 插件...';

  @override
  String get market_type => '类型';

  @override
  String get market_sort => '排序';

  @override
  String get market_loader => '核心';

  @override
  String get market_all => '全部';

  @override
  String get market_gameVersion => '游戏版本';

  @override
  String get market_noResults => '未找到相关项目';

  @override
  String get market_downloads => '下载';

  @override
  String get market_stars => '收藏';

  @override
  String get hangar_downloadRejected => '下载被拒绝：文件名包含非法路径字符';

  @override
  String get hangar_viewPath => '查看路径';

  @override
  String get hangar_description => '描述';

  @override
  String get hangar_notFound => '未找到项目';

  @override
  String get hangar_downloads => '下载';

  @override
  String get hangar_stars => '收藏';

  @override
  String get hangar_platform => '平台';

  @override
  String get mod_downloadRejected => '下载被拒绝：文件名为空或包含非法路径字符';

  @override
  String get mod_openDirectory => '打开目录';

  @override
  String get mod_notFound => '未找到项目';

  @override
  String get mod_description => '描述';

  @override
  String get mod_versionList => '版本列表';

  @override
  String get mod_downloads => '下载';

  @override
  String get mod_follows => '关注';

  @override
  String get pluginsUI_empty => '暂无插件 / Mod';

  @override
  String get pluginsUI_emptyHint => '将插件放入 plugins/、Mod 放入 mods/ 后重新扫描';

  @override
  String get pluginsUI_sectionPlugins => '插件';

  @override
  String get pluginsUI_sectionMods => 'Mod';

  @override
  String get pluginsUI_kindPlugin => '插件';

  @override
  String get pluginsUI_noConfig => '无配置';

  @override
  String get pluginsUI_configOnly => '仅配置';

  @override
  String get download_title => '下载核心';

  @override
  String get download_step1 => '第一步 · 选择核心与版本';

  @override
  String get download_source => '下载来源';

  @override
  String get download_mslSource => 'MSL 镜像源';

  @override
  String get download_mslAttribution => '本服务由 MSL 开服器提供';

  @override
  String get download_serverCore => '服务器核心';

  @override
  String get download_selectCore => '请选择核心';

  @override
  String get download_serverVersion => '服务器版本';

  @override
  String get download_selectCoreFirst => '请先选择核心';

  @override
  String get download_noVersionsForCore => '该核心暂无可用版本';

  @override
  String get download_selectVersion => '请选择版本';

  @override
  String get download_nextStep => '下一步';

  @override
  String get download_scenario => '适用场景';

  @override
  String download_scenarioWithCategory(String scenario, String category) {
    return '$scenario（$category）';
  }

  @override
  String get download_loadFailed => '加载失败';

  @override
  String get download_description => '简介';

  @override
  String get download_downloadFailed => '下载失败';

  @override
  String get download_step2 => '第二步 · 下载核心文件';

  @override
  String get download_downloadingHint => '正在下载…请勿离开';

  @override
  String get download_step3 => '第三步 · 编辑启动命令';

  @override
  String get download_command => '启动命令';

  @override
  String get download_finishCreate => '完成并创建实例';

  @override
  String get dbScreen_saved => '已保存';

  @override
  String get dbScreen_deleteTitle => '删除连接';

  @override
  String get dbScreen_deleted => '已删除';

  @override
  String get dbScreen_connectionFailed => '连接失败';

  @override
  String get dbScreen_title => '数据库';

  @override
  String get dbScreen_addConnection => '添加连接';

  @override
  String get dbScreen_manageHint =>
      '管理 MySQL / MariaDB / PostgreSQL / Redis 服务器连接';

  @override
  String get dbScreen_emptyTitle => '还没有数据库连接';

  @override
  String get dbScreen_emptyAddHint => '点击右上角添加';

  @override
  String get dbScreen_connect => '连接';

  @override
  String get dbScreen_nameRequired => '请输入名称';

  @override
  String get dbScreen_hostRequired => '请输入主机地址';

  @override
  String get dbScreen_portRange => '端口需在 1-65535 之间';

  @override
  String get dbScreen_editTitle => '编辑连接';

  @override
  String get dbScreen_host => '主机';

  @override
  String get dbScreen_hostHint => '例如 127.0.0.1';

  @override
  String get dbScreen_port => '端口';

  @override
  String get dbScreen_usernameOptional => '用户名（可选）';

  @override
  String get dbScreen_passwordOptional => '密码（可选）';

  @override
  String get dbScreen_databaseNameOptional => '数据库名（可选）';

  @override
  String get dbScreen_useSsl => '使用 SSL 连接';

  @override
  String get dbScreen_sslSubtitle =>
      '加密传输（MySQL/MariaDB/PostgreSQL/Redis，验证服务器证书）';

  @override
  String get nodes_title => '节点';

  @override
  String get nodes_refreshStatus => '刷新状态';

  @override
  String get nodes_addNode => '添加节点';

  @override
  String get nodes_empty => '还没有节点，点击右上角 + 添加';

  @override
  String get nodes_emptyHint =>
      'MCSM：连接 MCSManager 面板\nNode：本地 Go 语言节点（node/ 目录）';

  @override
  String get nodes_daemonRunning => '本地节点守护进程正在运行';

  @override
  String get nodes_daemonHint => '提示：Node 类型节点需要先运行 node/ 目录构建的 irix-node 服务';

  @override
  String hangar_installedToNode(String nodeName) {
    return '已安装到节点 $nodeName 的 plugins/';
  }

  @override
  String hangar_downloadedTo(String path) {
    return '已下载到 $path';
  }

  @override
  String hangar_directory(String path) {
    return '目录: $path';
  }

  @override
  String hangar_downloadFailed(String error) {
    return '下载失败: $error';
  }

  @override
  String hangar_publishedOn(String date) {
    return '发布于 $date';
  }

  @override
  String hangar_versionList(int count) {
    return '版本列表 ($count)';
  }

  @override
  String mod_downloadFailed(String error) {
    return '下载失败: $error';
  }

  @override
  String mod_downloadedTo(String path) {
    return '已下载到 $path';
  }

  @override
  String mod_installedToNode(String nodeName, String dir) {
    return '已安装到节点 $nodeName 的 $dir/';
  }

  @override
  String mod_directory(String path) {
    return '目录: $path';
  }

  @override
  String mod_publishedOn(String date) {
    return '发布于 $date';
  }

  @override
  String pluginsUI_noConfigFiles(String name) {
    return '$name 暂无可管理的配置文件';
  }

  @override
  String download_downloaded(String size) {
    return '已下载 $size';
  }

  @override
  String download_speed(String speed) {
    return '速度 $speed/s';
  }

  @override
  String download_coreFile(String fileName) {
    return '核心文件：$fileName';
  }

  @override
  String dbScreen_deleteConfirm(String name) {
    return '确定删除 \"$name\"？此操作不会影响远程服务器。';
  }

  @override
  String get newInstance_download => '下载';

  @override
  String get newInstance_downloadDesc => '自动下载核心并新建服务器实例';

  @override
  String get newInstance_import => '导入';

  @override
  String get newInstance_importDesc => '导入一个服务器核心新建服务器实例';

  @override
  String get importCore_title => '导入核心';

  @override
  String get importCore_coreFile => '核心文件';

  @override
  String get importCore_coreFileHint => '选择 .jar 核心文件';

  @override
  String get importCore_browse => '浏览';

  @override
  String get importCore_rootPath => '服务器根目录路径';

  @override
  String get importCore_rootPathHint => '选择或输入服务器根目录';

  @override
  String get importCore_startCommandHint => 'java -Xmx2G -jar <jar文件名> nogui';

  @override
  String get importCore_creating => '创建中…';

  @override
  String get importCore_createInstance => '创建实例';

  @override
  String get importCore_desc => '导入已下载的核心 .jar 文件并基于它创建一个新实例。';

  @override
  String get importCore_fillAllFields => '请填写核心文件、服务器根目录路径与启动命令';

  @override
  String get importInstance_title => '导入实例';

  @override
  String get importInstance_instanceName => '实例名称';

  @override
  String get importInstance_instanceNameHint => '留空则自动分配随机名称';

  @override
  String get importInstance_rootPath => '服务器根目录路径';

  @override
  String get importInstance_rootPathHint => '选择或输入服务器根目录';

  @override
  String get importInstance_startCommandHint =>
      'java -Xmx2G -jar server.jar nogui';

  @override
  String get importInstance_browse => '浏览';

  @override
  String get importInstance_creating => '创建中…';

  @override
  String get importInstance_createInstance => '创建实例';

  @override
  String get importInstance_desc => '导入一个已存在的服务器目录，使用其原有文件结构。';

  @override
  String get importInstance_fillRequired => '请填写服务器根目录路径与启动命令';

  @override
  String get trash_title => '回收站';

  @override
  String get trash_purge => '清空';

  @override
  String get trash_empty => '回收站为空';

  @override
  String get trash_purgeTitle => '清空回收站';

  @override
  String get trash_purgeAllConfirm => '确定要永久删除所有实例回收站中的文件吗？此操作不可撤销。';

  @override
  String get trash_purgeScopeConfirm => '确定要永久删除该实例回收站中的所有文件吗？此操作不可撤销。';

  @override
  String get trash_purged => '回收站已清空';

  @override
  String get trash_restore => '恢复';

  @override
  String get trash_permanentlyDelete => '永久删除';

  @override
  String get archive_selectExtractDir => '选择解压目标文件夹';

  @override
  String get archive_extractTo => '解压到...';

  @override
  String get archive_cannotOpen => '无法打开压缩文件';

  @override
  String get archive_invalidArchiveHint => '请确认该文件是有效的 ZIP/JAR 归档文件';

  @override
  String get archive_emptyArchive => '归档文件为空';

  @override
  String get archive_colName => '文件名';

  @override
  String get archive_colSize => '大小';

  @override
  String get archive_colModified => '修改时间';

  @override
  String get textEditor_undo => '撤回';

  @override
  String get textEditor_cannotRead => '无法读取文件';

  @override
  String get onboarding_title => 'IriX';

  @override
  String get onboarding_create => '新建';

  @override
  String get onboarding_createDesc => '新建一个MC服务器实例';

  @override
  String get onboarding_import => '导入';

  @override
  String get onboarding_importDesc => '导入一个MC服务器实例';

  @override
  String get remoteTab_restoreFailed => '恢复失败';

  @override
  String get remoteTab_snapshotFailed => '快照失败';

  @override
  String get remoteTab_unzippingOnNode => '节点端解压中…';

  @override
  String get remoteTab_uploadingBackup => '上传备份…';

  @override
  String trash_purgeFailed(String e) {
    return '清空失败: $e';
  }

  @override
  String trash_restored(String path) {
    return '已恢复 \"$path\"';
  }

  @override
  String trash_restoreFailed(String e) {
    return '恢复失败: $e';
  }

  @override
  String trash_permanentlyDeleted(String path) {
    return '已永久删除 \"$path\"';
  }

  @override
  String trash_deleteFailed(String e) {
    return '删除失败: $e';
  }

  @override
  String trash_deletedAt(String date) {
    return '删除于 $date';
  }

  @override
  String trash_groupHeader(String label, int count) {
    return '$label · $count 项';
  }

  @override
  String trash_today(String time) {
    return '今天 $time';
  }

  @override
  String trash_yesterday(String time) {
    return '昨天 $time';
  }

  @override
  String archive_extracted(String name) {
    return '已解压: $name';
  }

  @override
  String archive_extractFailed(String e) {
    return '解压失败: $e';
  }

  @override
  String archive_entryCount(int count) {
    return '$count 个条目';
  }

  @override
  String archive_fileNotFound(String path) {
    return '文件不存在: $path';
  }

  @override
  String get common_download => '下载';

  @override
  String remoteFile_downloadedTo(String path) {
    return '已下载到 $path';
  }
}
