// 配置项中文说明
// 为 server.properties、bukkit.yml、spigot.yml、paper-global.yml、paper-world-defaults.yml
// 中的配置项提供中文说明。
//
// 键格式：`文件名.配置项路径`，嵌套用 `.` 分隔。
// 例如：`server.properties.max-players`、`paper-global.yml.anticheat.obfuscation.enable-item-obfuscation`

/// 根据文件名和配置项路径获取硬编码的中文说明。
///
/// 仅查找硬编码的内置注释。要获取包含 CSV 导入注释的完整查找，
/// 使用 `ConfigAnnotationService.instance.get()`。
///
/// [fileName] 配置文件名（如 `server.properties`）。
/// [keyPath] 配置项路径，嵌套用 `.` 分隔（如 `max-players` 或 `anticheat.obfuscation`）。
/// 返回中文说明，未找到时返回 null。
String? getConfigDescriptionHardcoded(String fileName, String keyPath) {
  return _descriptions['$fileName.$keyPath'];
}

const Map<String, String> _descriptions = {
  // ==================== server.properties ====================
  'server.properties.accepts-transfers': '是否接受从其他服务器转移过来的玩家',
  'server.properties.allow-flight': '是否允许玩家飞行（非创造模式）',
  'server.properties.broadcast-console-to-ops': '是否将控制台消息广播给管理员',
  'server.properties.broadcast-rcon-to-ops': '是否将 RCON 消息广播给管理员',
  'server.properties.bug-report-link': 'Bug 报告链接',
  'server.properties.debug': '是否开启调试模式',
  'server.properties.difficulty': '游戏难度（peaceful/easy/normal/hard）',
  'server.properties.enable-code-of-conduct': '是否启用行为准则',
  'server.properties.enable-jmx-monitoring': '是否启用 JMX 监控',
  'server.properties.enable-query': '是否启用 GameSpy4 查询协议',
  'server.properties.enable-rcon': '是否启用远程控制台（RCON）',
  'server.properties.enable-status': '是否在服务器列表中显示状态',
  'server.properties.enforce-secure-profile': '是否强制安全配置文件',
  'server.properties.enforce-whitelist': '是否强制使用白名单',
  'server.properties.entity-broadcast-range-percentage': '实体广播范围百分比',
  'server.properties.force-gamemode': '是否强制玩家使用指定游戏模式',
  'server.properties.function-permission-level': '函数权限等级（0-4）',
  'server.properties.gamemode': '默认游戏模式（survival/creative/adventure/spectator）',
  'server.properties.generate-structures': '是否生成结构（村庄、神殿等）',
  'server.properties.generator-settings': '世界生成器设置（JSON）',
  'server.properties.hardcore': '是否开启极限模式（死亡后封禁）',
  'server.properties.hide-online-players': '是否隐藏在线玩家列表',
  'server.properties.initial-disabled-packs': '初始禁用的数据包',
  'server.properties.initial-enabled-packs': '初始启用的数据包',
  'server.properties.level-name': '世界名称（存档文件夹名）',
  'server.properties.level-seed': '世界种子（留空为随机）',
  'server.properties.level-type': '世界类型（如 minecraft:normal）',
  'server.properties.log-ips': '是否记录玩家 IP',
  'server.properties.max-chained-neighbor-updates': '最大连锁邻居方块更新次数',
  'server.properties.max-players': '最大玩家数',
  'server.properties.max-tick-time': '最大 Tick 时间（毫秒），超时触发看门狗',
  'server.properties.max-world-size': '世界最大尺寸（半径，方块）',
  'server.properties.motd': '服务器 MOTD 描述信息',
  'server.properties.network-compression-threshold': '网络压缩阈值（字节）',
  'server.properties.online-mode': '是否开启正版验证',
  'server.properties.op-permission-level': '管理员权限等级（0-4）',
  'server.properties.pause-when-empty-seconds': '无人时暂停 Tick 的秒数（-1 禁用）',
  'server.properties.player-idle-timeout': '玩家挂机踢出超时（分钟，0 禁用）',
  'server.properties.prevent-proxy-connections': '是否阻止代理连接',
  'server.properties.query.port': '查询协议端口',
  'server.properties.rate-limit': '数据包速率限制（0 禁用）',
  'server.properties.rcon.password': 'RCON 密码',
  'server.properties.rcon.port': 'RCON 端口',
  'server.properties.region-file-compression': '区域文件压缩格式',
  'server.properties.require-resource-pack': '是否强制使用资源包',
  'server.properties.resource-pack': '资源包下载链接',
  'server.properties.resource-pack-id': '资源包 UUID',
  'server.properties.resource-pack-prompt': '资源包提示信息',
  'server.properties.resource-pack-sha1': '资源包 SHA1 校验值',
  'server.properties.server-ip': '服务器绑定的 IP（留空为所有接口）',
  'server.properties.server-name': '服务器名称',
  'server.properties.server-port': '服务器端口',
  'server.properties.simulation-distance': '模拟距离（区块）',
  'server.properties.spawn-protection': '出生保护半径（方块）',
  'server.properties.sync-chunk-writes': '是否同步写入区块数据',
  'server.properties.use-native-transport': '是否使用原生网络传输（Linux）',
  'server.properties.view-distance': '视距（区块）',
  'server.properties.white-list': '是否启用白名单',

  // ==================== bukkit.yml ====================
  'bukkit.yml.settings.allow-end': '是否允许末地',
  'bukkit.yml.settings.warn-on-overload': '服务器过载时是否警告',
  'bukkit.yml.settings.permissions-file': '权限文件名',
  'bukkit.yml.settings.update-folder': '插件更新文件夹',
  'bukkit.yml.settings.plugin-profiling': '是否启用插件性能分析',
  'bukkit.yml.settings.connection-throttle': '连接限流（毫秒）',
  'bukkit.yml.settings.query-plugins': '是否在查询中显示插件列表',
  'bukkit.yml.settings.deprecated-verbose': '弃用 API 详细日志',
  'bukkit.yml.settings.shutdown-message': '关闭服务器时显示的消息',
  'bukkit.yml.settings.minimum-api': '最低 API 版本',
  'bukkit.yml.settings.use-map-color-cache': '是否使用地图颜色缓存',
  'bukkit.yml.spawn-limits.monsters': '怪物生成上限',
  'bukkit.yml.spawn-limits.animals': '动物生成上限',
  'bukkit.yml.spawn-limits.water-animals': '水生动物生成上限',
  'bukkit.yml.spawn-limits.water-ambient': '水生环境生物生成上限',
  'bukkit.yml.spawn-limits.water-underground-creature': '地下水生生物生成上限',
  'bukkit.yml.spawn-limits.axolotls': '美西螈生成上限',
  'bukkit.yml.spawn-limits.ambient': '环境生物生成上限（蝙蝠等）',
  'bukkit.yml.chunk-gc.period-in-ticks': '区块垃圾回收间隔（Tick）',
  'bukkit.yml.ticks-per.animal-spawns': '动物生成间隔（Tick）',
  'bukkit.yml.ticks-per.monster-spawns': '怪物生成间隔（Tick）',
  'bukkit.yml.ticks-per.water-spawns': '水生生物生成间隔（Tick）',
  'bukkit.yml.ticks-per.water-ambient-spawns': '水生环境生物生成间隔（Tick）',
  'bukkit.yml.ticks-per.water-underground-creature-spawns': '地下水生生物生成间隔（Tick）',
  'bukkit.yml.ticks-per.axolotl-spawns': '美西螈生成间隔（Tick）',
  'bukkit.yml.ticks-per.ambient-spawns': '环境生物生成间隔（Tick）',
  'bukkit.yml.ticks-per.autosave': '自动保存间隔（Tick）',

  // ==================== spigot.yml ====================
  'spigot.yml.settings.debug': '是否开启调试模式',
  'spigot.yml.settings.bungeecord': '是否启用 BungeeCord 代理支持',
  'spigot.yml.settings.sample-count': 'MOTD 采样数',
  'spigot.yml.settings.save-user-cache-on-stop-only': '仅在关闭时保存用户缓存',
  'spigot.yml.settings.user-cache-size': '用户缓存大小',
  'spigot.yml.settings.moved-wrongly-threshold': '错误移动检测阈值',
  'spigot.yml.settings.player-shuffle': '玩家洗牌（防止卡顿）',
  'spigot.yml.settings.moved-too-quickly-multiplier': '过快移动倍率',
  'spigot.yml.settings.netty-threads': 'Netty 网络线程数',
  'spigot.yml.settings.log-villager-deaths': '是否记录村民死亡日志',
  'spigot.yml.settings.log-named-deaths': '是否记录命名实体死亡日志',
  'spigot.yml.settings.timeout-time': '超时时间（秒），超时触发看门狗重启',
  'spigot.yml.settings.restart-on-crash': '崩溃时是否自动重启',
  'spigot.yml.settings.restart-script': '重启脚本路径',
  'spigot.yml.advancements.disable-saving': '是否禁用成就保存',
  'spigot.yml.messages.whitelist': '白名单拒绝消息',
  'spigot.yml.messages.unknown-command': '未知命令提示',
  'spigot.yml.messages.server-full': '服务器满员消息',
  'spigot.yml.messages.outdated-client': '客户端版本过低提示',
  'spigot.yml.messages.outdated-server': '服务器版本过低提示',
  'spigot.yml.messages.restart': '重启提示消息',
  'spigot.yml.players.disable-saving': '是否禁用玩家数据保存',
  'spigot.yml.stats.disable-saving': '是否禁用统计数据保存',
  'spigot.yml.commands.silent-commandblock-console': '命令方块是否静默执行',
  'spigot.yml.commands.tab-complete': 'Tab 自动补全（0=禁用，1=仅命令，2=带参数）',
  'spigot.yml.commands.send-namespaced': '是否发送命名空间命令',
  'spigot.yml.commands.log': '是否记录命令日志',
  'spigot.yml.commands.enable-spam-exclusions': '是否启用垃圾命令排除',
  'spigot.yml.world-settings.default.below-zero-generation-in-existing-chunks':
      '现有区块中是否生成 Y=0 以下内容',
  'spigot.yml.world-settings.default.simulation-distance': '模拟距离（区块）',
  'spigot.yml.world-settings.default.view-distance': '视距（区块）',
  'spigot.yml.world-settings.default.hunger.jump-walk-exhaustion': '跳跃行走饥饿消耗',
  'spigot.yml.world-settings.default.hunger.jump-sprint-exhaustion': '跳跃疾跑饥饿消耗',
  'spigot.yml.world-settings.default.hunger.combat-exhaustion': '战斗饥饿消耗',
  'spigot.yml.world-settings.default.hunger.regen-exhaustion': '生命恢复饥饿消耗',
  'spigot.yml.world-settings.default.hunger.swim-multiplier': '游泳饥饿倍率',
  'spigot.yml.world-settings.default.hunger.sprint-multiplier': '疾跑饥饿倍率',
  'spigot.yml.world-settings.default.hunger.other-multiplier': '其他饥饿倍率',
  'spigot.yml.world-settings.default.ticks-per.hopper-transfer': '漏斗传输间隔（Tick）',
  'spigot.yml.world-settings.default.ticks-per.hopper-check': '漏斗检测间隔（Tick）',
  'spigot.yml.world-settings.default.hopper-amount': '漏斗每次传输数量',
  'spigot.yml.world-settings.default.hopper-can-load-chunks': '漏斗是否可加载区块',
  'spigot.yml.world-settings.default.merge-radius.exp': '经验球合并半径',
  'spigot.yml.world-settings.default.merge-radius.item': '掉落物合并半径',
  'spigot.yml.world-settings.default.mob-spawn-range': '怪物生成范围（区块）',
  'spigot.yml.world-settings.default.item-despawn-rate': '掉落物消失间隔（Tick）',
  'spigot.yml.world-settings.default.thunder-chance': '雷雨概率',
  'spigot.yml.world-settings.default.unload-frozen-chunks': '是否卸载冻结区块',
  'spigot.yml.world-settings.default.end-portal-sound-radius': '末地传送门声音半径',
  'spigot.yml.world-settings.default.arrow-despawn-rate': '箭矢消失间隔（Tick）',
  'spigot.yml.world-settings.default.trident-despawn-rate': '三叉戟消失间隔（Tick）',
  'spigot.yml.world-settings.default.growth.cactus-modifier': '仙人掌生长速度（%）',
  'spigot.yml.world-settings.default.growth.cane-modifier': '甘蔗生长速度（%）',
  'spigot.yml.world-settings.default.growth.melon-modifier': '西瓜生长速度（%）',
  'spigot.yml.world-settings.default.growth.mushroom-modifier': '蘑菇生长速度（%）',
  'spigot.yml.world-settings.default.growth.pumpkin-modifier': '南瓜生长速度（%）',
  'spigot.yml.world-settings.default.growth.sapling-modifier': '树苗生长速度（%）',
  'spigot.yml.world-settings.default.growth.beetroot-modifier': '甜菜根生长速度（%）',
  'spigot.yml.world-settings.default.growth.carrot-modifier': '胡萝卜生长速度（%）',
  'spigot.yml.world-settings.default.growth.potato-modifier': '马铃薯生长速度（%）',
  'spigot.yml.world-settings.default.growth.wheat-modifier': '小麦生长速度（%）',
  'spigot.yml.world-settings.default.growth.netherwart-modifier': '地狱疣生长速度（%）',
  'spigot.yml.world-settings.default.growth.vine-modifier': '藤蔓生长速度（%）',
  'spigot.yml.world-settings.default.growth.cocoa-modifier': '可可豆生长速度（%）',
  'spigot.yml.world-settings.default.growth.bamboo-modifier': '竹子生长速度（%）',
  'spigot.yml.world-settings.default.growth.sweetberry-modifier': '甜浆果生长速度（%）',
  'spigot.yml.world-settings.default.growth.kelp-modifier': '海带生长速度（%）',
  'spigot.yml.world-settings.default.growth.twistingvines-modifier':
      '缠怨藤生长速度（%）',
  'spigot.yml.world-settings.default.growth.weepingvines-modifier':
      '垂泪藤生长速度（%）',
  'spigot.yml.world-settings.default.growth.cavevines-modifier': '洞穴藤蔓生长速度（%）',
  'spigot.yml.world-settings.default.growth.glowberry-modifier': '发光浆果生长速度（%）',
  'spigot.yml.world-settings.default.growth.pitcherplant-modifier':
      '瓶子草生长速度（%）',
  'spigot.yml.world-settings.default.wither-spawn-sound-radius': '凋灵生成声音半径',
  'spigot.yml.world-settings.default.hanging-tick-frequency': '悬挂实体 Tick 频率',
  'spigot.yml.world-settings.default.nerf-spawner-mobs': '是否弱化刷怪笼生成的怪物',
  'spigot.yml.world-settings.default.entity-activation-range.animals': '动物激活范围',
  'spigot.yml.world-settings.default.entity-activation-range.monsters':
      '怪物激活范围',
  'spigot.yml.world-settings.default.entity-activation-range.raiders':
      '袭击者激活范围',
  'spigot.yml.world-settings.default.entity-activation-range.misc': '杂项实体激活范围',
  'spigot.yml.world-settings.default.entity-activation-range.water': '水生实体激活范围',
  'spigot.yml.world-settings.default.entity-activation-range.villagers':
      '村民激活范围',
  'spigot.yml.world-settings.default.entity-activation-range.flying-monsters':
      '飞行怪物激活范围',
  'spigot.yml.world-settings.default.entity-tracking-range.players': '玩家跟踪范围',
  'spigot.yml.world-settings.default.entity-tracking-range.animals': '动物跟踪范围',
  'spigot.yml.world-settings.default.entity-tracking-range.monsters': '怪物跟踪范围',
  'spigot.yml.world-settings.default.entity-tracking-range.misc': '杂项实体跟踪范围',
  'spigot.yml.world-settings.default.entity-tracking-range.display': '展示实体跟踪范围',
  'spigot.yml.world-settings.default.entity-tracking-range.other': '其他实体跟踪范围',
  'spigot.yml.world-settings.default.dragon-death-sound-radius': '末影龙死亡声音半径',
  'spigot.yml.world-settings.default.max-tick-time.tile': '方块实体最大 Tick 时间',
  'spigot.yml.world-settings.default.max-tick-time.entity': '实体最大 Tick 时间',
  'spigot.yml.world-settings.default.max-tnt-per-tick': '每 Tick 最大 TNT 数量',
  'spigot.yml.world-settings.default.enable-zombie-pigmen-portal-spawns':
      '是否允许僵尸猪灵从传送门生成',
  'spigot.yml.world-settings.default.zombie-aggressive-towards-villager':
      '僵尸是否攻击村民',

  // ==================== paper-global.yml ====================
  'paper-global.yml.anticheat.obfuscation.enable-item-obfuscation':
      '是否启用物品混淆（反作弊）',
  'paper-global.yml.block-updates.disable-chorus-plant-updates': '是否禁用紫颂花更新',
  'paper-global.yml.block-updates.disable-mushroom-block-updates': '是否禁用蘑菇方块更新',
  'paper-global.yml.block-updates.disable-noteblock-updates': '是否禁用音符盒更新',
  'paper-global.yml.block-updates.disable-tripwire-updates': '是否禁用绊线更新',
  'paper-global.yml.chunk-loading-advanced.auto-config-send-distance':
      '是否自动配置区块发送距离',
  'paper-global.yml.chunk-loading-advanced.player-max-concurrent-chunk-generates':
      '玩家最大并发区块生成数（0=自动）',
  'paper-global.yml.chunk-loading-advanced.player-max-concurrent-chunk-loads':
      '玩家最大并发区块加载数（0=自动）',
  'paper-global.yml.chunk-loading-basic.player-max-chunk-generate-rate':
      '玩家最大区块生成速率（-1=无限）',
  'paper-global.yml.chunk-loading-basic.player-max-chunk-load-rate':
      '玩家最大区块加载速率',
  'paper-global.yml.chunk-loading-basic.player-max-chunk-send-rate':
      '玩家最大区块发送速率',
  'paper-global.yml.chunk-system.io-threads': '区块 IO 线程数（-1=自动）',
  'paper-global.yml.chunk-system.worker-threads': '区块工作线程数（-1=自动）',
  'paper-global.yml.collisions.enable-player-collisions': '是否启用玩家碰撞',
  'paper-global.yml.collisions.send-full-pos-for-hard-colliding-entities':
      '是否发送硬碰撞实体完整坐标',
  'paper-global.yml.commands.ride-command-allow-player-as-vehicle':
      'ride 命令是否允许玩家作为载具',
  'paper-global.yml.commands.suggest-player-names-when-null-tab-completions':
      'Tab 补全为空时是否建议玩家名',
  'paper-global.yml.commands.time-command-affects-all-worlds':
      'time 命令是否影响所有世界',
  'paper-global.yml.console.enable-brigadier-completions':
      '是否启用 Brigadier 命令补全',
  'paper-global.yml.console.enable-brigadier-highlighting':
      '是否启用 Brigadier 语法高亮',
  'paper-global.yml.console.has-all-permissions': '控制台是否拥有所有权限',
  'paper-global.yml.item-validation.book.author': '书本作者最大长度',
  'paper-global.yml.item-validation.book.page': '书页最大长度',
  'paper-global.yml.item-validation.book.title': '书名最大长度',
  'paper-global.yml.item-validation.book-size.page-max': '单页最大字节数',
  'paper-global.yml.item-validation.book-size.total-multiplier': '总字节数倍率',
  'paper-global.yml.item-validation.display-name': '显示名称最大长度',
  'paper-global.yml.item-validation.lore-line': 'Lore 行最大长度',
  'paper-global.yml.item-validation.resolve-selectors-in-books': '是否在书中解析选择器',
  'paper-global.yml.logging.deobfuscate-stacktraces': '是否反混淆堆栈跟踪',
  'paper-global.yml.messages.kick.authentication-servers-down': '认证服务器不可用时踢出消息',
  'paper-global.yml.messages.kick.connection-throttle': '连接限流踢出消息',
  'paper-global.yml.messages.kick.flying-player': '玩家飞行踢出消息',
  'paper-global.yml.messages.kick.flying-vehicle': '载具飞行踢出消息',
  'paper-global.yml.messages.no-permission': '无权限提示消息',
  'paper-global.yml.messages.use-display-name-in-quit-message': '退出消息是否使用显示名称',
  'paper-global.yml.misc.chat-threads.chat-executor-core-size':
      '聊天执行器核心线程数（-1=自动）',
  'paper-global.yml.misc.chat-threads.chat-executor-max-size':
      '聊天执行器最大线程数（-1=自动）',
  'paper-global.yml.misc.client-interaction-leniency-distance': '客户端交互宽容距离',
  'paper-global.yml.misc.compression-level': '压缩等级',
  'paper-global.yml.misc.enable-nether': '是否启用下界',
  'paper-global.yml.misc.fix-far-end-terrain-generation': '是否修复远端末地地形生成',
  'paper-global.yml.misc.load-permissions-yml-before-plugins':
      '是否在插件前加载 permissions.yml',
  'paper-global.yml.misc.max-joins-per-tick': '每 Tick 最大加入数',
  'paper-global.yml.misc.prevent-negative-villager-demand': '是否防止村民需求为负',
  'paper-global.yml.misc.region-file-cache-size': '区域文件缓存大小',
  'paper-global.yml.misc.send-full-pos-for-item-entities': '是否发送掉落物完整坐标',
  'paper-global.yml.misc.strict-advancement-dimension-check': '是否严格检查成就维度',
  'paper-global.yml.misc.use-alternative-luck-formula': '是否使用替代幸运值公式',
  'paper-global.yml.misc.use-dimension-type-for-custom-spawners':
      '自定义生成器是否使用维度类型',
  'paper-global.yml.packet-limiter.all-packets.action': '所有数据包超限动作（KICK/DROP）',
  'paper-global.yml.packet-limiter.all-packets.interval': '数据包限流检测间隔（秒）',
  'paper-global.yml.packet-limiter.all-packets.max-packet-rate': '最大数据包速率',
  'paper-global.yml.packet-limiter.kick-message': '数据包超限踢出消息',
  'paper-global.yml.player-auto-save.max-per-tick': '每 Tick 最大自动保存玩家数（-1=无限）',
  'paper-global.yml.player-auto-save.rate': '自动保存间隔（Tick，-1=默认）',
  'paper-global.yml.proxies.bungee-cord.online-mode': 'BungeeCord 在线模式',
  'paper-global.yml.proxies.proxy-protocol': '是否启用 PROXY 协议',
  'paper-global.yml.proxies.velocity.enabled': '是否启用 Velocity 代理支持',
  'paper-global.yml.proxies.velocity.online-mode': 'Velocity 在线模式',
  'paper-global.yml.proxies.velocity.secret': 'Velocity 密钥',
  'paper-global.yml.scoreboards.save-empty-scoreboard-teams': '是否保存空记分板队伍',
  'paper-global.yml.scoreboards.track-plugin-scoreboards': '是否跟踪插件记分板',
  'paper-global.yml.spam-limiter.incoming-packet-threshold': '入站数据包阈值',
  'paper-global.yml.spam-limiter.recipe-spam-increment': '配方刷屏增量',
  'paper-global.yml.spam-limiter.recipe-spam-limit': '配方刷屏上限',
  'paper-global.yml.spam-limiter.tab-spam-increment': 'Tab 刷屏增量',
  'paper-global.yml.spam-limiter.tab-spam-limit': 'Tab 刷屏上限',
  'paper-global.yml.spark.enable-immediately': '是否立即启动 spark',
  'paper-global.yml.spark.enabled': '是否启用 spark 性能分析',
  'paper-global.yml.threaded-regions.grid-exponent': '线程化区域网格指数',
  'paper-global.yml.threaded-regions.scheduler': '线程化区域调度器',
  'paper-global.yml.threaded-regions.threads': '线程化区域线程数（-1=自动）',
  'paper-global.yml.unsupported-settings.allow-headless-pistons': '是否允许无头活塞',
  'paper-global.yml.unsupported-settings.allow-permanent-block-break-exploits':
      '是否允许永久方块破坏漏洞',
  'paper-global.yml.unsupported-settings.allow-piston-duplication': '是否允许活塞复制',
  'paper-global.yml.unsupported-settings.allow-unsafe-end-portal-teleportation':
      '是否允许不安全的末地传送门传送',
  'paper-global.yml.unsupported-settings.compression-format': '压缩格式',
  'paper-global.yml.unsupported-settings.perform-username-validation':
      '是否执行用户名验证',
  'paper-global.yml.unsupported-settings.skip-tripwire-hook-placement-validation':
      '是否跳过绊线钩放置验证',
  'paper-global.yml.unsupported-settings.skip-vanilla-damage-tick-when-shield-blocked':
      '盾牌格挡时是否跳过原版伤害 Tick',
  'paper-global.yml.unsupported-settings.update-equipment-on-player-actions':
      '玩家行动时是否更新装备',
  'paper-global.yml.update-checker.enabled': '是否启用更新检查',
  'paper-global.yml.watchdog.early-warning-delay': '看门狗早期警告延迟（毫秒）',
  'paper-global.yml.watchdog.early-warning-every': '看门狗早期警告间隔（毫秒）',

  // ==================== paper-world-defaults.yml ====================
  'paper-world-defaults.yml.anticheat.anti-xray.enabled': '是否启用反透视（Anti-Xray）',
  'paper-world-defaults.yml.anticheat.anti-xray.engine-mode':
      '反透视引擎模式（1=隐藏，2=替换）',
  'paper-world-defaults.yml.anticheat.anti-xray.lava-obscures': '岩浆是否遮挡矿石',
  'paper-world-defaults.yml.anticheat.anti-xray.max-block-height': '反透视最大高度',
  'paper-world-defaults.yml.anticheat.anti-xray.update-radius': '更新半径',
  'paper-world-defaults.yml.anticheat.anti-xray.use-permission': '是否需要权限绕过反透视',
  'paper-world-defaults.yml.chunks.auto-save-interval': '自动保存间隔',
  'paper-world-defaults.yml.chunks.delay-chunk-unloads-by': '延迟卸载区块时间',
  'paper-world-defaults.yml.chunks.fixed-chunk-inhabited-time':
      '固定区块居住时间（-1=禁用）',
  'paper-world-defaults.yml.chunks.flush-regions-on-save': '保存时是否刷新区域',
  'paper-world-defaults.yml.chunks.max-auto-save-chunks-per-tick':
      '每 Tick 最大自动保存区块数',
  'paper-world-defaults.yml.chunks.prevent-moving-into-unloaded-chunks':
      '是否阻止进入未加载区块',
  'paper-world-defaults.yml.collisions.allow-player-cramming-damage':
      '是否允许玩家挤压伤害',
  'paper-world-defaults.yml.collisions.allow-vehicle-collisions': '是否允许载具碰撞',
  'paper-world-defaults.yml.collisions.fix-climbing-bypassing-cramming-rule':
      '是否修复攀爬绕过挤压规则',
  'paper-world-defaults.yml.collisions.max-entity-collisions': '最大实体碰撞数',
  'paper-world-defaults.yml.collisions.only-players-collide': '仅玩家可碰撞',
  'paper-world-defaults.yml.command-blocks.force-follow-perm-level':
      '命令方块是否强制遵循权限等级',
  'paper-world-defaults.yml.command-blocks.permissions-level': '命令方块权限等级',
  'paper-world-defaults.yml.entities.armor-stands.do-collision-entity-lookups':
      '盔甲架是否进行碰撞查找',
  'paper-world-defaults.yml.entities.armor-stands.tick': '盔甲架是否参与 Tick',
  'paper-world-defaults.yml.entities.behavior.allow-spider-world-border-climbing':
      '蜘蛛是否可攀爬世界边界',
  'paper-world-defaults.yml.entities.behavior.baby-zombie-movement-modifier':
      '小僵尸移动速度修正',
  'paper-world-defaults.yml.entities.behavior.cooldown-failed-beehive-releases':
      '蜂巢释放失败冷却',
  'paper-world-defaults.yml.entities.behavior.disable-chest-cat-detection':
      '是否禁用箱子猫检测',
  'paper-world-defaults.yml.entities.behavior.disable-creeper-lingering-effect':
      '是否禁用苦力怕残留药效',
  'paper-world-defaults.yml.entities.behavior.disable-player-crits': '是否禁用玩家暴击',
  'paper-world-defaults.yml.entities.behavior.ender-dragons-death-always-places-dragon-egg':
      '末影龙死亡是否必定生成龙蛋',
  'paper-world-defaults.yml.entities.behavior.experience-merge-max-value':
      '经验球合并最大值（-1=无限）',
  'paper-world-defaults.yml.entities.behavior.nerf-pigmen-from-nether-portals':
      '是否弱化传送门生成的猪灵',
  'paper-world-defaults.yml.entities.behavior.only-merge-items-horizontally':
      '是否仅水平合并掉落物',
  'paper-world-defaults.yml.entities.behavior.parrots-are-unaffected-by-player-movement':
      '鹦鹉是否不受玩家移动影响',
  'paper-world-defaults.yml.entities.behavior.phantoms-do-not-spawn-on-creative-players':
      '幻翼是否不在创造模式玩家上生成',
  'paper-world-defaults.yml.entities.behavior.phantoms-only-attack-insomniacs':
      '幻翼是否仅攻击失眠玩家',
  'paper-world-defaults.yml.entities.behavior.phantoms-spawn-attempt-max-seconds':
      '幻翼生成尝试最大间隔（秒）',
  'paper-world-defaults.yml.entities.behavior.phantoms-spawn-attempt-min-seconds':
      '幻翼生成尝试最小间隔（秒）',
  'paper-world-defaults.yml.entities.behavior.piglins-guard-chests': '猪灵是否守护箱子',
  'paper-world-defaults.yml.entities.behavior.pillager-patrols.disable':
      '是否禁用掠夺者巡逻',
  'paper-world-defaults.yml.entities.behavior.pillager-patrols.spawn-chance':
      '掠夺者巡逻生成概率',
  'paper-world-defaults.yml.entities.behavior.player-insomnia-start-ticks':
      '玩家失眠开始 Tick',
  'paper-world-defaults.yml.entities.behavior.should-remove-dragon': '是否移除末影龙',
  'paper-world-defaults.yml.entities.behavior.spawner-nerfed-mobs-should-jump':
      '刷怪笼弱化怪物是否跳跃',
  'paper-world-defaults.yml.entities.behavior.zombie-villager-infection-chance':
      '僵尸村民感染概率',
  'paper-world-defaults.yml.entities.behavior.zombies-target-turtle-eggs':
      '僵尸是否以海龟蛋为目标',
  'paper-world-defaults.yml.entities.markers.tick': '标记实体是否参与 Tick',
  'paper-world-defaults.yml.entities.spawning.all-chunks-are-slime-chunks':
      '是否所有区块都是史莱姆区块',
  'paper-world-defaults.yml.entities.spawning.alt-item-despawn-rate.enabled':
      '是否启用替代掉落物消失速率',
  'paper-world-defaults.yml.entities.spawning.count-all-mobs-for-spawning':
      '是否将所有怪物计入生成限制',
  'paper-world-defaults.yml.entities.spawning.disable-mob-spawner-spawn-egg-transformation':
      '是否禁用刷怪笼刷怪蛋转换',
  'paper-world-defaults.yml.entities.spawning.iron-golems-can-spawn-in-air':
      '铁傀儡是否可在空中生成',
  'paper-world-defaults.yml.entities.spawning.max-arrow-despawn-invulnerability':
      '箭矢最大消失无敌时间',
  'paper-world-defaults.yml.entities.spawning.monster-spawn-max-light-level':
      '怪物生成最大光照等级',
  'paper-world-defaults.yml.entities.spawning.per-player-mob-spawns':
      '是否按玩家计算怪物生成',
  'paper-world-defaults.yml.entities.spawning.scan-for-legacy-ender-dragon':
      '是否扫描旧版末影龙',
  'paper-world-defaults.yml.environment.disable-explosion-knockback':
      '是否禁用爆炸击退',
  'paper-world-defaults.yml.environment.disable-ice-and-snow': '是否禁用冰雪生成',
  'paper-world-defaults.yml.environment.disable-thunder': '是否禁用雷雨',
  'paper-world-defaults.yml.environment.fire-tick-delay': '火焰蔓延延迟（Tick）',
  'paper-world-defaults.yml.environment.frosted-ice.enabled': '是否启用霜冰',
  'paper-world-defaults.yml.environment.generate-flat-bedrock': '是否生成扁平基岩',
  'paper-world-defaults.yml.environment.locate-structures-outside-world-border':
      '是否在世界边界外搜索结构',
  'paper-world-defaults.yml.environment.max-block-ticks': '最大方块 Tick 数',
  'paper-world-defaults.yml.environment.max-fluid-ticks': '最大流体 Tick 数',
  'paper-world-defaults.yml.environment.nether-ceiling-void-damage-height':
      '下界天花板虚空伤害高度',
  'paper-world-defaults.yml.environment.optimize-explosions': '是否优化爆炸计算',
  'paper-world-defaults.yml.environment.portal-create-radius': '传送门创建半径',
  'paper-world-defaults.yml.environment.portal-search-radius': '传送门搜索半径',
  'paper-world-defaults.yml.environment.portal-search-vanilla-dimension-scaling':
      '传送门搜索是否使用原版维度缩放',
  'paper-world-defaults.yml.environment.treasure-maps.enabled': '是否启用藏宝图',
  'paper-world-defaults.yml.environment.void-damage-amount': '虚空伤害量',
  'paper-world-defaults.yml.environment.water-over-lava-flow-speed': '水流过岩浆的速度',
  'paper-world-defaults.yml.fishing-time-range.maximum': '钓鱼最长时间（Tick）',
  'paper-world-defaults.yml.fishing-time-range.minimum': '钓鱼最短时间（Tick）',
  'paper-world-defaults.yml.fixes.disable-unloaded-chunk-enderpearl-exploit':
      '是否禁用未加载区块末影珍珠漏洞',
  'paper-world-defaults.yml.fixes.falling-block-height-nerf': '下落方块高度限制',
  'paper-world-defaults.yml.fixes.fix-items-merging-through-walls':
      '是否修复物品穿墙合并',
  'paper-world-defaults.yml.fixes.prevent-tnt-from-moving-in-water':
      '是否阻止 TNT 在水中移动',
  'paper-world-defaults.yml.fixes.split-overstacked-loot': '是否拆分超叠掉落物',
  'paper-world-defaults.yml.fixes.tnt-entity-height-nerf': 'TNT 实体高度限制',
  'paper-world-defaults.yml.hopper.cooldown-when-full': '满时是否冷却漏斗',
  'paper-world-defaults.yml.hopper.disable-move-event': '是否禁用漏斗移动事件',
  'paper-world-defaults.yml.hopper.ignore-occluding-blocks': '是否忽略遮挡方块',
  'paper-world-defaults.yml.lootables.auto-replenish': '是否自动补充战利品',
  'paper-world-defaults.yml.lootables.max-refills': '最大补充次数（-1=无限）',
  'paper-world-defaults.yml.lootables.refresh-max': '刷新最大时间',
  'paper-world-defaults.yml.lootables.refresh-min': '刷新最小时间',
  'paper-world-defaults.yml.lootables.reset-seed-on-fill': '补充时是否重置随机种子',
  'paper-world-defaults.yml.lootables.restrict-player-reloot': '是否限制玩家重复获取战利品',
  'paper-world-defaults.yml.maps.item-frame-cursor-limit': '物品展示框光标上限',
  'paper-world-defaults.yml.maps.item-frame-cursor-update-interval':
      '物品展示框光标更新间隔（Tick）',
  'paper-world-defaults.yml.max-growth-height.bamboo.max': '竹子最大生长高度',
  'paper-world-defaults.yml.max-growth-height.bamboo.min': '竹子最小生长高度',
  'paper-world-defaults.yml.max-growth-height.cactus': '仙人掌最大生长高度',
  'paper-world-defaults.yml.max-growth-height.reeds': '甘蔗最大生长高度',
  'paper-world-defaults.yml.misc.allow-remote-ender-dragon-respawning':
      '是否允许远程重生末影龙',
  'paper-world-defaults.yml.misc.alternate-current-update-order': '红石更新顺序',
  'paper-world-defaults.yml.misc.disable-end-credits': '是否禁用末地 credits',
  'paper-world-defaults.yml.misc.disable-relative-projectile-velocity':
      '是否禁用相对抛射物速度',
  'paper-world-defaults.yml.misc.disable-sprint-interruption-on-attack':
      '攻击时是否禁用疾跑打断',
  'paper-world-defaults.yml.misc.legacy-ender-pearl-behavior': '是否使用旧版末影珍珠行为',
  'paper-world-defaults.yml.misc.max-leash-distance': '最大拴绳距离',
  'paper-world-defaults.yml.misc.redstone-implementation':
      '红石实现（VANILLA/ALTERNATE_CURRENT）',
  'paper-world-defaults.yml.misc.update-pathfinding-on-block-update':
      '方块更新时是否更新寻路',
  'paper-world-defaults.yml.scoreboards.allow-non-player-entities-on-scoreboards':
      '记分板是否允许非玩家实体',
  'paper-world-defaults.yml.scoreboards.use-vanilla-world-scoreboard-name-coloring':
      '是否使用原版记分板名称着色',
  'paper-world-defaults.yml.spawn.allow-using-signs-inside-spawn-protection':
      '出生保护内是否可使用牌子',
  'paper-world-defaults.yml.tick-rates.container-update': '容器更新 Tick 频率',
  'paper-world-defaults.yml.tick-rates.dry-farmland': '干旱农田 Tick 频率',
  'paper-world-defaults.yml.tick-rates.grass-spread': '草地蔓延 Tick 频率',
  'paper-world-defaults.yml.tick-rates.mob-spawner': '刷怪笼 Tick 频率',
  'paper-world-defaults.yml.tick-rates.wet-farmland': '湿润农田 Tick 频率',
  'paper-world-defaults.yml.unsupported-settings.disable-world-ticking-when-empty':
      '无人时是否禁用世界 Tick',
  'paper-world-defaults.yml.unsupported-settings.fix-invulnerable-end-crystal-exploit':
      '是否修复无敌末影水晶漏洞',

  // ==================== paper-global.yml 补充 ====================
  'paper-global.yml.anticheat.obfuscation.items.all-models.also-obfuscate':
      '所有模型下也需混淆的物品组件',
  'paper-global.yml.anticheat.obfuscation.items.all-models.dont-obfuscate':
      '所有模型下不混淆的物品组件',
  'paper-global.yml.anticheat.obfuscation.items.all-models.sanitize-count':
      '是否清理物品数量',
  'paper-global.yml.anticheat.obfuscation.model-overrides': '特定物品模型的混淆覆盖规则',
  'paper-global.yml.misc.xp-orb-groups-per-area': '每区域经验球分组数',
  'paper-global.yml.packet-limiter.overrides': '特定数据包的限流覆盖规则',
  'paper-global.yml.unsupported-settings.oversized-item-component-sanitizer.dont-sanitize':
      '不清理的超大物品组件',

  // ==================== paper-world-defaults.yml 补充 ====================
  'paper-world-defaults.yml.anticheat.anti-xray.hidden-blocks': '隐藏的方块列表（反透视）',
  'paper-world-defaults.yml.anticheat.anti-xray.replacement-blocks':
      '替换方块列表（反透视）',
  'paper-world-defaults.yml.chunks.entity-per-chunk-save-limit': '每区块实体保存上限',
  'paper-world-defaults.yml.chunks.entity-per-chunk-save-limit.arrow':
      '箭矢保存上限（-1=无限）',
  'paper-world-defaults.yml.chunks.entity-per-chunk-save-limit.ender_pearl':
      '末影珍珠保存上限（-1=无限）',
  'paper-world-defaults.yml.chunks.entity-per-chunk-save-limit.experience_orb':
      '经验球保存上限（-1=无限）',
  'paper-world-defaults.yml.chunks.entity-per-chunk-save-limit.fireball':
      '火球保存上限（-1=无限）',
  'paper-world-defaults.yml.chunks.entity-per-chunk-save-limit.small_fireball':
      '小火球保存上限（-1=无限）',
  'paper-world-defaults.yml.chunks.entity-per-chunk-save-limit.snowball':
      '雪球保存上限（-1=无限）',
  'paper-world-defaults.yml.entities.behavior.door-breaking-difficulty.husk':
      '尸壳破门难度限制',
  'paper-world-defaults.yml.entities.behavior.door-breaking-difficulty.vindicator':
      '卫道士破门难度限制',
  'paper-world-defaults.yml.entities.behavior.door-breaking-difficulty.zombie':
      '僵尸破门难度限制',
  'paper-world-defaults.yml.entities.behavior.door-breaking-difficulty.zombie_villager':
      '僵尸村民破门难度限制',
  'paper-world-defaults.yml.entities.behavior.door-breaking-difficulty.zombified_piglin':
      '僵尸猪灵破门难度限制',
  'paper-world-defaults.yml.entities.behavior.mobs-can-always-pick-up-loot.skeletons':
      '骷髅是否始终可拾取战利品',
  'paper-world-defaults.yml.entities.behavior.mobs-can-always-pick-up-loot.zombies':
      '僵尸是否始终可拾取战利品',
  'paper-world-defaults.yml.entities.behavior.pillager-patrols.spawn-delay.per-player':
      '是否按玩家计算生成延迟',
  'paper-world-defaults.yml.entities.behavior.pillager-patrols.spawn-delay.ticks':
      '生成延迟（Tick）',
  'paper-world-defaults.yml.entities.behavior.pillager-patrols.start.day':
      '开始生成的天数',
  'paper-world-defaults.yml.entities.behavior.pillager-patrols.start.per-player':
      '是否按玩家计算开始天数',
  'paper-world-defaults.yml.entities.behavior.stuck-entity-poi-retry-delay':
      '卡住实体 POI 重试延迟（Tick）',
  'paper-world-defaults.yml.entities.mob-effects.immune-to-wither-effect.wither':
      '凋灵是否免疫凋零效果',
  'paper-world-defaults.yml.entities.mob-effects.immune-to-wither-effect.wither-skeleton':
      '凋灵骷髅是否免疫凋零效果',
  'paper-world-defaults.yml.entities.mob-effects.spiders-immune-to-poison-effect':
      '蜘蛛是否免疫中毒效果',
  'paper-world-defaults.yml.entities.sniffer.boosted-hatch-time': '嗅探兽加速孵化时间',
  'paper-world-defaults.yml.entities.sniffer.hatch-time': '嗅探兽孵化时间',
  'paper-world-defaults.yml.entities.spawning.creative-arrow-despawn-rate':
      '创造模式箭矢消失速率',
  'paper-world-defaults.yml.entities.spawning.despawn-range-shape':
      '消失范围形状（ELLIPSOID/SPHERE）',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.ambient.hard':
      '环境生物硬消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.ambient.soft':
      '环境生物软消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.axolotls.hard':
      '美西螈硬消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.axolotls.soft':
      '美西螈软消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.creature.hard':
      '生物硬消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.creature.soft':
      '生物软消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.misc.hard':
      '杂项实体硬消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.misc.soft':
      '杂项实体软消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.monster.hard':
      '怪物硬消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.monster.soft':
      '怪物软消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.underground_water_creature.hard':
      '地下水生生物硬消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.underground_water_creature.soft':
      '地下水生生物软消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.water_ambient.hard':
      '水生环境生物硬消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.water_ambient.soft':
      '水生环境生物软消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.water_creature.hard':
      '水生生物硬消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges.water_creature.soft':
      '水生生物软消失范围',
  'paper-world-defaults.yml.entities.spawning.despawn-time.llama_spit':
      '羊驼唾液消失时间',
  'paper-world-defaults.yml.entities.spawning.despawn-time.snowball': '雪球消失时间',
  'paper-world-defaults.yml.entities.spawning.duplicate-uuid.mode':
      '重复 UUID 处理模式（SAFE_REGEN/DELETE/IGNORE）',
  'paper-world-defaults.yml.entities.spawning.duplicate-uuid.safe-regen-delete-range':
      '安全重生成删除范围',
  'paper-world-defaults.yml.entities.spawning.filter-bad-tile-entity-nbt-from-falling-blocks':
      '是否过滤下落方块的不良 NBT',
  'paper-world-defaults.yml.entities.spawning.filtered-entity-tag-nbt-paths':
      '过滤的实体标签 NBT 路径',
  'paper-world-defaults.yml.entities.spawning.non-player-arrow-despawn-rate':
      '非玩家射出箭矢消失速率',
  'paper-world-defaults.yml.entities.spawning.skeleton-horse-thunder-spawn-chance':
      '雷雨时骷髅马生成概率',
  'paper-world-defaults.yml.entities.spawning.slime-spawn-height.slime-chunk.maximum':
      '史莱姆区块最大生成高度',
  'paper-world-defaults.yml.entities.spawning.slime-spawn-height.surface-biome.maximum':
      '地表生物群系最大生成高度',
  'paper-world-defaults.yml.entities.spawning.slime-spawn-height.surface-biome.minimum':
      '地表生物群系最小生成高度',
  'paper-world-defaults.yml.entities.spawning.spawn-limits.ambient':
      '环境生物生成上限（-1=默认）',
  'paper-world-defaults.yml.entities.spawning.spawn-limits.axolotls':
      '美西螈生成上限（-1=默认）',
  'paper-world-defaults.yml.entities.spawning.spawn-limits.creature':
      '生物生成上限（-1=默认）',
  'paper-world-defaults.yml.entities.spawning.spawn-limits.monster':
      '怪物生成上限（-1=默认）',
  'paper-world-defaults.yml.entities.spawning.spawn-limits.underground_water_creature':
      '地下水生生物生成上限（-1=默认）',
  'paper-world-defaults.yml.entities.spawning.spawn-limits.water_ambient':
      '水生环境生物生成上限（-1=默认）',
  'paper-world-defaults.yml.entities.spawning.spawn-limits.water_creature':
      '水生生物生成上限（-1=默认）',
  'paper-world-defaults.yml.entities.spawning.ticks-per-spawn.ambient':
      '环境生物生成间隔（Tick，-1=默认）',
  'paper-world-defaults.yml.entities.spawning.ticks-per-spawn.axolotls':
      '美西螈生成间隔（Tick，-1=默认）',
  'paper-world-defaults.yml.entities.spawning.ticks-per-spawn.creature':
      '生物生成间隔（Tick，-1=默认）',
  'paper-world-defaults.yml.entities.spawning.ticks-per-spawn.monster':
      '怪物生成间隔（Tick，-1=默认）',
  'paper-world-defaults.yml.entities.spawning.ticks-per-spawn.underground_water_creature':
      '地下水生生物生成间隔（Tick，-1=默认）',
  'paper-world-defaults.yml.entities.spawning.ticks-per-spawn.water_ambient':
      '水生环境生物生成间隔（Tick，-1=默认）',
  'paper-world-defaults.yml.entities.spawning.ticks-per-spawn.water_creature':
      '水生生物生成间隔（Tick，-1=默认）',
  'paper-world-defaults.yml.entities.spawning.wandering-trader.spawn-chance-failure-increment':
      '流浪商人生成失败概率增量',
  'paper-world-defaults.yml.entities.spawning.wandering-trader.spawn-chance-max':
      '流浪商人生成概率上限',
  'paper-world-defaults.yml.entities.spawning.wandering-trader.spawn-chance-min':
      '流浪商人生成概率下限',
  'paper-world-defaults.yml.entities.spawning.wandering-trader.spawn-day-length':
      '流浪商人生成日长度（Tick）',
  'paper-world-defaults.yml.entities.spawning.wandering-trader.spawn-minute-length':
      '流浪商人生成分钟长度（Tick）',
  'paper-world-defaults.yml.entities.spawning.wateranimal-spawn-height.maximum':
      '水生动物最大生成高度',
  'paper-world-defaults.yml.entities.spawning.wateranimal-spawn-height.minimum':
      '水生动物最小生成高度',
  'paper-world-defaults.yml.entities.tracking-range-y.animal': '动物 Y 轴跟踪范围',
  'paper-world-defaults.yml.entities.tracking-range-y.display': '展示实体 Y 轴跟踪范围',
  'paper-world-defaults.yml.entities.tracking-range-y.enabled': '是否启用 Y 轴跟踪范围',
  'paper-world-defaults.yml.entities.tracking-range-y.misc': '杂项实体 Y 轴跟踪范围',
  'paper-world-defaults.yml.entities.tracking-range-y.monster': '怪物 Y 轴跟踪范围',
  'paper-world-defaults.yml.entities.tracking-range-y.other': '其他实体 Y 轴跟踪范围',
  'paper-world-defaults.yml.entities.tracking-range-y.player': '玩家 Y 轴跟踪范围',
  'paper-world-defaults.yml.environment.frosted-ice.delay.max': '霜冰最大延迟（Tick）',
  'paper-world-defaults.yml.environment.frosted-ice.delay.min': '霜冰最小延迟（Tick）',
  'paper-world-defaults.yml.environment.treasure-maps.find-already-discovered.loot-tables':
      '战利品表是否查找已发现的藏宝图',
  'paper-world-defaults.yml.environment.treasure-maps.find-already-discovered.villager-trade':
      '村民交易是否查找已发现的藏宝图',
  'paper-world-defaults.yml.environment.void-damage-min-build-height-offset':
      '虚空伤害最小建筑高度偏移',
  'paper-world-defaults.yml.feature-seeds.generate-random-seeds-for-all':
      '是否为所有特性生成随机种子',
  'paper-world-defaults.yml.lootables.restrict-player-reloot-time':
      '限制玩家重复获取战利品的时间',
  'paper-world-defaults.yml.lootables.retain-unlooted-shulker-box-loot-table-on-non-player-break':
      '非玩家破坏时是否保留未获取的潜影盒战利品表',
  'paper-world-defaults.yml.misc.show-sign-click-command-failure-msgs-to-player':
      '是否向玩家显示牌子点击命令失败消息',
  'paper-world-defaults.yml.tick-rates.behavior.villager.validatenearbypoi':
      '村民验证附近 POI 的 Tick 频率（-1=默认）',
  'paper-world-defaults.yml.tick-rates.sensor.villager.secondarypoisensor':
      '村民次要 POI 传感器 Tick 频率',

  // 通用分组说明
  'paper-global.yml.anticheat': '反作弊设置',
  'paper-global.yml.anticheat.obfuscation': '物品混淆设置',
  'paper-global.yml.anticheat.obfuscation.items': '物品混淆规则',
  'paper-global.yml.block-updates': '方块更新设置',
  'paper-global.yml.chunk-loading-advanced': '高级区块加载设置',
  'paper-global.yml.chunk-loading-basic': '基础区块加载设置',
  'paper-global.yml.chunk-system': '区块系统线程设置',
  'paper-global.yml.collisions': '碰撞设置',
  'paper-global.yml.commands': '命令设置',
  'paper-global.yml.console': '控制台设置',
  'paper-global.yml.item-validation': '物品验证设置',
  'paper-global.yml.item-validation.book': '书本验证',
  'paper-global.yml.item-validation.book-size': '书本大小限制',
  'paper-global.yml.logging': '日志设置',
  'paper-global.yml.messages': '消息设置',
  'paper-global.yml.messages.kick': '踢出消息',
  'paper-global.yml.misc': '杂项设置',
  'paper-global.yml.misc.chat-threads': '聊天线程设置',
  'paper-global.yml.packet-limiter': '数据包限制器',
  'paper-global.yml.packet-limiter.all-packets': '所有数据包限制',
  'paper-global.yml.player-auto-save': '玩家自动保存',
  'paper-global.yml.proxies': '代理设置',
  'paper-global.yml.proxies.bungee-cord': 'BungeeCord 设置',
  'paper-global.yml.proxies.velocity': 'Velocity 设置',
  'paper-global.yml.scoreboards': '记分板设置',
  'paper-global.yml.spam-limiter': '刷屏限制器',
  'paper-global.yml.spark': 'Spark 性能分析',
  'paper-global.yml.threaded-regions': '线程化区域设置',
  'paper-global.yml.unsupported-settings': '不受支持的设置（漏洞特性）',
  'paper-global.yml.update-checker': '更新检查器',
  'paper-global.yml.watchdog': '看门狗（超时检测）',
  'paper-world-defaults.yml.anticheat': '反作弊设置',
  'paper-world-defaults.yml.anticheat.anti-xray': '反透视设置',
  'paper-world-defaults.yml.chunks': '区块设置',
  'paper-world-defaults.yml.collisions': '碰撞设置',
  'paper-world-defaults.yml.command-blocks': '命令方块设置',
  'paper-world-defaults.yml.entities': '实体设置',
  'paper-world-defaults.yml.entities.armor-stands': '盔甲架设置',
  'paper-world-defaults.yml.entities.behavior': '实体行为设置',
  'paper-world-defaults.yml.entities.behavior.door-breaking-difficulty':
      '破门难度限制',
  'paper-world-defaults.yml.entities.behavior.mobs-can-always-pick-up-loot':
      '怪物始终可拾取战利品',
  'paper-world-defaults.yml.entities.behavior.pillager-patrols': '掠夺者巡逻设置',
  'paper-world-defaults.yml.entities.behavior.pillager-patrols.spawn-delay':
      '生成延迟',
  'paper-world-defaults.yml.entities.behavior.pillager-patrols.start': '开始条件',
  'paper-world-defaults.yml.entities.markers': '标记实体设置',
  'paper-world-defaults.yml.entities.mob-effects': '生物效果免疫',
  'paper-world-defaults.yml.entities.mob-effects.immune-to-wither-effect':
      '凋零效果免疫',
  'paper-world-defaults.yml.entities.sniffer': '嗅探兽设置',
  'paper-world-defaults.yml.entities.spawning': '生成设置',
  'paper-world-defaults.yml.entities.spawning.alt-item-despawn-rate':
      '替代掉落物消失速率',
  'paper-world-defaults.yml.entities.spawning.despawn-ranges': '消失范围',
  'paper-world-defaults.yml.entities.spawning.duplicate-uuid': '重复 UUID 处理',
  'paper-world-defaults.yml.entities.spawning.slime-spawn-height': '史莱姆生成高度',
  'paper-world-defaults.yml.entities.spawning.slime-spawn-height.slime-chunk':
      '史莱姆区块',
  'paper-world-defaults.yml.entities.spawning.slime-spawn-height.surface-biome':
      '地表生物群系',
  'paper-world-defaults.yml.entities.spawning.spawn-limits': '生成上限',
  'paper-world-defaults.yml.entities.spawning.ticks-per-spawn': '每生成间隔 Tick',
  'paper-world-defaults.yml.entities.spawning.wandering-trader': '流浪商人设置',
  'paper-world-defaults.yml.entities.tracking-range-y': 'Y 轴跟踪范围',
  'paper-world-defaults.yml.environment': '环境设置',
  'paper-world-defaults.yml.environment.frosted-ice': '霜冰设置',
  'paper-world-defaults.yml.environment.frosted-ice.delay': '霜冰延迟',
  'paper-world-defaults.yml.environment.treasure-maps': '藏宝图设置',
  'paper-world-defaults.yml.environment.treasure-maps.find-already-discovered':
      '查找已发现的',
  'paper-world-defaults.yml.feature-seeds': '特性种子',
  'paper-world-defaults.yml.fishing-time-range': '钓鱼时间范围',
  'paper-world-defaults.yml.fixes': '修复设置',
  'paper-world-defaults.yml.hopper': '漏斗设置',
  'paper-world-defaults.yml.lootables': '战利品设置',
  'paper-world-defaults.yml.maps': '地图设置',
  'paper-world-defaults.yml.max-growth-height': '最大生长高度',
  'paper-world-defaults.yml.max-growth-height.bamboo': '竹子',
  'paper-world-defaults.yml.misc': '杂项设置',
  'paper-world-defaults.yml.scoreboards': '记分板设置',
  'paper-world-defaults.yml.spawn': '出生点设置',
  'paper-world-defaults.yml.tick-rates': 'Tick 频率设置',
  'paper-world-defaults.yml.tick-rates.behavior': '行为 Tick 频率',
  'paper-world-defaults.yml.tick-rates.behavior.villager': '村民',
  'paper-world-defaults.yml.tick-rates.sensor': '传感器 Tick 频率',
  'paper-world-defaults.yml.tick-rates.sensor.villager': '村民',
  'paper-world-defaults.yml.unsupported-settings': '不受支持的设置',
  'paper-world-defaults.yml.unsupported-settings.oversized-item-component-sanitizer':
      '超大物品组件清理器',
  'bukkit.yml.settings': '服务器设置',
  'bukkit.yml.settings.attribute': '属性上限设置',
  'bukkit.yml.spawn-limits': '生成上限',
  'bukkit.yml.chunk-gc': '区块垃圾回收',
  'bukkit.yml.ticks-per': 'Tick 间隔设置',
  'spigot.yml.settings': '服务器设置',
  'spigot.yml.settings.attribute': '属性上限设置',
  'spigot.yml.advancements': '成就设置',
  'spigot.yml.messages': '消息设置',
  'spigot.yml.players': '玩家设置',
  'spigot.yml.stats': '统计设置',
  'spigot.yml.commands': '命令设置',
  'spigot.yml.world-settings': '世界设置',
  'spigot.yml.world-settings.default': '默认世界设置',
  'spigot.yml.world-settings.default.hunger': '饥饿消耗设置',
  'spigot.yml.world-settings.default.ticks-per': 'Tick 间隔设置',
  'spigot.yml.world-settings.default.merge-radius': '合并半径',
  'spigot.yml.world-settings.default.growth': '生长速度设置',
  'spigot.yml.world-settings.default.entity-activation-range': '实体激活范围',
  'spigot.yml.world-settings.default.entity-activation-range.wake-up-inactive':
      '唤醒非活跃实体',
  'spigot.yml.world-settings.default.entity-tracking-range': '实体跟踪范围',
  'spigot.yml.world-settings.default.max-tick-time': '最大 Tick 时间',

  // ==================== purpur.yml ====================
  // 顶层设置
  'purpur.yml.verbose': '是否输出详细调试信息',
  'purpur.yml.config-version': '配置文件版本（请勿手动修改）',

  // settings 全局设置
  'purpur.yml.settings': 'Purpur 全局设置',
  'purpur.yml.settings.fix-projectile-looting-transfer': '是否修复投掷物抢夺附魔转移问题',
  'purpur.yml.settings.limit-armor': '是否限制玩家可穿戴的护甲数量',
  'purpur.yml.settings.tps-catchup': 'TPS 落后时是否追赶（防止卡顿后持续低 TPS）',
  'purpur.yml.settings.server-mod-name': '服务器模组名称（显示在客户端 F3）',
  'purpur.yml.settings.player-deaths-always-show-item': '玩家死亡是否总是显示掉落物品',
  'purpur.yml.settings.startup-commands': '服务器启动时自动执行的命令列表',
  'purpur.yml.settings.disable-give-dropping': '是否禁用 /give 命令掉落物品',
  'purpur.yml.settings.use-alternate-keepalive': '是否使用替代的心跳保持机制',
  'purpur.yml.settings.bee-count-payload': '蜜蜂计数是否包含负载数据',
  'purpur.yml.settings.clamp-attributes': '是否将属性值限制在合理范围内',
  'purpur.yml.settings.allow-water-placement-in-the-end': '是否允许在末地放置水',
  'purpur.yml.settings.lagging-threshold': '服务器卡顿阈值（TPS，低于此值视为卡顿）',
  'purpur.yml.settings.blast-resistance-overrides': '方块爆炸抗性覆盖列表',
  'purpur.yml.settings.username-valid-characters': '玩家用户名允许的字符正则',
  'purpur.yml.settings.register-minecraft-debug-commands':
      '是否注册 Minecraft 调试命令',
  'purpur.yml.settings.register-minecraft-disabled-commands':
      '是否注册被禁用的 Minecraft 命令',

  // settings.blocks 全局方块设置
  'purpur.yml.settings.blocks': '全局方块行为设置',
  'purpur.yml.settings.blocks.barrel': '木桶设置',
  'purpur.yml.settings.blocks.barrel.rows': '木桶行数（3=单排，6=六排大箱子）',
  'purpur.yml.settings.blocks.ender_chest': '末影箱设置',
  'purpur.yml.settings.blocks.ender_chest.six-rows': '末影箱是否使用六行（大箱子）',
  'purpur.yml.settings.blocks.ender_chest.use-permissions-for-rows':
      '是否通过权限控制末影箱行数',
  'purpur.yml.settings.blocks.crying_obsidian': '哭泣的黑曜石设置',
  'purpur.yml.settings.blocks.crying_obsidian.valid-for-portal-frame':
      '哭泣的黑曜石是否可用于末地传送门框架',
  'purpur.yml.settings.blocks.beehive': '蜂巢设置',
  'purpur.yml.settings.blocks.beehive.max-bees-inside': '蜂巢内最大蜜蜂数量',
  'purpur.yml.settings.blocks.anvil': '铁砧设置（全局）',
  'purpur.yml.settings.blocks.anvil.cumulative-cost': '铁砧修复是否累积经验消耗',
  'purpur.yml.settings.blocks.snow': '雪设置',
  'purpur.yml.settings.blocks.snow.smooth-accumulation-step': '雪堆积的平滑步长（0=原版）',
  'purpur.yml.settings.blocks.lightning_rod': '避雷针设置',
  'purpur.yml.settings.blocks.lightning_rod.range': '避雷针吸引闪电的范围',
  'purpur.yml.settings.blocks.grindstone': '砂轮设置',
  'purpur.yml.settings.blocks.grindstone.ignored-enchants': '砂轮移除时忽略的附魔列表',
  'purpur.yml.settings.blocks.grindstone.remove-attributes': '砂轮是否移除物品属性',
  'purpur.yml.settings.blocks.grindstone.remove-name-and-lore': '砂轮是否移除物品名称和描述',
  'purpur.yml.settings.blocks.cave_vines': '洞穴藤蔓设置',
  'purpur.yml.settings.blocks.cave_vines.max-growth-age': '洞穴藤蔓最大生长年龄',
  'purpur.yml.settings.blocks.kelp': '海带设置',
  'purpur.yml.settings.blocks.kelp.max-growth-age': '海带最大生长年龄',
  'purpur.yml.settings.blocks.twisting_vines': '缠怨藤设置',
  'purpur.yml.settings.blocks.twisting_vines.max-growth-age': '缠怨藤最大生长年龄',
  'purpur.yml.settings.blocks.weeping_vines': '垂泪藤设置',
  'purpur.yml.settings.blocks.weeping_vines.max-growth-age': '垂泪藤最大生长年龄',
  'purpur.yml.settings.blocks.magma-block': '岩浆块设置（全局）',
  'purpur.yml.settings.blocks.magma-block.reverse-bubble-column-flow':
      '岩浆块是否反转气泡柱流向',
  'purpur.yml.settings.blocks.soul-sand': '灵魂沙设置',
  'purpur.yml.settings.blocks.soul-sand.reverse-bubble-column-flow':
      '灵魂沙是否反转气泡柱流向',

  // settings.entity 全局实体设置
  'purpur.yml.settings.entity': '全局实体设置',
  'purpur.yml.settings.entity.enderman': '末影人设置',
  'purpur.yml.settings.entity.enderman.short-height': '末影人是否使用较短身高',

  // settings.broadcasts 广播设置
  'purpur.yml.settings.broadcasts': '广播消息设置',
  'purpur.yml.settings.broadcasts.advancement': '成就广播',
  'purpur.yml.settings.broadcasts.advancement.only-broadcast-to-affected-player':
      '成就仅广播给相关玩家',
  'purpur.yml.settings.broadcasts.death': '死亡广播',
  'purpur.yml.settings.broadcasts.death.only-broadcast-to-affected-player':
      '死亡消息仅广播给相关玩家',

  // settings.messages 消息设置
  'purpur.yml.settings.messages': '消息文本设置',
  'purpur.yml.settings.messages.death-message': '死亡消息文本',
  'purpur.yml.settings.messages.death-message.run-with-scissors':
      '拿着剪刀奔跑时摔倒的死亡消息',
  'purpur.yml.settings.messages.death-message.stonecutter': '被切石机切死的死亡消息',
  'purpur.yml.settings.messages.cannot-ride-mob': '无法骑乘生物的提示消息',
  'purpur.yml.settings.messages.afk-broadcast-away': '玩家进入 AFK 的广播消息',
  'purpur.yml.settings.messages.afk-broadcast-back': '玩家退出 AFK 的广播消息',
  'purpur.yml.settings.messages.afk-broadcast-use-display-name':
      'AFK 广播是否使用显示名称',
  'purpur.yml.settings.messages.afk-tab-list-prefix': 'AFK 玩家 Tab 列表前缀',
  'purpur.yml.settings.messages.afk-tab-list-suffix': 'AFK 玩家 Tab 列表后缀',
  'purpur.yml.settings.messages.credits-command-output': '显示末地 credits 命令的输出',
  'purpur.yml.settings.messages.demo-command-output': '演示模式命令的输出',
  'purpur.yml.settings.messages.ping-command-output': '查看延迟命令的输出',
  'purpur.yml.settings.messages.ram-command-output': '查看内存命令的输出',
  'purpur.yml.settings.messages.rambar-command-output': '内存条切换命令的输出',
  'purpur.yml.settings.messages.tpsbar-command-output': 'TPS 条切换命令的输出',
  'purpur.yml.settings.messages.dont-run-with-scissors': '不要拿着剪刀奔跑的警告消息',
  'purpur.yml.settings.messages.uptime-command-output': '运行时间命令的输出',
  'purpur.yml.settings.messages.unverified-username': '未验证用户名提示',
  'purpur.yml.settings.messages.sleep-skipping-night': '跳过夜晚的提示消息',
  'purpur.yml.settings.messages.sleeping-players-percent': '正在睡觉玩家百分比提示',
  'purpur.yml.settings.messages.sleep-not-possible': '无法睡觉的提示消息',

  // settings.command 命令设置
  'purpur.yml.settings.command': '命令相关设置',
  'purpur.yml.settings.command.rambar': '内存条命令设置',
  'purpur.yml.settings.command.rambar.title': '内存条标题格式',
  'purpur.yml.settings.command.rambar.overlay': '内存条 Boss 条样式',
  'purpur.yml.settings.command.rambar.progress-color': '内存条进度颜色',
  'purpur.yml.settings.command.rambar.progress-color.good': '内存充足时的颜色',
  'purpur.yml.settings.command.rambar.progress-color.medium': '内存中等时的颜色',
  'purpur.yml.settings.command.rambar.progress-color.low': '内存不足时的颜色',
  'purpur.yml.settings.command.rambar.text-color': '内存条文本颜色',
  'purpur.yml.settings.command.rambar.text-color.good': '内存充足时的文本颜色',
  'purpur.yml.settings.command.rambar.text-color.medium': '内存中等时的文本颜色',
  'purpur.yml.settings.command.rambar.text-color.low': '内存不足时的文本颜色',
  'purpur.yml.settings.command.rambar.tick-interval': '内存条更新间隔（Tick）',
  'purpur.yml.settings.command.tpsbar': 'TPS 条命令设置',
  'purpur.yml.settings.command.tpsbar.title': 'TPS 条标题格式',
  'purpur.yml.settings.command.tpsbar.overlay': 'TPS 条 Boss 条样式',
  'purpur.yml.settings.command.tpsbar.fill-mode': 'TPS 条填充模式（TPS/MSPT）',
  'purpur.yml.settings.command.tpsbar.progress-color': 'TPS 条进度颜色',
  'purpur.yml.settings.command.tpsbar.progress-color.good': 'TPS 良好时的颜色',
  'purpur.yml.settings.command.tpsbar.progress-color.medium': 'TPS 中等的颜色',
  'purpur.yml.settings.command.tpsbar.progress-color.low': 'TPS 低下时的颜色',
  'purpur.yml.settings.command.tpsbar.text-color': 'TPS 条文本颜色',
  'purpur.yml.settings.command.tpsbar.text-color.good': 'TPS 良好时的文本颜色',
  'purpur.yml.settings.command.tpsbar.text-color.medium': 'TPS 中等的文本颜色',
  'purpur.yml.settings.command.tpsbar.text-color.low': 'TPS 低下时的文本颜色',
  'purpur.yml.settings.command.tpsbar.tick-interval': 'TPS 条更新间隔（Tick）',
  'purpur.yml.settings.command.compass': '指南针命令设置',
  'purpur.yml.settings.command.compass.title': '指南针 Boss 条标题',
  'purpur.yml.settings.command.compass.overlay': '指南针 Boss 条样式',
  'purpur.yml.settings.command.compass.progress-color': '指南针进度颜色',
  'purpur.yml.settings.command.compass.percent': '指南针填充比例',
  'purpur.yml.settings.command.compass.tick-interval': '指南针更新间隔（Tick）',
  'purpur.yml.settings.command.gamemode': '游戏模式命令设置',
  'purpur.yml.settings.command.gamemode.requires-specific-permission':
      '游戏模式命令是否需要特定权限',
  'purpur.yml.settings.command.hide-hidden-players-from-entity-selector':
      '实体选择器是否隐藏隐身玩家',
  'purpur.yml.settings.command.uptime': '运行时间命令设置',
  'purpur.yml.settings.command.uptime.format': '运行时间显示格式',
  'purpur.yml.settings.command.uptime.day': '天数（单数）格式',
  'purpur.yml.settings.command.uptime.days': '天数（复数）格式',
  'purpur.yml.settings.command.uptime.hour': '小时（单数）格式',
  'purpur.yml.settings.command.uptime.hours': '小时（复数）格式',
  'purpur.yml.settings.command.uptime.minute': '分钟（单数）格式',
  'purpur.yml.settings.command.uptime.minutes': '分钟（复数）格式',
  'purpur.yml.settings.command.uptime.second': '秒（单数）格式',
  'purpur.yml.settings.command.uptime.seconds': '秒（复数）格式',

  // settings.network 网络设置
  'purpur.yml.settings.network': '网络设置',
  'purpur.yml.settings.network.upnp-port-forwarding': '是否启用 UPnP 自动端口转发',
  'purpur.yml.settings.network.max-joins-per-second': '每秒最大加入数（false=禁用）',
  'purpur.yml.settings.network.kick-for-out-of-order-chat': '是否踢出乱序聊天消息的玩家',

  // settings.enchantment 附魔设置
  'purpur.yml.settings.enchantment': '附魔设置',
  'purpur.yml.settings.enchantment.anvil': '铁砧附魔设置',
  'purpur.yml.settings.enchantment.anvil.allow-inapplicable-enchants':
      '铁砧是否允许不兼容的附魔',
  'purpur.yml.settings.enchantment.anvil.allow-incompatible-enchants':
      '铁砧是否允许冲突的附魔',
  'purpur.yml.settings.enchantment.anvil.allow-higher-enchants-levels':
      '铁砧是否允许超出最大等级的附魔',
  'purpur.yml.settings.enchantment.anvil.replace-incompatible-enchants':
      '是否替换冲突的附魔',
  'purpur.yml.settings.enchantment.allow-unsafe-enchant-command':
      '是否允许不安全的附魔命令',
  'purpur.yml.settings.enchantment.clamp-levels': '是否限制附魔等级',

  // settings.logger 日志设置
  'purpur.yml.settings.logger': '日志抑制设置',
  'purpur.yml.settings.logger.suppress-init-legacy-material-errors':
      '是否抑制初始化时的旧版材料错误',
  'purpur.yml.settings.logger.suppress-ignored-advancement-warnings':
      '是否抑制被忽略的成就警告',
  'purpur.yml.settings.logger.suppress-unrecognized-recipe-errors':
      '是否抑制未识别配方的错误',
  'purpur.yml.settings.logger.suppress-setblock-in-far-chunk-errors':
      '是否抑制在远处区块设置方块的错误',
  'purpur.yml.settings.logger.suppress-library-loader': '是否抑制库加载器日志',

  // settings.block-fall-multipliers 方块下落倍率
  'purpur.yml.settings.block-fall-multipliers': '方块下落伤害倍率',

  // world-settings.default 世界默认设置
  'purpur.yml.world-settings': '世界设置',
  'purpur.yml.world-settings.default': '默认世界设置',
  'purpur.yml.world-settings.default.settings': '世界设置',
  'purpur.yml.world-settings.default.settings.entity': '世界实体设置',
  'purpur.yml.world-settings.default.settings.entity.shared-random':
      '实体是否共享随机种子（防止刷怪可预测）',

  // world-settings.default.blocks 世界方块设置
  'purpur.yml.world-settings.default.blocks': '世界方块行为设置',
  'purpur.yml.world-settings.default.blocks.observer': '侦测器设置',
  'purpur.yml.world-settings.default.blocks.observer.disable-clock':
      '是否禁用侦测器时钟（防卡顿）',
  'purpur.yml.world-settings.default.blocks.slab': '半砖设置',
  'purpur.yml.world-settings.default.blocks.slab.break-individual-slabs-when-sneaking':
      '潜行时是否单独破坏双半砖',
  'purpur.yml.world-settings.default.blocks.respawn_anchor': '重生锚设置',
  'purpur.yml.world-settings.default.blocks.respawn_anchor.explode':
      '重生锚是否可在主世界爆炸',
  'purpur.yml.world-settings.default.blocks.respawn_anchor.explosion-power':
      '重生锚爆炸威力',
  'purpur.yml.world-settings.default.blocks.respawn_anchor.explosion-fire':
      '重生锚爆炸是否起火',
  'purpur.yml.world-settings.default.blocks.respawn_anchor.explosion-effect':
      '重生锚爆炸效果（BLOCK/BREAK）',
  'purpur.yml.world-settings.default.blocks.anvil': '铁砧设置（世界）',
  'purpur.yml.world-settings.default.blocks.anvil.allow-colors': '铁砧是否允许使用彩色名称',
  'purpur.yml.world-settings.default.blocks.anvil.use-mini-message':
      '铁砧是否使用 MiniMessage 格式',
  'purpur.yml.world-settings.default.blocks.anvil.iron-ingots-used-for-repair':
      '铁砧修复消耗的铁锭数量',
  'purpur.yml.world-settings.default.blocks.anvil.obsidian-used-for-damage':
      '铁砧受损时消耗的黑曜石数量',
  'purpur.yml.world-settings.default.blocks.stonecutter': '切石机设置',
  'purpur.yml.world-settings.default.blocks.stonecutter.damage': '切石机造成的伤害值',
  'purpur.yml.world-settings.default.blocks.azalea': '杜鹃花设置',
  'purpur.yml.world-settings.default.blocks.azalea.growth-chance': '杜鹃花生长概率',
  'purpur.yml.world-settings.default.blocks.dragon_egg': '龙蛋设置',
  'purpur.yml.world-settings.default.blocks.dragon_egg.teleport': '龙蛋是否可传送',
  'purpur.yml.world-settings.default.blocks.enchantment-table': '附魔台设置',
  'purpur.yml.world-settings.default.blocks.enchantment-table.lapis-persists':
      '附魔台是否持久化青金石',
  'purpur.yml.world-settings.default.blocks.sculk_shrieker': '幽匿尖啸体设置',
  'purpur.yml.world-settings.default.blocks.sculk_shrieker.can-summon-default':
      '幽匿尖啸体是否可默认召唤监守者',
  'purpur.yml.world-settings.default.blocks.composter': '堆肥桶设置',
  'purpur.yml.world-settings.default.blocks.composter.sneak-to-bulk-process':
      '是否潜行批量堆肥',
  'purpur.yml.world-settings.default.blocks.cactus': '仙人掌设置',
  'purpur.yml.world-settings.default.blocks.cactus.breaks-from-solid-neighbors':
      '仙人掌是否被相邻固体方块破坏',
  'purpur.yml.world-settings.default.blocks.cactus.affected-by-bonemeal':
      '仙人掌是否受骨粉影响',
  'purpur.yml.world-settings.default.blocks.campfire': '营火设置',
  'purpur.yml.world-settings.default.blocks.campfire.lit-when-placed':
      '营火放置时是否点燃',
  'purpur.yml.world-settings.default.blocks.nether_wart': '地狱疣设置',
  'purpur.yml.world-settings.default.blocks.nether_wart.affected-by-bonemeal':
      '地狱疣是否受骨粉影响',
  'purpur.yml.world-settings.default.blocks.spawner': '刷怪笼设置',
  'purpur.yml.world-settings.default.blocks.spawner.deactivate-by-redstone':
      '刷怪笼是否可被红石禁用',
  'purpur.yml.world-settings.default.blocks.spawner.fix-mc-238526':
      '是否修复 MC-238526 刷怪笼 Bug',
  'purpur.yml.world-settings.default.blocks.chest': '箱子设置',
  'purpur.yml.world-settings.default.blocks.chest.open-with-solid-block-on-top':
      '箱子顶部有固体方块时是否可打开',
  'purpur.yml.world-settings.default.blocks.flowering_azalea': '杜鹃花设置',
  'purpur.yml.world-settings.default.blocks.flowering_azalea.growth-chance':
      '杜鹃花生长概率',
  'purpur.yml.world-settings.default.blocks.sugar_cane': '甘蔗设置',
  'purpur.yml.world-settings.default.blocks.sugar_cane.affected-by-bonemeal':
      '甘蔗是否受骨粉影响',
  'purpur.yml.world-settings.default.blocks.coral': '珊瑚设置',
  'purpur.yml.world-settings.default.blocks.coral.die-outside-water':
      '珊瑚是否在水中外死亡',
  'purpur.yml.world-settings.default.blocks.farmland': '农田设置',
  'purpur.yml.world-settings.default.blocks.farmland.mob-griefing-override':
      '农田生物破坏覆盖（default/true/false）',
  'purpur.yml.world-settings.default.blocks.farmland.gets-moist-from-below':
      '农田是否从下方获取水分',
  'purpur.yml.world-settings.default.blocks.farmland.use-alpha-farmland':
      '是否使用 Alpha 版农田',
  'purpur.yml.world-settings.default.blocks.farmland.disable-trampling':
      '是否禁用农田踩踏',
  'purpur.yml.world-settings.default.blocks.farmland.only-players-trample':
      '是否仅玩家可踩踏农田',
  'purpur.yml.world-settings.default.blocks.farmland.feather-fall-distance-affects-trampling':
      '轻盈附魔是否影响踩踏距离',
  'purpur.yml.world-settings.default.blocks.farmland.trample-height':
      '踩踏高度阈值（-1=默认）',
  'purpur.yml.world-settings.default.blocks.furnace': '熔炉设置',
  'purpur.yml.world-settings.default.blocks.furnace.use-lava-from-underneath':
      '熔炉是否从下方使用岩浆',
  'purpur.yml.world-settings.default.blocks.water': '水设置',
  'purpur.yml.world-settings.default.blocks.water.infinite-required-sources':
      '形成无限水源所需的水源数',
  'purpur.yml.world-settings.default.blocks.bed': '床设置',
  'purpur.yml.world-settings.default.blocks.bed.explode': '床是否会在其他维度爆炸',
  'purpur.yml.world-settings.default.blocks.bed.explode-on-villager-sleep':
      '村民睡觉时床是否爆炸',
  'purpur.yml.world-settings.default.blocks.bed.explosion-power': '床爆炸威力',
  'purpur.yml.world-settings.default.blocks.bed.explosion-fire': '床爆炸是否起火',
  'purpur.yml.world-settings.default.blocks.bed.explosion-effect': '床爆炸效果',
  'purpur.yml.world-settings.default.blocks.dispenser': '发射器设置',
  'purpur.yml.world-settings.default.blocks.dispenser.apply-cursed-to-armor-slots':
      '发射器是否对护甲槽应用诅咒',
  'purpur.yml.world-settings.default.blocks.dispenser.place-anvils':
      '发射器是否可放置铁砧',
  'purpur.yml.world-settings.default.blocks.packed_ice': '浮冰设置',
  'purpur.yml.world-settings.default.blocks.packed_ice.allow-mob-spawns':
      '浮冰上是否可生成怪物',
  'purpur.yml.world-settings.default.blocks.blue_ice': '蓝冰设置',
  'purpur.yml.world-settings.default.blocks.blue_ice.allow-mob-spawns':
      '蓝冰上是否可生成怪物',
  'purpur.yml.world-settings.default.blocks.blue_ice.allow-snow-formation':
      '蓝冰上是否可积雪',
  'purpur.yml.world-settings.default.blocks.magma-block': '岩浆块设置（世界）',
  'purpur.yml.world-settings.default.blocks.magma-block.damage-when-sneaking':
      '潜行时岩浆块是否造成伤害',
  'purpur.yml.world-settings.default.blocks.powered-rail': '充能铁轨设置',
  'purpur.yml.world-settings.default.blocks.powered-rail.activation-range':
      '充能铁轨激活范围',
  'purpur.yml.world-settings.default.blocks.lava': '岩浆设置',
  'purpur.yml.world-settings.default.blocks.lava.infinite-required-sources':
      '形成无限岩浆源所需的源数',
  'purpur.yml.world-settings.default.blocks.lava.speed': '岩浆流动速度',
  'purpur.yml.world-settings.default.blocks.lava.speed.nether': '下界岩浆流动速度',
  'purpur.yml.world-settings.default.blocks.lava.speed.not-nether': '非下界岩浆流动速度',
  'purpur.yml.world-settings.default.blocks.door': '门设置',
  'purpur.yml.world-settings.default.blocks.door.requires-redstone':
      '需要红石才能开关的门列表',
  'purpur.yml.world-settings.default.blocks.powder_snow': '细雪设置',
  'purpur.yml.world-settings.default.blocks.powder_snow.mob-griefing-override':
      '细雪生物破坏覆盖',
  'purpur.yml.world-settings.default.blocks.beacon': '信标设置',
  'purpur.yml.world-settings.default.blocks.beacon.effect-range': '信标效果范围',
  'purpur.yml.world-settings.default.blocks.beacon.effect-range.level-1':
      '一级信标效果范围',
  'purpur.yml.world-settings.default.blocks.beacon.effect-range.level-2':
      '二级信标效果范围',
  'purpur.yml.world-settings.default.blocks.beacon.effect-range.level-3':
      '三级信标效果范围',
  'purpur.yml.world-settings.default.blocks.beacon.effect-range.level-4':
      '四级信标效果范围',
  'purpur.yml.world-settings.default.blocks.beacon.allow-effects-with-tinted-glass':
      '遮光玻璃下是否有效',
  'purpur.yml.world-settings.default.blocks.piston': '活塞设置',
  'purpur.yml.world-settings.default.blocks.piston.block-push-limit':
      '活塞推动方块上限',
  'purpur.yml.world-settings.default.blocks.end-crystal': '末影水晶设置',
  'purpur.yml.world-settings.default.blocks.end-crystal.baseless': '无基座末影水晶',
  'purpur.yml.world-settings.default.blocks.end-crystal.baseless.explode':
      '无基座末影水晶是否爆炸',
  'purpur.yml.world-settings.default.blocks.end-crystal.baseless.explosion-power':
      '无基座末影水晶爆炸威力',
  'purpur.yml.world-settings.default.blocks.end-crystal.baseless.explosion-fire':
      '无基座末影水晶爆炸是否起火',
  'purpur.yml.world-settings.default.blocks.end-crystal.baseless.explosion-effect':
      '无基座末影水晶爆炸效果',
  'purpur.yml.world-settings.default.blocks.end-crystal.base': '有基座末影水晶',
  'purpur.yml.world-settings.default.blocks.end-crystal.base.explode':
      '有基座末影水晶是否爆炸',
  'purpur.yml.world-settings.default.blocks.end-crystal.base.explosion-power':
      '有基座末影水晶爆炸威力',
  'purpur.yml.world-settings.default.blocks.end-crystal.base.explosion-fire':
      '有基座末影水晶爆炸是否起火',
  'purpur.yml.world-settings.default.blocks.end-crystal.base.explosion-effect':
      '有基座末影水晶爆炸效果',
  'purpur.yml.world-settings.default.blocks.end-crystal.cramming-amount':
      '末影水晶挤压数量上限',
  'purpur.yml.world-settings.default.blocks.sign': '牌子设置',
  'purpur.yml.world-settings.default.blocks.sign.allow-colors': '牌子是否允许使用彩色文本',
  'purpur.yml.world-settings.default.blocks.sponge': '海绵设置',
  'purpur.yml.world-settings.default.blocks.sponge.absorption': '海绵吸收设置',
  'purpur.yml.world-settings.default.blocks.sponge.absorption.area': '海绵吸收区域',
  'purpur.yml.world-settings.default.blocks.sponge.absorption.radius': '海绵吸收半径',
  'purpur.yml.world-settings.default.blocks.sponge.absorbs-lava': '海绵是否吸收岩浆',
  'purpur.yml.world-settings.default.blocks.sponge.absorbs-water-from-mud':
      '海绵是否从泥巴吸水',
  'purpur.yml.world-settings.default.blocks.turtle_egg': '海龟蛋设置',
  'purpur.yml.world-settings.default.blocks.turtle_egg.break-from-exp-orbs':
      '经验球是否压碎海龟蛋',
  'purpur.yml.world-settings.default.blocks.turtle_egg.break-from-items':
      '物品是否压碎海龟蛋',
  'purpur.yml.world-settings.default.blocks.turtle_egg.break-from-minecarts':
      '矿车是否压碎海龟蛋',
  'purpur.yml.world-settings.default.blocks.turtle_egg.mob-griefing-override':
      '海龟蛋生物破坏覆盖',
  'purpur.yml.world-settings.default.blocks.turtle_egg.random-tick-crack-chance':
      '海龟蛋随机破坏概率',
  'purpur.yml.world-settings.default.blocks.turtle_egg.feather-fall-distance-affects-trampling':
      '轻盈附魔是否影响踩踏',
  'purpur.yml.world-settings.default.blocks.conduit': '潮涌核心设置',
  'purpur.yml.world-settings.default.blocks.conduit.effect-distance':
      '潮涌核心效果距离',
  'purpur.yml.world-settings.default.blocks.conduit.mob-damage': '潮涌核心对怪物伤害',
  'purpur.yml.world-settings.default.blocks.conduit.mob-damage.distance':
      '潮涌核心伤害距离',
  'purpur.yml.world-settings.default.blocks.conduit.mob-damage.damage-amount':
      '潮涌核心伤害值',
  'purpur.yml.world-settings.default.blocks.conduit.valid-ring-blocks':
      '潮涌核心有效环绕方块',
  'purpur.yml.world-settings.default.blocks.cauldron': '炼药锅设置',
  'purpur.yml.world-settings.default.blocks.cauldron.fill-chances': '炼药锅填充概率',
  'purpur.yml.world-settings.default.blocks.cauldron.fill-chances.rain':
      '雨水填充概率',
  'purpur.yml.world-settings.default.blocks.cauldron.fill-chances.powder-snow':
      '细雪填充概率',
  'purpur.yml.world-settings.default.blocks.cauldron.fill-chances.dripstone-water':
      '钟乳石水填充概率',
  'purpur.yml.world-settings.default.blocks.cauldron.fill-chances.dripstone-lava':
      '钟乳石岩浆填充概率',
  'purpur.yml.world-settings.default.blocks.big_dripleaf': '大型垂滴叶设置',
  'purpur.yml.world-settings.default.blocks.big_dripleaf.tilt-delay':
      '大型垂滴叶倾斜延迟',
  'purpur.yml.world-settings.default.blocks.big_dripleaf.tilt-delay.UNSTABLE':
      '不稳定状态延迟（Tick）',
  'purpur.yml.world-settings.default.blocks.big_dripleaf.tilt-delay.PARTIAL':
      '部分倾斜延迟（Tick）',
  'purpur.yml.world-settings.default.blocks.big_dripleaf.tilt-delay.FULL':
      '完全倾斜延迟（Tick）',

  // world-settings.default.mobs 生物设置（通用字段，适用于所有生物）
  'purpur.yml.world-settings.default.mobs': '生物设置',
  'purpur.yml.world-settings.default.mobs.creaking': '嘎吱怪设置',
  'purpur.yml.world-settings.default.mobs.creeper': '苦力怕设置',
  'purpur.yml.world-settings.default.mobs.creeper.naturally-charged-chance':
      '苦力怕自然充能概率',
  'purpur.yml.world-settings.default.mobs.creeper.allow-griefing': '苦力怕是否可破坏方块',
  'purpur.yml.world-settings.default.mobs.creeper.takes-damage-from-water':
      '苦力怕是否受水伤害',
  'purpur.yml.world-settings.default.mobs.creeper.explode-when-killed':
      '苦力怕被杀时是否爆炸',
  'purpur.yml.world-settings.default.mobs.creeper.health-impacts-explosion':
      '生命值是否影响爆炸',
  'purpur.yml.world-settings.default.mobs.creeper.always-drop-exp':
      '苦力怕是否必定掉落经验',
  'purpur.yml.world-settings.default.mobs.creeper.head-visibility-percent':
      '苦力怕头部可见比例',
  'purpur.yml.world-settings.default.mobs.creeper.encircle-target': '苦力怕是否环绕目标',
  'purpur.yml.world-settings.default.mobs.enderman': '末影人设置',
  'purpur.yml.world-settings.default.mobs.enderman.allow-griefing':
      '末影人是否可破坏方块',
  'purpur.yml.world-settings.default.mobs.enderman.can-despawn-with-held-block':
      '末影人持有方块时是否可消失',
  'purpur.yml.world-settings.default.mobs.enderman.takes-damage-from-water':
      '末影人是否受水伤害',
  'purpur.yml.world-settings.default.mobs.enderman.aggressive-towards-endermites':
      '末影人是否攻击末影螨',
  'purpur.yml.world-settings.default.mobs.enderman.disable-player-stare-aggression':
      '是否禁用玩家注视激怒',
  'purpur.yml.world-settings.default.mobs.enderman.ignore-projectiles':
      '末影人是否忽略投掷物',
  'purpur.yml.world-settings.default.mobs.zombie': '僵尸设置',
  'purpur.yml.world-settings.default.mobs.zombie.aggressive-towards-villager-when-lagging':
      '卡顿时僵尸是否仍攻击村民',
  'purpur.yml.world-settings.default.mobs.villager': '村民设置',
  'purpur.yml.world-settings.default.mobs.villager.follow-emerald-blocks':
      '村民是否跟随绿宝石块',
  'purpur.yml.world-settings.default.mobs.villager.can-be-leashed':
      '村民是否可被拴绳拴住',
  'purpur.yml.world-settings.default.mobs.villager.can-breed': '村民是否可繁殖',
  'purpur.yml.world-settings.default.mobs.villager.clerics-farm-warts':
      '牧师是否种植地狱疣',
  'purpur.yml.world-settings.default.mobs.villager.allow-trading': '村民是否允许交易',
  'purpur.yml.world-settings.default.mobs.villager.minimum-demand': '村民最低需求',
  'purpur.yml.world-settings.default.mobs.villager.lobotomize':
      '村民脑白质切除（禁用 AI）',
  'purpur.yml.world-settings.default.mobs.villager.lobotomize.enabled':
      '是否启用村民脑白质切除',
  'purpur.yml.world-settings.default.mobs.villager.lobotomize.check-interval':
      '脑白质检查间隔（Tick）',
  'purpur.yml.world-settings.default.mobs.villager.lobotomize.wait-until-trade-locked':
      '等待交易锁定后再切除',
  'purpur.yml.world-settings.default.mobs.villager.display-trade-item':
      '是否显示交易物品',
  'purpur.yml.world-settings.default.mobs.villager.spawn-iron-golem':
      '村民生成铁傀儡设置',
  'purpur.yml.world-settings.default.mobs.villager.spawn-iron-golem.radius':
      '生成铁傀儡半径',
  'purpur.yml.world-settings.default.mobs.villager.spawn-iron-golem.limit':
      '生成铁傀儡上限',
  'purpur.yml.world-settings.default.mobs.phantom': '幻翼设置',
  'purpur.yml.world-settings.default.mobs.phantom.flames': '幻翼火焰设置',
  'purpur.yml.world-settings.default.mobs.phantom.flames.damage': '幻翼火焰伤害',
  'purpur.yml.world-settings.default.mobs.phantom.flames.fire-time': '幻翼火焰时间',
  'purpur.yml.world-settings.default.mobs.phantom.allow-griefing': '幻翼是否可破坏方块',
  'purpur.yml.world-settings.default.mobs.phantom.attacked-by-crystal-range':
      '末影水晶攻击范围',
  'purpur.yml.world-settings.default.mobs.phantom.attacked-by-crystal-damage':
      '末影水晶伤害值',
  'purpur.yml.world-settings.default.mobs.phantom.orbit-crystal-radius':
      '环绕水晶半径',
  'purpur.yml.world-settings.default.mobs.phantom.spawn': '幻翼生成设置',
  'purpur.yml.world-settings.default.mobs.phantom.spawn.min-sky-darkness':
      '最小天空黑暗度',
  'purpur.yml.world-settings.default.mobs.phantom.spawn.only-above-sea-level':
      '仅在海平面以上生成',
  'purpur.yml.world-settings.default.mobs.phantom.spawn.only-with-visible-sky':
      '仅在可见天空处生成',
  'purpur.yml.world-settings.default.mobs.phantom.spawn.local-difficulty-chance':
      '局部难度概率',
  'purpur.yml.world-settings.default.mobs.phantom.spawn.per-attempt': '每次尝试生成数',
  'purpur.yml.world-settings.default.mobs.phantom.spawn.per-attempt.min':
      '每次尝试最小生成数',
  'purpur.yml.world-settings.default.mobs.phantom.spawn.per-attempt.max':
      '每次尝试最大生成数',
  'purpur.yml.world-settings.default.mobs.phantom.burn-in-light': '光照下燃烧阈值',
  'purpur.yml.world-settings.default.mobs.phantom.burn-in-daylight': '白天是否燃烧',
  'purpur.yml.world-settings.default.mobs.phantom.ignore-players-with-torch':
      '是否忽略持火把玩家',
  'purpur.yml.world-settings.default.mobs.phantom.flames-on-swoop': '俯冲时是否带火',
  'purpur.yml.world-settings.default.mobs.phantom.size': '幻翼体型',
  'purpur.yml.world-settings.default.mobs.phantom.size.min': '最小体型',
  'purpur.yml.world-settings.default.mobs.phantom.size.max': '最大体型',
  'purpur.yml.world-settings.default.mobs.wither': '凋灵设置',
  'purpur.yml.world-settings.default.mobs.wither.health-regen-amount':
      '凋灵生命恢复量',
  'purpur.yml.world-settings.default.mobs.wither.health-regen-delay':
      '凋灵生命恢复延迟（Tick）',
  'purpur.yml.world-settings.default.mobs.wither.can-ride-vehicles':
      '凋灵是否可骑乘载具',
  'purpur.yml.world-settings.default.mobs.wither.explosion-radius': '凋灵爆炸半径',
  'purpur.yml.world-settings.default.mobs.wither.play-spawn-sound': '是否播放生成音效',
  'purpur.yml.world-settings.default.mobs.ender_dragon': '末影龙设置',
  'purpur.yml.world-settings.default.mobs.ender_dragon.always-drop-full-exp':
      '末影龙是否必定掉落全部经验',
  'purpur.yml.world-settings.default.mobs.ender_dragon.can-ride-vehicles':
      '末影龙是否可骑乘载具',
  'purpur.yml.world-settings.default.mobs.allay': '悦灵设置',
  'purpur.yml.world-settings.default.mobs.drowned': '溺尸设置',
  'purpur.yml.world-settings.default.mobs.drowned.can-break-doors': '溺尸是否可破门',
  'purpur.yml.world-settings.default.mobs.drowned.jockey': '溺尸骑鸡设置',
  'purpur.yml.world-settings.default.mobs.drowned.jockey.only-babies':
      '仅幼年溺尸可骑乘',
  'purpur.yml.world-settings.default.mobs.drowned.jockey.chance': '溺尸骑鸡概率',
  'purpur.yml.world-settings.default.mobs.drowned.jockey.try-existing-chickens':
      '是否尝试骑现有鸡',
  'purpur.yml.world-settings.default.mobs.shulker': '潜影贝设置',
  'purpur.yml.world-settings.default.mobs.shulker.spawn-from-bullet':
      '潜影贝从子弹生成',
  'purpur.yml.world-settings.default.mobs.shulker.spawn-from-bullet.base-chance':
      '基础生成概率',
  'purpur.yml.world-settings.default.mobs.shulker.spawn-from-bullet.require-open-lid':
      '需要打开盖子',
  'purpur.yml.world-settings.default.mobs.shulker.spawn-from-bullet.nearby-range':
      '附近范围',
  'purpur.yml.world-settings.default.mobs.shulker.spawn-from-bullet.nearby-equation':
      '附近数量方程',
  'purpur.yml.world-settings.default.mobs.shulker.spawn-from-bullet.random-color':
      '随机颜色',
  'purpur.yml.world-settings.default.mobs.shulker.change-color-with-dye':
      '是否可用染料变色',
  'purpur.yml.world-settings.default.mobs.iron_golem': '铁傀儡设置',
  'purpur.yml.world-settings.default.mobs.iron_golem.poppy-calms-anger':
      '罂粟是否平息愤怒',
  'purpur.yml.world-settings.default.mobs.iron_golem.healing-calms-anger':
      '治疗是否平息愤怒',
  'purpur.yml.world-settings.default.mobs.ravager': '劫兽设置',
  'purpur.yml.world-settings.default.mobs.ravager.griefable-blocks':
      '劫兽可破坏方块列表',
  'purpur.yml.world-settings.default.mobs.ravager.avoid-rabbits': '劫兽是否躲避兔子',
  'purpur.yml.world-settings.default.mobs.snow_golem': '雪傀儡设置',
  'purpur.yml.world-settings.default.mobs.snow_golem.leave-trail-when-ridden':
      '骑乘时是否留下雪迹',
  'purpur.yml.world-settings.default.mobs.snow_golem.pumpkin-can-be-added-back':
      '是否可加回南瓜头',
  'purpur.yml.world-settings.default.mobs.snow_golem.min-shoot-interval-ticks':
      '最小射雪球间隔（Tick）',
  'purpur.yml.world-settings.default.mobs.snow_golem.max-shoot-interval-ticks':
      '最大射雪球间隔（Tick）',
  'purpur.yml.world-settings.default.mobs.snow_golem.snow-ball-modifier':
      '雪球伤害修正',
  'purpur.yml.world-settings.default.mobs.snow_golem.attack-distance': '攻击距离',
  'purpur.yml.world-settings.default.mobs.warden': '监守者设置',
  'purpur.yml.world-settings.default.mobs.warden.can-use-sonic-boom':
      '监守者是否可使用音波攻击',
  'purpur.yml.world-settings.default.mobs.piglin': '猪灵设置',
  'purpur.yml.world-settings.default.mobs.piglin.portal-spawn-modifier':
      '传送门生成修正',
  'purpur.yml.world-settings.default.mobs.piglin.ignores-armor-with-gold-trim':
      '是否忽略金饰护甲',
  'purpur.yml.world-settings.default.mobs.zombie_villager': '僵尸村民设置',
  'purpur.yml.world-settings.default.mobs.zombie_villager.curing_time': '治愈时间',
  'purpur.yml.world-settings.default.mobs.zombie_villager.curing_time.min':
      '最小治愈时间（Tick）',
  'purpur.yml.world-settings.default.mobs.zombie_villager.curing_time.max':
      '最大治愈时间（Tick）',
  'purpur.yml.world-settings.default.mobs.zombie_villager.cure': '治愈设置',
  'purpur.yml.world-settings.default.mobs.zombie_villager.cure.enabled':
      '是否启用治愈',
  'purpur.yml.world-settings.default.mobs.zombified_piglin': '僵尸猪灵设置',
  'purpur.yml.world-settings.default.mobs.zombified_piglin.count-as-player-kill-when-angry':
      '愤怒时是否计入玩家击杀',
  'purpur.yml.world-settings.default.mobs.skeleton': '骷髅设置',
  'purpur.yml.world-settings.default.mobs.skeleton.feed-wither-roses':
      '喂食凋灵玫瑰数量',
  'purpur.yml.world-settings.default.mobs.skeleton.bow-accuracy': '弓箭精度',
  'purpur.yml.world-settings.default.mobs.giant': '巨人设置',
  'purpur.yml.world-settings.default.mobs.giant.movement-speed': '巨人移动速度',
  'purpur.yml.world-settings.default.mobs.giant.attack-damage': '巨人攻击伤害',
  'purpur.yml.world-settings.default.mobs.giant.step-height': '巨人步高',
  'purpur.yml.world-settings.default.mobs.giant.jump-height': '巨人跳跃高度',
  'purpur.yml.world-settings.default.mobs.giant.have-ai': '巨人是否有 AI',
  'purpur.yml.world-settings.default.mobs.giant.have-hostile-ai': '巨人是否有敌对 AI',
  'purpur.yml.world-settings.default.mobs.wolf': '狼设置',
  'purpur.yml.world-settings.default.mobs.wolf.milk-cures-rabid-wolves':
      '牛奶是否治愈狂犬狼',
  'purpur.yml.world-settings.default.mobs.wolf.spawn-rabid-chance': '生成狂犬狼概率',
  'purpur.yml.world-settings.default.mobs.cow': '牛设置',
  'purpur.yml.world-settings.default.mobs.cow.feed-mushrooms-for-mooshroom':
      '喂蘑菇变哞菇数量',
  'purpur.yml.world-settings.default.mobs.cow.naturally-aggressive-to-players':
      '牛自然攻击玩家',
  'purpur.yml.world-settings.default.mobs.cow.naturally-aggressive-to-players.chance':
      '攻击概率',
  'purpur.yml.world-settings.default.mobs.cow.naturally-aggressive-to-players.damage':
      '攻击伤害',
  'purpur.yml.world-settings.default.mobs.chicken': '鸡设置',
  'purpur.yml.world-settings.default.mobs.chicken.retaliate': '鸡是否反击',
  'purpur.yml.world-settings.default.mobs.dolphin': '海豚设置',
  'purpur.yml.world-settings.default.mobs.dolphin.spit': '海豚吐口水设置',
  'purpur.yml.world-settings.default.mobs.dolphin.spit.cooldown': '吐口水冷却（Tick）',
  'purpur.yml.world-settings.default.mobs.dolphin.spit.speed': '吐口水速度',
  'purpur.yml.world-settings.default.mobs.dolphin.spit.damage': '吐口水伤害',
  'purpur.yml.world-settings.default.mobs.dolphin.disable-treasure-searching':
      '是否禁用寻宝',
  'purpur.yml.world-settings.default.mobs.dolphin.naturally-aggressive-to-players-chance':
      '攻击玩家概率',
  'purpur.yml.world-settings.default.mobs.bee': '蜜蜂设置',
  'purpur.yml.world-settings.default.mobs.bee.can-work-at-night': '蜜蜂是否可在夜间工作',
  'purpur.yml.world-settings.default.mobs.bee.can-work-in-rain': '蜜蜂是否可在雨天工作',
  'purpur.yml.world-settings.default.mobs.bee.can-instantly-start-drowning':
      '蜜蜂是否立即开始溺水',
  'purpur.yml.world-settings.default.mobs.bee.dies-after-sting': '蜜蜂蛰后是否死亡',
  'purpur.yml.world-settings.default.mobs.cat': '猫设置',
  'purpur.yml.world-settings.default.mobs.cat.spawn-delay': '猫生成延迟（Tick）',
  'purpur.yml.world-settings.default.mobs.cat.scan-range-for-other-cats':
      '扫描其他猫的范围',
  'purpur.yml.world-settings.default.mobs.cat.scan-range-for-other-cats.swamp-hut':
      '沼泽小屋扫描范围',
  'purpur.yml.world-settings.default.mobs.cat.scan-range-for-other-cats.village':
      '村庄扫描范围',
  'purpur.yml.world-settings.default.mobs.cat.default-collar-color': '默认项圈颜色',
  'purpur.yml.world-settings.default.mobs.happy_ghast': '欢乐妖精',
  'purpur.yml.world-settings.default.mobs.strider': '炽足兽设置',
  'purpur.yml.world-settings.default.mobs.strider.give-saddle-back': '是否返还鞍',
  'purpur.yml.world-settings.default.mobs.vindicator': '卫道士设置',
  'purpur.yml.world-settings.default.mobs.vindicator.johnny': 'Johnny 模式设置',
  'purpur.yml.world-settings.default.mobs.vindicator.johnny.spawn-chance':
      'Johnny 生成概率',
  'purpur.yml.world-settings.default.mobs.turtle': '海龟设置',
  'purpur.yml.world-settings.default.mobs.parrot': '鹦鹉设置',
  'purpur.yml.world-settings.default.mobs.parrot.can-breed': '鹦鹉是否可繁殖',
  'purpur.yml.world-settings.default.mobs.polar_bear': '北极熊设置',
  'purpur.yml.world-settings.default.mobs.polar_bear.breedable-item': '可繁殖物品',
  'purpur.yml.world-settings.default.mobs.rabbit': '兔子设置',
  'purpur.yml.world-settings.default.mobs.rabbit.spawn-toast-chance':
      '生成 Toast 兔概率',
  'purpur.yml.world-settings.default.mobs.rabbit.spawn-killer-rabbit-chance':
      '生成杀手兔概率',
  'purpur.yml.world-settings.default.mobs.silverfish': '蠹虫设置',
  'purpur.yml.world-settings.default.mobs.silverfish.movement_speed': '移动速度',
  'purpur.yml.world-settings.default.mobs.silverfish.attack_damage': '攻击伤害',
  'purpur.yml.world-settings.default.mobs.zombie_horse': '僵尸马设置',
  'purpur.yml.world-settings.default.mobs.zombie_horse.spawn-chance': '生成概率',
  'purpur.yml.world-settings.default.mobs.squid': '鱿鱼设置',
  'purpur.yml.world-settings.default.mobs.squid.immune-to-EAR': '是否免疫实体激活范围',
  'purpur.yml.world-settings.default.mobs.squid.water-offset-check': '水位偏移检查',
  'purpur.yml.world-settings.default.mobs.squid.can-fly': '是否可飞行',
  'purpur.yml.world-settings.default.mobs.glow_squid': '发光鱿鱼设置',
  'purpur.yml.world-settings.default.mobs.glow_squid.can-fly': '发光鱿鱼是否可飞行',
  'purpur.yml.world-settings.default.mobs.wandering_trader': '流浪商人设置',
  'purpur.yml.world-settings.default.mobs.wandering_trader.follow-emerald-blocks':
      '是否跟随绿宝石块',
  'purpur.yml.world-settings.default.mobs.wandering_trader.can-be-leashed':
      '是否可被拴绳拴住',
  'purpur.yml.world-settings.default.mobs.wandering_trader.allow-trading':
      '是否允许交易',
  'purpur.yml.world-settings.default.mobs.tropical_fish': '热带鱼',
  'purpur.yml.world-settings.default.mobs.pufferfish': '河豚',
  'purpur.yml.world-settings.default.mobs.cod': '鳕鱼',
  'purpur.yml.world-settings.default.mobs.salmon': '鲑鱼',
  'purpur.yml.world-settings.default.mobs.llama': '羊驼设置',
  'purpur.yml.world-settings.default.mobs.llama.join-caravans': '是否加入商队',
  'purpur.yml.world-settings.default.mobs.trader_llama': '行商羊驼',
  'purpur.yml.world-settings.default.mobs.mooshroom': '哞菇',
  'purpur.yml.world-settings.default.mobs.piglin_brute': '猪灵蛮兵',
  'purpur.yml.world-settings.default.mobs.hoglin': '疣猪兽',
  'purpur.yml.world-settings.default.mobs.zoglin': '僵尸疣猪兽',
  'purpur.yml.world-settings.default.mobs.stray': '流浪者',
  'purpur.yml.world-settings.default.mobs.husk': '尸壳',
  'purpur.yml.world-settings.default.mobs.cave_spider': '洞穴蜘蛛',
  'purpur.yml.world-settings.default.mobs.spider': '蜘蛛',
  'purpur.yml.world-settings.default.mobs.witch': '女巫',
  'purpur.yml.world-settings.default.mobs.blaze': '烈焰人',
  'purpur.yml.world-settings.default.mobs.ghast': '恶魂',
  'purpur.yml.world-settings.default.mobs.magma_cube': '岩浆怪',
  'purpur.yml.world-settings.default.mobs.slime': '史莱姆',
  'purpur.yml.world-settings.default.mobs.guardian': '守卫者',
  'purpur.yml.world-settings.default.mobs.elder_guardian': '远古守卫者',
  'purpur.yml.world-settings.default.mobs.evoker': '唤魔者',
  'purpur.yml.world-settings.default.mobs.illusioner': '幻术师',
  'purpur.yml.world-settings.default.mobs.armadillo': '犰狳',
  'purpur.yml.world-settings.default.mobs.axolotl': '美西螈',
  'purpur.yml.world-settings.default.mobs.bat': '蝙蝠',
  'purpur.yml.world-settings.default.mobs.camel': '骆驼',
  'purpur.yml.world-settings.default.mobs.donkey': '驴',
  'purpur.yml.world-settings.default.mobs.mule': '骡',
  'purpur.yml.world-settings.default.mobs.horse': '马',
  'purpur.yml.world-settings.default.mobs.skeleton_horse': '骷髅马',
  'purpur.yml.world-settings.default.mobs.ocelot': '豹猫',
  'purpur.yml.world-settings.default.mobs.panda': '熊猫',
  'purpur.yml.world-settings.default.mobs.pig': '猪',
  'purpur.yml.world-settings.default.mobs.sheep': '羊',
  'purpur.yml.world-settings.default.mobs.goat': '山羊',
  'purpur.yml.world-settings.default.mobs.fox': '狐狸',
  'purpur.yml.world-settings.default.mobs.frog': '青蛙',
  'purpur.yml.world-settings.default.mobs.tadpole': '蝌蚪',
  'purpur.yml.world-settings.default.mobs.sniffer': '嗅探兽',
  'purpur.yml.world-settings.default.mobs.vex': '恼鬼',
  'purpur.yml.world-settings.default.mobs.bogged': '沼骸',
  'purpur.yml.world-settings.default.mobs.copper_golem': '铜傀儡',
  'purpur.yml.world-settings.default.mobs.nautilus': '鹦鹉螺',
  'purpur.yml.world-settings.default.mobs.zombie_nautilus': '僵尸鹦鹉螺',

  // mob 通用字段（适用于所有生物的公共字段）
  'purpur.yml.world-settings.default.mobs.*.ridable': '是否可骑乘',
  'purpur.yml.world-settings.default.mobs.*.ridable-in-water': '骑乘时是否可在水中',
  'purpur.yml.world-settings.default.mobs.*.controllable': '是否可用 WASD 控制',
  'purpur.yml.world-settings.default.mobs.*.ridable-max-y': '骑乘时最大 Y 高度',
  'purpur.yml.world-settings.default.mobs.*.attributes': '属性设置',
  'purpur.yml.world-settings.default.mobs.*.attributes.max_health': '最大生命值',
  'purpur.yml.world-settings.default.mobs.*.attributes.scale': '体型缩放',
  'purpur.yml.world-settings.default.mobs.*.attributes.follow_range': '跟踪范围',
  'purpur.yml.world-settings.default.mobs.*.attributes.knockback_resistance':
      '击退抗性',
  'purpur.yml.world-settings.default.mobs.*.attributes.movement_speed': '移动速度',
  'purpur.yml.world-settings.default.mobs.*.attributes.flying_speed': '飞行速度',
  'purpur.yml.world-settings.default.mobs.*.attributes.armor': '护甲值',
  'purpur.yml.world-settings.default.mobs.*.attributes.armor_toughness': '护甲韧性',
  'purpur.yml.world-settings.default.mobs.*.attributes.attack_knockback':
      '攻击击退',
  'purpur.yml.world-settings.default.mobs.*.attributes.attack_damage': '攻击伤害',
  'purpur.yml.world-settings.default.mobs.*.attributes.spawn_reinforcements':
      '生成援军概率',
  'purpur.yml.world-settings.default.mobs.*.attributes.tempt_range': '诱惑范围',
  'purpur.yml.world-settings.default.mobs.*.attributes.step_height': '步高',
  'purpur.yml.world-settings.default.mobs.*.attributes.jump_strength': '跳跃强度',
  'purpur.yml.world-settings.default.mobs.*.attributes.max_health.min': '最小生命值',
  'purpur.yml.world-settings.default.mobs.*.attributes.max_health.max': '最大生命值',
  'purpur.yml.world-settings.default.mobs.*.attributes.jump_strength.min':
      '最小跳跃强度',
  'purpur.yml.world-settings.default.mobs.*.attributes.jump_strength.max':
      '最大跳跃强度',
  'purpur.yml.world-settings.default.mobs.*.attributes.movement_speed.min':
      '最小移动速度',
  'purpur.yml.world-settings.default.mobs.*.attributes.movement_speed.max':
      '最大移动速度',
  'purpur.yml.world-settings.default.mobs.*.breeding-delay-ticks': '繁殖延迟（Tick）',
  'purpur.yml.world-settings.default.mobs.*.takes-damage-from-water': '是否受水伤害',
  'purpur.yml.world-settings.default.mobs.*.always-drop-exp': '是否必定掉落经验',
  'purpur.yml.world-settings.default.mobs.*.mob-griefing-override':
      '生物破坏覆盖（default/true/false）',
  'purpur.yml.world-settings.default.mobs.*.can-pick-up-loot':
      '是否可拾取掉落物（default/true/false）',
  'purpur.yml.world-settings.default.mobs.*.allow-griefing': '是否可破坏方块',
  'purpur.yml.world-settings.default.mobs.*.head-visibility-percent': '头部可见比例',
  'purpur.yml.world-settings.default.mobs.*.jockey': '骑乘生成设置',
  'purpur.yml.world-settings.default.mobs.*.jockey.only-babies': '仅幼年可骑乘',
  'purpur.yml.world-settings.default.mobs.*.jockey.chance': '骑乘生成概率',
  'purpur.yml.world-settings.default.mobs.*.jockey.try-existing-chickens':
      '是否尝试骑现有鸡',
  'purpur.yml.world-settings.default.mobs.*.can-swim': '是否可游泳',
  'purpur.yml.world-settings.default.mobs.*.can-breed': '是否可繁殖',
  'purpur.yml.world-settings.default.mobs.*.give-saddle-back': '是否返还鞍',
  'purpur.yml.world-settings.default.mobs.*.default-collar-color': '默认项圈颜色',
  'purpur.yml.world-settings.default.mobs.*.movement-speed': '移动速度（旧版字段）',
  'purpur.yml.world-settings.default.mobs.*.attack-damage': '攻击伤害（旧版字段）',
  'purpur.yml.world-settings.default.mobs.*.follow-range': '跟踪范围（旧版字段）',
  'purpur.yml.world-settings.default.mobs.*.step-height': '步高（旧版字段）',
  'purpur.yml.world-settings.default.mobs.*.jump-height': '跳跃高度（旧版字段）',
  'purpur.yml.world-settings.default.mobs.*.have-ai': '是否有 AI',
  'purpur.yml.world-settings.default.mobs.*.have-hostile-ai': '是否有敌对 AI',
  'purpur.yml.world-settings.default.mobs.*.ridable-jump-height': '骑乘跳跃高度',

  // world-settings.default.tools 工具设置
  'purpur.yml.world-settings.default.tools': '工具行为设置',
  'purpur.yml.world-settings.default.tools.axe': '斧设置',
  'purpur.yml.world-settings.default.tools.axe.strippables': '可剥皮方块列表',
  'purpur.yml.world-settings.default.tools.axe.waxables': '可去蜡方块列表',
  'purpur.yml.world-settings.default.tools.axe.weatherables': '可除锈方块列表',
  'purpur.yml.world-settings.default.tools.hoe': '锄设置',
  'purpur.yml.world-settings.default.tools.hoe.tillables': '可耕地方块列表',
  'purpur.yml.world-settings.default.tools.hoe.replant-crops': '是否自动补种作物',
  'purpur.yml.world-settings.default.tools.hoe.replant-nether-warts':
      '是否自动补种地狱疣',
  'purpur.yml.world-settings.default.tools.shovel': '铲设置',
  'purpur.yml.world-settings.default.tools.shovel.flattenables': '可平整化方块列表',

  // world-settings.default.ridable-settings 骑乘设置
  'purpur.yml.world-settings.default.ridable-settings': '骑乘通用设置',
  'purpur.yml.world-settings.default.ridable-settings.babies-are-ridable':
      '幼年生物是否可骑乘',
  'purpur.yml.world-settings.default.ridable-settings.untamed-tamables-are-ridable':
      '未驯服的可驯服生物是否可骑乘',
  'purpur.yml.world-settings.default.ridable-settings.use-night-vision':
      '骑乘时是否给予夜视',
  'purpur.yml.world-settings.default.ridable-settings.use-dismounts-underwater-tag':
      '是否使用水下骑乘标签',

  // world-settings.default.hunger 饥饿设置
  'purpur.yml.world-settings.default.hunger': '饥饿设置',
  'purpur.yml.world-settings.default.hunger.starvation-damage': '饥饿伤害值',

  // world-settings.default.gameplay-mechanics 游戏机制
  'purpur.yml.world-settings.default.gameplay-mechanics': '游戏机制设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.entity-lifespan':
      '实体生命周期（Tick，0=无限）',
  'purpur.yml.world-settings.default.gameplay-mechanics.entity-left-handed-chance':
      '实体左手概率',
  'purpur.yml.world-settings.default.gameplay-mechanics.elytra': '鞘翅设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.elytra.damage-per-second':
      '鞘翅每秒耐久损耗',
  'purpur.yml.world-settings.default.gameplay-mechanics.elytra.damage-multiplied-by-speed':
      '速度影响耐久损耗倍率',
  'purpur.yml.world-settings.default.gameplay-mechanics.elytra.damage-per-boost':
      '加速时耐久损耗',
  'purpur.yml.world-settings.default.gameplay-mechanics.elytra.damage-per-boost.firework':
      '烟花加速耐久损耗',
  'purpur.yml.world-settings.default.gameplay-mechanics.elytra.damage-per-boost.trident':
      '三叉戟加速耐久损耗',
  'purpur.yml.world-settings.default.gameplay-mechanics.elytra.kinetic-damage':
      '是否承受动能伤害',
  'purpur.yml.world-settings.default.gameplay-mechanics.infinity-bow': '无限弓设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.infinity-bow.works-without-arrows':
      '无限弓是否无需箭矢',
  'purpur.yml.world-settings.default.gameplay-mechanics.item': '物品设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.immune': '物品免疫设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.immune.cactus':
      '仙人掌免疫的物品',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.immune.explosion':
      '爆炸免疫的物品',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.immune.fire':
      '火焰免疫的物品',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.immune.lightning':
      '闪电免疫的物品',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.shears': '剪刀设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.shears.damage-if-sprinting':
      '疾跑时是否损坏剪刀',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.shears.damage-if-sprinting-item-model':
      '疾跑损坏剪刀的物品模型',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.shears.ignore-in-water':
      '水中是否忽略损坏',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.shears.ignore-in-lava':
      '岩浆中是否忽略损坏',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.shears.sprinting-damage':
      '疾跑损坏值',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.shears.defuse-tnt-chance':
      '拆除 TNT 概率',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.ender-pearl':
      '末影珍珠设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.ender-pearl.damage':
      '末影珍珠伤害',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.ender-pearl.cooldown':
      '末影珍珠冷却（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.ender-pearl.creative-cooldown':
      '创造模式冷却（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.ender-pearl.endermite-spawn-chance':
      '末影螨生成概率',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.glow_berries':
      '发光浆果设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.glow_berries.eat-glow-duration':
      '食用发光时长（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.shulker_box':
      '潜影盒设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.shulker_box.drop-contents-when-destroyed':
      '破坏时是否掉落内容物',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.compass': '指南针设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.compass.holding-shows-bossbar':
      '手持时是否显示 Boss 条',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.snowball': '雪球设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.snowball.extinguish':
      '雪球灭火设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.snowball.extinguish.fire':
      '是否灭火',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.snowball.extinguish.candles':
      '是否灭蜡烛',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.snowball.extinguish.campfires':
      '是否灭营火',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.end-crystal':
      '末影水晶物品',
  'purpur.yml.world-settings.default.gameplay-mechanics.item.end-crystal.place-anywhere':
      '是否可任意放置',
  'purpur.yml.world-settings.default.gameplay-mechanics.armorstand': '盔甲架设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.armorstand.step-height':
      '盔甲架步高',
  'purpur.yml.world-settings.default.gameplay-mechanics.armorstand.set-name-visible-when-placing-with-custom-name':
      '放置时是否显示自定义名称',
  'purpur.yml.world-settings.default.gameplay-mechanics.armorstand.fix-nametags':
      '是否修复名牌',
  'purpur.yml.world-settings.default.gameplay-mechanics.armorstand.can-movement-tick':
      '是否可移动 Tick',
  'purpur.yml.world-settings.default.gameplay-mechanics.armorstand.can-move-in-water':
      '是否可在水中移动',
  'purpur.yml.world-settings.default.gameplay-mechanics.armorstand.can-move-in-water-over-fence':
      '是否可越过栅栏',
  'purpur.yml.world-settings.default.gameplay-mechanics.armorstand.place-with-arms-visible':
      '放置时是否显示手臂',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-spawning': '怪物生成设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-spawning.village-cats':
      '村庄猫生成（default/true/false）',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-spawning.raid-patrols':
      '袭击巡逻（default/true/false）',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-spawning.phantoms':
      '幻翼（default/true/false）',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-spawning.wandering-traders':
      '流浪商人（default/true/false）',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-spawning.village-sieges':
      '村庄围攻（default/true/false）',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-spawning.ignore-creative-players':
      '是否忽略创造模式玩家',
  'purpur.yml.world-settings.default.gameplay-mechanics.player': '玩家设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.idle-timeout':
      '挂机超时设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.idle-timeout.kick-if-idle':
      '挂机是否踢出',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.idle-timeout.tick-nearby-entities':
      '是否 Tick 附近实体',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.idle-timeout.count-as-sleeping':
      '是否计入睡觉',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.idle-timeout.update-tab-list':
      '是否更新 Tab 列表',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.idle-timeout.mobs-target':
      '怪物是否可攻击',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.exp-dropped-on-death':
      '死亡掉落经验',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.exp-dropped-on-death.equation':
      '经验掉落公式',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.exp-dropped-on-death.maximum':
      '最大掉落经验',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.teleport-if-outside-border':
      '出边界是否传送',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.teleport-on-nether-ceiling-damage':
      '下界天花板伤害时传送',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.totem-of-undying-works-in-inventory':
      '不死图腾是否在背包生效',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.fix-stuck-in-portal':
      '是否修复卡在传送门',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.one-punch-in-creative':
      '创造模式是否一拳秒杀',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.sleep-ignore-nearby-mobs':
      '睡觉是否忽略附近怪物',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.can-skip-night':
      '是否可跳过夜晚',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.critical-damage-multiplier':
      '暴击伤害倍率',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.burp-delay':
      '饱嗝延迟（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.burp-when-full':
      '饱食时是否打嗝',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.ridable-in-water':
      '骑乘玩家是否可在水中',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.curse-of-binding':
      '绑定诅咒设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.curse-of-binding.remove-with-weakness':
      '虚弱时是否可移除',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.shift-right-click-repairs-mending-points':
      '潜行右键修复经验修补点数',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.exp-pickup-delay-ticks':
      '经验拾取延迟（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.allow-void-trading':
      '是否允许虚空交易',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.netherite-fire-resistance':
      '下界合金防火设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.netherite-fire-resistance.duration':
      '持续时间（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.netherite-fire-resistance.amplifier':
      '效果等级',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.netherite-fire-resistance.ambient':
      '是否为环境效果',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.netherite-fire-resistance.show-particles':
      '是否显示粒子',
  'purpur.yml.world-settings.default.gameplay-mechanics.player.netherite-fire-resistance.show-icon':
      '是否显示图标',
  'purpur.yml.world-settings.default.gameplay-mechanics.drowning': '溺水设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.drowning.air-ticks':
      '空气量（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.drowning.ticks-per-damage':
      '伤害间隔（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.drowning.damage-from-drowning':
      '溺水伤害值',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-effects': '生物效果设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-effects.health-regen-amount':
      '生命恢复量',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-effects.minimal-health-poison-amount':
      '中毒时最低生命值',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-effects.poison-degeneration-amount':
      '中毒扣血量',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-effects.wither-degeneration-amount':
      '凋零扣血量',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-effects.hunger-exhaustion-amount':
      '饥饿疲惫值',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-effects.saturation-regen-amount':
      '饱和恢复量',
  'purpur.yml.world-settings.default.gameplay-mechanics.daylight-cycle-ticks':
      '昼夜循环 Tick',
  'purpur.yml.world-settings.default.gameplay-mechanics.daylight-cycle-ticks.daytime':
      '白天时长（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.daylight-cycle-ticks.nighttime':
      '夜晚时长（Tick）',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-damage':
      '投掷物伤害',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-damage.snowball':
      '雪球伤害（-1=默认）',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-offset':
      '投掷物偏移',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-offset.bow':
      '弓偏移',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-offset.crossbow':
      '弩偏移',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-offset.egg':
      '鸡蛋偏移',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-offset.ender-pearl':
      '末影珍珠偏移',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-offset.throwable-potion':
      '喷溅药水偏移',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-offset.trident':
      '三叉戟偏移',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectile-offset.snowball':
      '雪球偏移',
  'purpur.yml.world-settings.default.gameplay-mechanics.silk-touch': '精准采集设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.silk-touch.enabled':
      '是否启用精准采集刷怪笼',
  'purpur.yml.world-settings.default.gameplay-mechanics.silk-touch.spawner-name':
      '刷怪笼物品名称',
  'purpur.yml.world-settings.default.gameplay-mechanics.silk-touch.minimal-level':
      '所需附魔等级',
  'purpur.yml.world-settings.default.gameplay-mechanics.silk-touch.spawner-lore':
      '刷怪笼 Lore',
  'purpur.yml.world-settings.default.gameplay-mechanics.silk-touch.tools':
      '可用工具列表',
  'purpur.yml.world-settings.default.gameplay-mechanics.halloween': '万圣节设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.halloween.force':
      '是否强制万圣节',
  'purpur.yml.world-settings.default.gameplay-mechanics.halloween.head-chance':
      '南瓜头概率',
  'purpur.yml.world-settings.default.gameplay-mechanics.use-better-mending':
      '是否使用更好的经验修补',
  'purpur.yml.world-settings.default.gameplay-mechanics.always-tame-in-creative':
      '创造模式是否必定驯服',
  'purpur.yml.world-settings.default.gameplay-mechanics.boat': '船设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.boat.eject-players-on-land':
      '落地时是否弹出玩家',
  'purpur.yml.world-settings.default.gameplay-mechanics.boat.do-fall-damage':
      '是否造成坠落伤害',
  'purpur.yml.world-settings.default.gameplay-mechanics.disable-drops-on-cramming-death':
      '挤压死亡时是否禁用掉落',
  'purpur.yml.world-settings.default.gameplay-mechanics.milk-cures-bad-omen':
      '牛奶是否消除坏兆',
  'purpur.yml.world-settings.default.gameplay-mechanics.trident-loyalty-void-return-height':
      '三叉戟忠诚返回高度',
  'purpur.yml.world-settings.default.gameplay-mechanics.entities-can-use-portals':
      '实体是否可使用传送门',
  'purpur.yml.world-settings.default.gameplay-mechanics.raid-cooldown-seconds':
      '袭击冷却秒数',
  'purpur.yml.world-settings.default.gameplay-mechanics.animal-breeding-cooldown-seconds':
      '动物繁殖冷却秒数',
  'purpur.yml.world-settings.default.gameplay-mechanics.persistent-droppable-entity-display-names':
      '实体是否保留可掉落显示名',
  'purpur.yml.world-settings.default.gameplay-mechanics.fireballs-mob-griefing-override':
      '火球生物破坏覆盖',
  'purpur.yml.world-settings.default.gameplay-mechanics.projectiles-mob-griefing-override':
      '投掷物生物破坏覆盖',
  'purpur.yml.world-settings.default.gameplay-mechanics.note-block-ignore-above':
      '音符盒是否忽略上方方块',
  'purpur.yml.world-settings.default.gameplay-mechanics.impose-teleport-restrictions-on-gateways':
      '末地传送门是否限制传送',
  'purpur.yml.world-settings.default.gameplay-mechanics.impose-teleport-restrictions-on-nether-portals':
      '下界传送门是否限制传送',
  'purpur.yml.world-settings.default.gameplay-mechanics.impose-teleport-restrictions-on-end-portals':
      '末地传送门是否限制传送',
  'purpur.yml.world-settings.default.gameplay-mechanics.tick-fluids':
      '是否 Tick 流体',
  'purpur.yml.world-settings.default.gameplay-mechanics.entity-blindness-multiplier':
      '失明效果倍率',
  'purpur.yml.world-settings.default.gameplay-mechanics.mobs-ignore-rails':
      '怪物是否忽略铁轨',
  'purpur.yml.world-settings.default.gameplay-mechanics.rain-stops-after-sleep':
      '睡觉后是否停止下雨',
  'purpur.yml.world-settings.default.gameplay-mechanics.thunder-stops-after-sleep':
      '睡觉后是否停止雷雨',
  'purpur.yml.world-settings.default.gameplay-mechanics.persistent-tileentity-lore':
      '方块实体是否保留 Lore',
  'purpur.yml.world-settings.default.gameplay-mechanics.persistent-tileentity-display-name':
      '方块实体是否保留显示名',
  'purpur.yml.world-settings.default.gameplay-mechanics.mob-last-hurt-by-player-time':
      '怪物被玩家伤害持续时间',
  'purpur.yml.world-settings.default.gameplay-mechanics.milk-clears-beneficial-effects':
      '牛奶是否清除增益效果',
  'purpur.yml.world-settings.default.gameplay-mechanics.disable-oxidation-proximity-penalty':
      '是否禁用氧化邻近惩罚',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart': '矿车设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.max-speed':
      '矿车最大速度',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.place-anywhere':
      '是否可任意放置',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.powered-rail':
      '充能铁轨设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.powered-rail.boost-modifier':
      '加速修正',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.controllable':
      '可控矿车设置',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.controllable.enabled':
      '是否启用可控矿车',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.controllable.step-height':
      '步高',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.controllable.hop-boost':
      '跳跃加速',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.controllable.fall-damage':
      '是否受坠落伤害',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.controllable.base-speed':
      '基础速度',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.controllable.block-speed':
      '方块速度',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.controllable.block-speed.grass_block':
      '草方块上速度',
  'purpur.yml.world-settings.default.gameplay-mechanics.minecart.controllable.block-speed.stone':
      '石头上速度',

  // ==================== gale-global.yml ====================
  'gale-global.yml._version': '配置文件版本（请勿手动修改）',
  'gale-global.yml.gameplay-mechanics': '游戏机制设置',
  'gale-global.yml.gameplay-mechanics.enable-book-writing': '是否允许玩家在书中写入内容',
  'gale-global.yml.log-to-console': '控制台日志设置',
  'gale-global.yml.log-to-console.chat': '聊天相关日志',
  'gale-global.yml.log-to-console.chat.empty-message-warning': '是否记录空消息警告',
  'gale-global.yml.log-to-console.chat.expired-message-warning': '是否记录过期消息警告',
  'gale-global.yml.log-to-console.chat.not-secure-marker': '是否标记非安全消息',
  'gale-global.yml.log-to-console.ignored-advancements': '是否记录被忽略的成就',
  'gale-global.yml.log-to-console.invalid-legacy-text-component':
      '是否记录无效的旧版文本组件',
  'gale-global.yml.log-to-console.invalid-statistics': '是否记录无效统计数据',
  'gale-global.yml.log-to-console.legacy-material-initialization':
      '是否记录旧版材料初始化日志',
  'gale-global.yml.log-to-console.null-id-disconnections': '是否记录空 ID 断开连接',
  'gale-global.yml.log-to-console.player-login-locations': '是否记录玩家登录位置',
  'gale-global.yml.log-to-console.plugin-library-loader': '插件库加载器日志',
  'gale-global.yml.log-to-console.plugin-library-loader.downloads': '是否记录库下载日志',
  'gale-global.yml.log-to-console.plugin-library-loader.library-loaded':
      '是否记录库加载完成日志',
  'gale-global.yml.log-to-console.plugin-library-loader.start-load-libraries-for-plugin':
      '是否记录开始为插件加载库',
  'gale-global.yml.log-to-console.set-block-in-far-chunk': '是否记录在远处区块设置方块',
  'gale-global.yml.log-to-console.unrecognized-recipes': '是否记录未识别的配方',
  'gale-global.yml.misc': '杂项设置',
  'gale-global.yml.misc.ignore-null-legacy-structure-data': '是否忽略空的旧版结构数据',
  'gale-global.yml.misc.keepalive': '心跳保持设置',
  'gale-global.yml.misc.keepalive.send-multiple': '是否发送多个心跳',
  'gale-global.yml.misc.last-tick-time-in-tps-command': 'TPS 命令中上一刻时间设置',
  'gale-global.yml.misc.last-tick-time-in-tps-command.add-oversleep':
      '是否添加超时睡眠时间',
  'gale-global.yml.misc.last-tick-time-in-tps-command.enabled': '是否启用',
  'gale-global.yml.misc.premium-account-slow-login-timeout': '正版账户慢登录超时（-1=禁用）',
  'gale-global.yml.misc.verify-chat-order': '是否验证聊天顺序',
  'gale-global.yml.small-optimizations': '小型优化设置',
  'gale-global.yml.small-optimizations.reduced-intervals': '降低检测间隔',
  'gale-global.yml.small-optimizations.reduced-intervals.increase-time-statistics':
      '增加时间统计间隔倍数',
  'gale-global.yml.small-optimizations.reduced-intervals.update-entity-line-of-sight':
      '更新实体视线间隔倍数',

  // ==================== gale-world-defaults.yml ====================
  'gale-world-defaults.yml._version': '配置文件版本（请勿手动修改）',
  'gale-world-defaults.yml.gameplay-mechanics': '游戏机制设置',
  'gale-world-defaults.yml.gameplay-mechanics.entities-can-random-stroll-into-non-ticking-chunks':
      '实体是否可随机走入非活动区块',
  'gale-world-defaults.yml.gameplay-mechanics.entity-wake-up-duration-ratio-standard-deviation':
      '实体唤醒持续时间比率标准差',
  'gale-world-defaults.yml.gameplay-mechanics.fixes': '修复设置',
  'gale-world-defaults.yml.gameplay-mechanics.fixes.broadcast-crit-animations-as-the-entity-being-critted':
      '是否广播暴击动画给被暴击的实体',
  'gale-world-defaults.yml.gameplay-mechanics.fixes.mc-121706':
      '修复 MC-121706（实体渲染问题）',
  'gale-world-defaults.yml.gameplay-mechanics.fixes.mc-238526':
      '修复 MC-238526（刷怪笼问题）',
  'gale-world-defaults.yml.gameplay-mechanics.hide-flames-on-entities-with-fire-resistance':
      '抗火效果的实体是否隐藏火焰',
  'gale-world-defaults.yml.gameplay-mechanics.try-respawn-ender-dragon-after-end-crystal-place':
      '放置末影水晶后是否尝试重生末影龙',
  'gale-world-defaults.yml.small-optimizations': '小型优化设置',
  'gale-world-defaults.yml.small-optimizations.load-chunks': '区块加载优化',
  'gale-world-defaults.yml.small-optimizations.load-chunks.to-activate-climbing-entities':
      '是否加载区块以激活攀爬实体',
  'gale-world-defaults.yml.small-optimizations.load-chunks.to-spawn-phantoms':
      '是否加载区块以生成幻翼',
  'gale-world-defaults.yml.small-optimizations.max-projectile-chunk-loads':
      '投掷物区块加载上限',
  'gale-world-defaults.yml.small-optimizations.max-projectile-chunk-loads.per-projectile':
      '每个投掷物限制',
  'gale-world-defaults.yml.small-optimizations.max-projectile-chunk-loads.per-projectile.max':
      '最大区块加载数',
  'gale-world-defaults.yml.small-optimizations.max-projectile-chunk-loads.per-projectile.remove-from-world-after-reach-limit':
      '达到上限后是否从世界移除',
  'gale-world-defaults.yml.small-optimizations.max-projectile-chunk-loads.per-projectile.reset-movement-after-reach-limit':
      '达到上限后是否重置移动',
  'gale-world-defaults.yml.small-optimizations.max-projectile-chunk-loads.per-tick':
      '每 Tick 区块加载上限',
  'gale-world-defaults.yml.small-optimizations.reduced-intervals': '降低检测间隔',
  'gale-world-defaults.yml.small-optimizations.reduced-intervals.check-stuck-in-wall':
      '检测卡墙间隔倍数',
  'gale-world-defaults.yml.small-optimizations.reduced-intervals.villager-item-repickup':
      '村民物品拾取间隔倍数',
  'gale-world-defaults.yml.small-optimizations.save-fireworks': '是否保存烟花',
  'gale-world-defaults.yml.small-optimizations.use-optimized-sheep-offspring-color':
      '是否使用优化的羊后代颜色计算',

  // ==================== leaf-global.yml ====================
  'leaf-global.yml.config-version': '配置文件版本（请勿手动修改）',

  // async 异步设置
  'leaf-global.yml.async': '异步设置',
  'leaf-global.yml.async.async-chunk-send': '异步区块发送',
  'leaf-global.yml.async.async-chunk-send.enabled': '是否启用异步区块数据包发送',
  'leaf-global.yml.async.async-mob-spawning': '异步生物生成',
  'leaf-global.yml.async.async-mob-spawning.enabled':
      '是否启用异步生物生成（需开启 per-player-mob-spawns）',
  'leaf-global.yml.async.async-pathfinding': '异步寻路',
  'leaf-global.yml.async.async-pathfinding.enabled': '是否启用异步寻路',
  'leaf-global.yml.async.async-pathfinding.max-threads': '最大线程数（0=自动）',
  'leaf-global.yml.async.async-pathfinding.keepalive': '线程保活时间（秒）',
  'leaf-global.yml.async.async-pathfinding.queue-size': '队列大小（0=自动）',
  'leaf-global.yml.async.async-pathfinding.reject-policy':
      '队列满时的拒绝策略（FLUSH_ALL/CALLER_RUNS）',
  'leaf-global.yml.async.async-playerdata-save': '异步玩家数据保存',
  'leaf-global.yml.async.async-playerdata-save.enabled': '是否启用异步保存玩家数据',
  'leaf-global.yml.async.async-entity-tracker': '异步实体跟踪（实验性）',
  'leaf-global.yml.async.async-entity-tracker.enabled': '是否启用异步实体跟踪',
  'leaf-global.yml.async.async-entity-tracker.threads': '线程数（0=自动）',
  'leaf-global.yml.async.parallel-world-ticking': '并行世界处理（实验性）',
  'leaf-global.yml.async.parallel-world-ticking.enabled': '是否启用并行世界 Tick',
  'leaf-global.yml.async.parallel-world-ticking.threads': '并行线程数',
  'leaf-global.yml.async.parallel-world-ticking.log-container-creation-stacktraces':
      '是否记录容器创建堆栈',
  'leaf-global.yml.async.parallel-world-ticking.disable-hard-throw':
      '是否禁用硬异常抛出',
  'leaf-global.yml.async.parallel-world-ticking.async-unsafe-read-handling':
      '异步不安全读取处理（DISABLED/ALLOWED）',

  // performance 性能设置
  'leaf-global.yml.performance': '性能设置',
  'leaf-global.yml.performance.check-survival-before-growth': '生长前存活检查',
  'leaf-global.yml.performance.check-survival-before-growth.cactus-check-survival':
      '仙人掌生长前检查存活',
  'leaf-global.yml.performance.despawn-time': '消失时间设置',
  'leaf-global.yml.performance.despawn-time.proactive-weak-loading-despawn':
      '启用主动弱加载实体消失检查（实验性）',
  'leaf-global.yml.performance.dont-save-entity': '不保存实体设置',
  'leaf-global.yml.performance.dont-save-entity.dont-save-primed-tnt':
      '区块卸载时不保存激活的 TNT',
  'leaf-global.yml.performance.dont-save-entity.dont-save-falling-block':
      '区块卸载时不保存掉落的方块',
  'leaf-global.yml.performance.dab': '动态实体激活距离（DAB）',
  'leaf-global.yml.performance.dab.enabled': '是否启用 DAB',
  'leaf-global.yml.performance.dab.dont-enable-if-in-water': '水中非水生生物不受 DAB 影响',
  'leaf-global.yml.performance.dab.start-distance': 'DAB 开始生效距离',
  'leaf-global.yml.performance.dab.max-tick-freq': '最远实体 Tick 间隔',
  'leaf-global.yml.performance.dab.activation-dist-mod': '激活距离修正值',
  'leaf-global.yml.performance.dab.blacklisted-entities': 'DAB 黑名单实体列表',
  'leaf-global.yml.performance.enable-cached-minecraft-to-bukkit-entitytype-convert':
      '是否缓存实体类型转换',
  'leaf-global.yml.performance.entity-goal': '实体目标设置',
  'leaf-global.yml.performance.entity-goal.start-tick-chance': '开始 Tick 概率',
  'leaf-global.yml.performance.entity-goal.start-tick-chance.nearest-attackable-target':
      '最近攻击目标概率（-1=默认）',
  'leaf-global.yml.performance.entity-goal.start-tick-chance.follow-parent':
      '跟随父母概率（-1=默认）',
  'leaf-global.yml.performance.entity-goal.start-tick-chance.avoid-entity':
      '躲避实体概率（-1=默认）',
  'leaf-global.yml.performance.entity-goal.start-tick-chance.temptation':
      '诱惑概率（-1=默认）',
  'leaf-global.yml.performance.entity-goal.start-tick-chance.enderman-look-for-player':
      '末影人寻找玩家概率（-1=默认）',
  'leaf-global.yml.performance.fast-biome-manager-seed-obfuscation':
      '快速生物群系管理器种子混淆',
  'leaf-global.yml.performance.fast-biome-manager-seed-obfuscation.enabled':
      '是否启用 XXHash 种子混淆',
  'leaf-global.yml.performance.fast-biome-manager-seed-obfuscation.seed-obfuscation-key':
      '混淆种子',
  'leaf-global.yml.performance.faster-random-generator': '更快的随机生成器',
  'leaf-global.yml.performance.faster-random-generator.enabled':
      '是否启用 Xoroshiro128PlusPlus',
  'leaf-global.yml.performance.faster-random-generator.enable-for-worldgen':
      '是否用于世界生成（警告：影响世界生成）',
  'leaf-global.yml.performance.faster-random-generator.warn-for-slime-chunk':
      '史莱姆区块是否警告使用原版随机',
  'leaf-global.yml.performance.faster-random-generator.use-legacy-random-for-slime-chunk':
      '史莱姆区块是否使用原版随机',
  'leaf-global.yml.performance.faster-structure-gen-future-sequencing':
      '更快的结构生成任务分段',
  'leaf-global.yml.performance.reuse-random-ticking-blockpos':
      '复用随机 Tick 的 BlockPos（实验性）',
  'leaf-global.yml.performance.cache-biome': '缓存生物群系',
  'leaf-global.yml.performance.cache-biome.enabled': '是否启用生物群系缓存',
  'leaf-global.yml.performance.cache-biome.mob-spawning': '是否缓存生物生成群系',
  'leaf-global.yml.performance.cache-biome.advancements': '是否缓存成就群系',
  'leaf-global.yml.performance.optimize-block-entities': '是否优化方块实体',
  'leaf-global.yml.performance.optimize-mob-despawn': '是否优化生物消失',
  'leaf-global.yml.performance.only-tick-items-in-hand': '仅 Tick 主副手物品',
  'leaf-global.yml.performance.optimize-mob-spawning': '是否优化生物生成',
  'leaf-global.yml.performance.optimize-no-action-time': '优化无动作时间',
  'leaf-global.yml.performance.optimize-no-action-time.disable-light-check':
      '是否禁用光照检查',
  'leaf-global.yml.performance.optimize-player-movement': '是否优化玩家移动处理',
  'leaf-global.yml.performance.optimize-random-tick': '是否优化随机 Tick',
  'leaf-global.yml.performance.optimize-waypoint': '是否优化路径点',
  'leaf-global.yml.performance.optimized-powered-rails': '是否使用优化的动力铁轨',
  'leaf-global.yml.performance.reduce-packets': '减少数据包',
  'leaf-global.yml.performance.reduce-packets.reduce-entity-move-packets':
      '是否减少实体移动数据包',
  'leaf-global.yml.performance.reduce-packets.reduce-entity-motion-packets':
      '是否减少实体运动数据包',
  'leaf-global.yml.performance.reduce-packets.disable-useless-particles':
      '是否禁用无用粒子',
  'leaf-global.yml.performance.skip-ai-for-non-aware-mob': '非感知生物是否跳过 AI',
  'leaf-global.yml.performance.datapack': '数据包设置',
  'leaf-global.yml.performance.datapack.skip-inactive-entity-for-execute-command':
      'execute 命令是否跳过不活跃实体',
  'leaf-global.yml.performance.skip-map-item-data-updates-if-map-does-not-have-craftmaprenderer':
      '地图无渲染器时跳过数据更新',
  'leaf-global.yml.performance.sleeping-block-entity': '方块实体睡眠优化',
  'leaf-global.yml.performance.throttle-mob-spawning': '节流生物生成',
  'leaf-global.yml.performance.throttle-mob-spawning.enabled': '是否启用生成节流',
  'leaf-global.yml.performance.throttle-mob-spawning.monster': '怪物生成节流',
  'leaf-global.yml.performance.throttle-mob-spawning.monster.min-failed':
      '最小失败次数',
  'leaf-global.yml.performance.throttle-mob-spawning.monster.spawn-chance':
      '生成概率（0-100）',
  'leaf-global.yml.performance.throttle-mob-spawning.creature': '动物生成节流',
  'leaf-global.yml.performance.throttle-mob-spawning.creature.min-failed':
      '最小失败次数',
  'leaf-global.yml.performance.throttle-mob-spawning.creature.spawn-chance':
      '生成概率',
  'leaf-global.yml.performance.throttle-mob-spawning.ambient': '环境生物生成节流',
  'leaf-global.yml.performance.throttle-mob-spawning.ambient.min-failed':
      '最小失败次数',
  'leaf-global.yml.performance.throttle-mob-spawning.ambient.spawn-chance':
      '生成概率',
  'leaf-global.yml.performance.throttle-mob-spawning.axolotls': '美西螈生成节流',
  'leaf-global.yml.performance.throttle-mob-spawning.axolotls.min-failed':
      '最小失败次数',
  'leaf-global.yml.performance.throttle-mob-spawning.axolotls.spawn-chance':
      '生成概率',
  'leaf-global.yml.performance.throttle-mob-spawning.underground_water_creature':
      '地下水生物生成节流',
  'leaf-global.yml.performance.throttle-mob-spawning.underground_water_creature.min-failed':
      '最小失败次数',
  'leaf-global.yml.performance.throttle-mob-spawning.underground_water_creature.spawn-chance':
      '生成概率',
  'leaf-global.yml.performance.throttle-mob-spawning.water_creature': '水生物生成节流',
  'leaf-global.yml.performance.throttle-mob-spawning.water_creature.min-failed':
      '最小失败次数',
  'leaf-global.yml.performance.throttle-mob-spawning.water_creature.spawn-chance':
      '生成概率',
  'leaf-global.yml.performance.throttle-mob-spawning.water_ambient':
      '水环境生物生成节流',
  'leaf-global.yml.performance.throttle-mob-spawning.water_ambient.min-failed':
      '最小失败次数',
  'leaf-global.yml.performance.throttle-mob-spawning.water_ambient.spawn-chance':
      '生成概率',
  'leaf-global.yml.performance.create-snapshot-on-retrieving-blockstate':
      '检索方块状态时创建快照',
  'leaf-global.yml.performance.use-virtual-thread': '使用虚拟线程',
  'leaf-global.yml.performance.use-virtual-thread.bukkit-async-scheduler':
      'Bukkit 异步调度器使用虚拟线程',
  'leaf-global.yml.performance.use-virtual-thread.folia-async-scheduler':
      'Folia 异步调度器使用虚拟线程',
  'leaf-global.yml.performance.use-virtual-thread.async-chat-executor':
      '异步聊天使用虚拟线程',
  'leaf-global.yml.performance.use-virtual-thread.download-pool': '下载池使用虚拟线程',
  'leaf-global.yml.performance.use-virtual-thread.auth-pool': '验证池使用虚拟线程',
  'leaf-global.yml.performance.use-virtual-thread.paper-configuration-pool':
      'Paper 配置池使用虚拟线程',

  // fixes 修复设置
  'leaf-global.yml.fixes': '修复设置',
  'leaf-global.yml.fixes.vanilla-bug-fix': '原版漏洞修复',
  'leaf-global.yml.fixes.vanilla-bug-fix.mc-270656': '修复 MC-270656（进度触发检查错误）',
  'leaf-global.yml.fixes.vanilla-bug-fix.mc-301114': '修复 MC-301114（战斗跟踪器内存泄漏）',
  'leaf-global.yml.fixes.vanilla-bug-fix.mc-301114-max-entries': '战斗跟踪器最大条目数',
  'leaf-global.yml.fixes.vanilla-bug-fix.mc-152094': '修复 MC-152094（末地船边缘截断）',
  'leaf-global.yml.fixes.prevent-moving-into-weak-loaded-chunks': '阻止实体进入弱加载区块',
  'leaf-global.yml.fixes.prevent-moving-into-weak-loaded-chunks.enabled':
      '是否启用',
  'leaf-global.yml.fixes.prevent-moving-into-weak-loaded-chunks.projectiles':
      '是否阻止投掷物进入',

  // gameplay-mechanisms 游戏机制
  'leaf-global.yml.gameplay-mechanisms': '游戏机制设置',
  'leaf-global.yml.gameplay-mechanisms.afk-command': 'AFK 命令设置',
  'leaf-global.yml.gameplay-mechanisms.afk-command.enabled': '是否启用 AFK 命令',
  'leaf-global.yml.gameplay-mechanisms.inventory-overflow-event': '物品栏溢出事件',
  'leaf-global.yml.gameplay-mechanisms.inventory-overflow-event.enabled':
      '是否启用物品栏溢出事件',
  'leaf-global.yml.gameplay-mechanisms.inventory-overflow-event.listener-class':
      '监听器类名',
  'leaf-global.yml.gameplay-mechanisms.player': '玩家设置',
  'leaf-global.yml.gameplay-mechanisms.player.max-use-item-distance':
      'UseItem 最大距离（-1=禁用检测）',
  'leaf-global.yml.gameplay-mechanisms.allow-tripwire-dupe': '是否允许绊线复制',
  'leaf-global.yml.gameplay-mechanisms.death-item-drop-knockback': '死亡物品掉落击退',
  'leaf-global.yml.gameplay-mechanisms.death-item-drop-knockback.drop-around':
      '物品是否随机掉落在周围',
  'leaf-global.yml.gameplay-mechanisms.death-item-drop-knockback.horizontal-force':
      '水平击退力',
  'leaf-global.yml.gameplay-mechanisms.death-item-drop-knockback.vertical-force':
      '垂直击退力',
  'leaf-global.yml.gameplay-mechanisms.ice-and-snow-chance': '冰雪生成概率',
  'leaf-global.yml.gameplay-mechanisms.knockback': '击退设置',
  'leaf-global.yml.gameplay-mechanisms.knockback.snowball-knockback-players':
      '雪球是否击退玩家',
  'leaf-global.yml.gameplay-mechanisms.knockback.egg-knockback-players':
      '鸡蛋是否击退玩家',
  'leaf-global.yml.gameplay-mechanisms.knockback.can-player-knockback-zombie':
      '玩家是否可击退僵尸',
  'leaf-global.yml.gameplay-mechanisms.knockback.flush-location-while-knockback-player':
      '击退时同步玩家位置',
  'leaf-global.yml.gameplay-mechanisms.knockback.old-blast-protection-explosion-knockback':
      '使用旧版爆炸保护击退',
  'leaf-global.yml.gameplay-mechanisms.only-player-pushable': '仅玩家可推动',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings': '刷怪笼设置',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.enabled':
      '是否启用自定义刷怪笼设置',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.checks': '生成检查',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.checks.light-level-check':
      '检查光照等级',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.checks.spawner-max-nearby-check':
      '检查附近怪物数量上限',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.checks.check-for-nearby-players':
      '检查附近玩家',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.checks.spawner-block-checks':
      '检查方块阻挡',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.checks.water-prevent-spawn-check':
      '检查水阻止生成',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.checks.ignore-spawn-rules':
      '忽略生物特定生成规则',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.min-spawn-delay':
      '最小生成延迟（Tick）',
  'leaf-global.yml.gameplay-mechanisms.spawner-settings.max-spawn-delay':
      '最大生成延迟（Tick）',
  'leaf-global.yml.gameplay-mechanisms.use-spigot-item-merging-mechanism':
      '使用 Spigot 物品合并机制',
  'leaf-global.yml.gameplay-mechanisms.use-vanilla-hopper': '使用原版漏斗',

  // network 网络设置
  'leaf-global.yml.network': '网络设置',
  'leaf-global.yml.network.async-switch-state': '异步切换连接状态',
  'leaf-global.yml.network.chat-message-signature': '是否启用聊天签名（禁用后无法举报）',
  'leaf-global.yml.network.OptimizeNonFlushPacketSending':
      '优化非刷新数据包发送（需重启，不兼容 ProtocolLib）',
  'leaf-global.yml.network.protocol-support': '协议支持设置',
  'leaf-global.yml.network.protocol-support.strict-mode': '严格模式',
  'leaf-global.yml.network.protocol-support.jade-protocol': 'Jade 协议',
  'leaf-global.yml.network.protocol-support.appleskin-protocol': 'AppleSkin 协议',
  'leaf-global.yml.network.protocol-support.appleskin-protocol-sync-tick-interval':
      'AppleSkin 同步间隔（Tick）',
  'leaf-global.yml.network.protocol-support.asteorbar-protocol': 'AsteorBar 协议',
  'leaf-global.yml.network.protocol-support.chatimage-protocol': 'ChatImage 协议',
  'leaf-global.yml.network.protocol-support.xaero-map-protocol': 'Xaero 地图协议',
  'leaf-global.yml.network.protocol-support.xaero-map-server-id':
      'Xaero 地图服务器 ID',
  'leaf-global.yml.network.protocol-support.syncmatica-protocol':
      'Syncmatica 协议',
  'leaf-global.yml.network.protocol-support.syncmatica-quota': 'Syncmatica 配额',
  'leaf-global.yml.network.protocol-support.syncmatica-quota-limit':
      'Syncmatica 配额上限',
  'leaf-global.yml.network.protocol-support.do-a-barrel-roll-protocol':
      'Do a Barrel Roll 协议',
  'leaf-global.yml.network.protocol-support.do-a-barrel-roll-allow-thrusting':
      '允许推进',
  'leaf-global.yml.network.protocol-support.do-a-barrel-roll-force-enabled':
      '强制启用',
  'leaf-global.yml.network.protocol-support.do-a-barrel-roll-force-installed':
      '强制安装',
  'leaf-global.yml.network.protocol-support.do-a-barrel-roll-installed-timeout':
      '安装超时',

  // misc 杂项设置
  'leaf-global.yml.misc': '杂项设置',
  'leaf-global.yml.misc.connection-message': '连接消息设置',
  'leaf-global.yml.misc.connection-message.join': '加入消息',
  'leaf-global.yml.misc.connection-message.join.enabled': '是否启用自定义加入消息',
  'leaf-global.yml.misc.connection-message.join.message':
      '加入消息（MiniMessage 格式，default=原版）',
  'leaf-global.yml.misc.connection-message.quit': '退出消息',
  'leaf-global.yml.misc.connection-message.quit.enabled': '是否启用自定义退出消息',
  'leaf-global.yml.misc.connection-message.quit.message':
      '退出消息（MiniMessage 格式，default=原版）',
  'leaf-global.yml.misc.disable-world-data-saving': '禁用世界数据保存',
  'leaf-global.yml.misc.disable-world-data-saving.worlds': '不保存的世界列表（仅内存）',
  'leaf-global.yml.misc.including-5s-in-get-tps': 'TPS 计算是否包含 5 秒数据',
  'leaf-global.yml.misc.lag-compensation': '滞后补偿',
  'leaf-global.yml.misc.lag-compensation.enabled': '是否启用滞后补偿',
  'leaf-global.yml.misc.lag-compensation.enable-for-water': '对水启用',
  'leaf-global.yml.misc.lag-compensation.enable-for-lava': '对岩浆启用',
  'leaf-global.yml.misc.region-format': '区域格式设置（Linear 压缩）',
  'leaf-global.yml.misc.region-format.format-name':
      '格式名（MCA/B_LINEAR/LINEAR_V2）',
  'leaf-global.yml.misc.region-format.compress-level': '压缩等级',
  'leaf-global.yml.misc.region-format.io-thread-count': 'IO 线程数',
  'leaf-global.yml.misc.region-format.io-flush-delay': 'IO 刷新延迟',
  'leaf-global.yml.misc.region-format.linear-use-virtual-thread':
      'Linear 使用虚拟线程',
  'leaf-global.yml.misc.remove-change-non-editable-sign-warning':
      '移除修改不可编辑告示牌的警告',
  'leaf-global.yml.misc.remove-spigot-check-bungee-config':
      '移除 Spigot Bungee 检查',
  'leaf-global.yml.misc.secure-seed': '安全种子',
  'leaf-global.yml.misc.secure-seed.enabled': '是否启用安全种子（1024 位，无法破解）',
  'leaf-global.yml.misc.sentry': 'Sentry 错误报告',
  'leaf-global.yml.misc.sentry.dsn': 'Sentry DSN（留空关闭）',
  'leaf-global.yml.misc.sentry.log-level': '记录的日志级别',
  'leaf-global.yml.misc.sentry.only-log-thrown': '仅记录带异常的日志',
  'leaf-global.yml.misc.rebrand': '服务器品牌',
  'leaf-global.yml.misc.rebrand.server-mod-name': '服务器模组名称',
  'leaf-global.yml.misc.rebrand.server-gui-name': '服务器 GUI 名称',
  'leaf-global.yml.misc.message': '消息设置',
  'leaf-global.yml.misc.message.unknown-command': '未知命令消息（MiniMessage 格式）',
  'leaf-global.yml.misc.vanilla-username-check': '原版用户名验证',
  'leaf-global.yml.misc.vanilla-username-check.remove-all-check': '移除所有验证（危险）',
  'leaf-global.yml.misc.vanilla-username-check.enforce-skull-validation':
      '强制头颅验证',
  'leaf-global.yml.misc.vanilla-username-check.allow-old-players-join':
      '允许老玩家加入（不满足新正则）',
  'leaf-global.yml.misc.vanilla-username-check.use-username-regex':
      '使用自定义用户名正则',
  'leaf-global.yml.misc.vanilla-username-check.username-regex': '用户名正则表达式',
};
