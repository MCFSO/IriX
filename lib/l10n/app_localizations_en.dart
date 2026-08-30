// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get common_save => 'Save';

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_delete => 'Delete';

  @override
  String get common_edit => 'Edit';

  @override
  String get common_refresh => 'Refresh';

  @override
  String get common_retry => 'Retry';

  @override
  String get common_confirm => 'Confirm';

  @override
  String get common_close => 'Close';

  @override
  String get common_add => 'Add';

  @override
  String get common_search => 'Search';

  @override
  String get common_name => 'Name';

  @override
  String get common_status => 'Status';

  @override
  String get common_action => 'Action';

  @override
  String get common_loading => 'Loading…';

  @override
  String get common_error => 'Error';

  @override
  String get common_success => 'Success';

  @override
  String get common_copy => 'Copy';

  @override
  String get common_remove => 'Remove';

  @override
  String get common_ok => 'OK';

  @override
  String get common_back => 'Back';

  @override
  String get common_reset => 'Reset';

  @override
  String get common_apply => 'Apply';

  @override
  String get common_confirmDelete => 'Confirm Delete';

  @override
  String get common_open => 'Open';

  @override
  String get common_enabled => 'Enabled';

  @override
  String get common_disabled => 'Disabled';

  @override
  String common_deleteItemConfirm(String name) {
    return 'Delete \"$name\"? This action cannot be undone.';
  }

  @override
  String common_itemCount(int count) {
    return '$count item';
  }

  @override
  String common_timeMinutesAgo(int minutes) {
    return '$minutes minute ago';
  }

  @override
  String common_timeHoursAgo(int hours) {
    return '$hours hour ago';
  }

  @override
  String common_timeDaysAgo(int days) {
    return '$days day ago';
  }

  @override
  String common_timeMonthsAgo(int months) {
    return '$months month ago';
  }

  @override
  String common_timeYearsAgo(int years) {
    return '$years year ago';
  }

  @override
  String get common_language => 'Language';

  @override
  String get common_languageSystem => 'System';

  @override
  String get common_languageChinese => '简体中文';

  @override
  String get common_languageEnglish => 'English';

  @override
  String get settings_title => 'Settings';

  @override
  String get settings_multiMode => 'Multi-node management';

  @override
  String get settings_multiModeOn =>
      'Instances are distributed across multiple nodes with automatic resource allocation, crash migration and data sync.';

  @override
  String get settings_singleMode =>
      'Single mode: instances run on this machine';

  @override
  String get settings_multiModeHint =>
      'Multi-node mode requires at least 2 nodes, which can be added on the Home page.';

  @override
  String get settings_vault => 'Vault encrypted storage';

  @override
  String get settings_vaultOn =>
      'Enabled: node detail / unlock / initialize / certificate binding vault capabilities are available';

  @override
  String get settings_vaultOff =>
      'Off: vault capabilities are hidden (node must run with -vault and configure TLS)';

  @override
  String get settings_developer => 'Developer mode';

  @override
  String get settings_developerOn =>
      'On: records app runtime, operations, network and crash logs to the program directory logs/';

  @override
  String get settings_developerOff => 'Off: developer logs are not recorded';

  @override
  String get settings_developerHint =>
      'When enabled, everything (runtime logs, operation traces, network request details, startup and crash stacks) is written to a session log file under the program directory logs/, to help troubleshoot issues.';

  @override
  String settings_downloadThreads(int count) {
    return 'Download threads: $count';
  }

  @override
  String get settings_downloadThreadsHint =>
      'Multi-threaded chunked resume; falls back to single thread when the server does not support Range.';

  @override
  String settings_dbPageSize(int count) {
    return 'Database rows per page: $count';
  }

  @override
  String get settings_dbPageSizeHint =>
      'Rows shown per page when browsing database tables.';

  @override
  String get settings_font => 'Font';

  @override
  String get settings_fontHint =>
      'Terminal (console / log / code) font is configured separately from the rest of the UI; the rest defaults to MiSans, terminal defaults to JetBrains Mono.';

  @override
  String get settings_uiFont => 'UI font';

  @override
  String get settings_terminalFont => 'Terminal font';

  @override
  String get settings_fontFallbackHint =>
      'System fonts that are not installed (e.g. JetBrains Mono) fall back to the default font automatically.';

  @override
  String get node_renameTitle => 'Rename node';

  @override
  String get node_nameHint => 'Node name';

  @override
  String node_deleteConfirmTitle(String name) {
    return 'Delete node \"$name\"?';
  }

  @override
  String get node_deleteConfirmContent =>
      'Only the locally saved node info is removed; data on the server is not affected.';

  @override
  String get node_online => 'Online';

  @override
  String get node_offline => 'Offline';

  @override
  String get node_renameMenu => 'Rename';

  @override
  String get node_deleteMenu => 'Delete';

  @override
  String get container_tabContainers => 'Containers';

  @override
  String get container_tabRelease => 'Release';

  @override
  String get container_tabForward => 'Forward';

  @override
  String get container_tabSettings => 'Settings';

  @override
  String get container_tabImages => 'Images';

  @override
  String get container_tabVolumes => 'Volumes';

  @override
  String get container_tabNetworks => 'Networks';

  @override
  String get container_jailList => 'Jail list';

  @override
  String get container_containerList => 'Container list';

  @override
  String get container_import => 'Import';

  @override
  String get container_createJail => 'Create Jail';

  @override
  String get container_createContainer => 'Create container';

  @override
  String get container_noJails => 'No jails';

  @override
  String get container_noContainers => 'No containers';

  @override
  String get container_bootstrappedReleases => 'Bootstrapped releases';

  @override
  String get container_imageList => 'Image list';

  @override
  String get container_bootstrap => 'Bootstrap';

  @override
  String get container_pull => 'Pull';

  @override
  String get container_build => 'Build';

  @override
  String get container_noReleases =>
      'No releases yet. Click Bootstrap to pull (e.g. 14.2-RELEASE).';

  @override
  String get container_noImages => 'No images';

  @override
  String get container_deleteImage => 'Delete image';

  @override
  String get container_bootstrapRelease => 'Bootstrap release';

  @override
  String get container_pullImage => 'Pull image';

  @override
  String get container_releaseName => 'Release name';

  @override
  String get container_imageName => 'Image name';

  @override
  String get container_releaseNameHint => 'e.g. 14.2-RELEASE';

  @override
  String get container_imageNameHint => 'e.g. itzg/minecraft-server:latest';

  @override
  String get container_rdrRules => 'Port forwarding rules (bastille rdr)';

  @override
  String get container_addForward => 'Add forward';

  @override
  String get container_noRdrRules => 'No forwarding rules';

  @override
  String get container_deleteForward => 'Delete forward';

  @override
  String get container_forwardDeleted => 'Forwarding rule deleted';

  @override
  String get container_forwardAdded => 'Forwarding rule added';

  @override
  String get container_deleteVolume => 'Delete volume';

  @override
  String get container_volumeList => 'Volume list';

  @override
  String get container_networkList => 'Network list';

  @override
  String get container_noVolumes => 'No volumes';

  @override
  String get container_noNetworks => 'No networks';

  @override
  String get container_start => 'Start';

  @override
  String get container_stop => 'Stop';

  @override
  String get container_manageDetail => 'Manage (details)';

  @override
  String get container_moreActions => 'More actions';

  @override
  String get container_restart => 'Restart';

  @override
  String get container_clone => 'Clone';

  @override
  String get container_resourceLimit => 'Resource limit';

  @override
  String get container_exportArchive => 'Export archive';

  @override
  String get container_status => 'Status';

  @override
  String get container_image => 'Image';

  @override
  String get container_ports => 'Ports';

  @override
  String get container_createdAt => 'Created at';

  @override
  String get container_confirmOperation => 'Confirm operation';

  @override
  String get container_exportSavedPath =>
      'Archive saved to the following path on the node:';

  @override
  String get container_redetect => 'Re-detect';

  @override
  String get container_envUnavailableBastille =>
      'Bastille runs on FreeBSD nodes. Add an online FreeBSD node (irix-node) in Node Management, then manage jails from the instance detail page\'s Containers tab.';

  @override
  String get container_envUnavailableDocker =>
      'This machine uses Docker. Install and start Docker Desktop (or the docker CLI), then click Re-detect to enable all container features.';

  @override
  String get container_nameHelperBastille =>
      'Letters, digits, - and _ only; cannot be purely numeric.';

  @override
  String get container_release => 'Release';

  @override
  String get container_imageHelper => 'e.g. itzg/minecraft-server:latest';

  @override
  String get container_releaseHelper => 'e.g. 14.2-RELEASE (Bootstrap first)';

  @override
  String get container_ipAddress => 'IP address';

  @override
  String get container_ipHelper => 'Include prefix, e.g. 192.168.1.50/24';

  @override
  String get container_jailType => 'Jail type';

  @override
  String get container_jailTypeThin => 'thin — symlinked template (default)';

  @override
  String get container_jailTypeThick =>
      'thick — thick container (-T extracts template)';

  @override
  String get container_jailTypeClone => 'clone — clone existing release';

  @override
  String get container_jailTypeEmpty =>
      'empty — empty container (-E, name only)';

  @override
  String get container_jailTypeLinux => 'linux — Linux Jail (-L)';

  @override
  String get container_vnetMode => 'VNET mode';

  @override
  String get container_vnetModeNone => 'No VNET (shared host network)';

  @override
  String get container_vnetModeVnet => 'VNET (-V, NIC must be physical)';

  @override
  String get container_vnetModeBridge =>
      'Bridged VNET (-B, NIC must be bridge)';

  @override
  String get container_bridgeNic => 'Bridge NIC';

  @override
  String get container_physicalNic => 'Physical NIC';

  @override
  String get container_bridgeNicHint => 'e.g. bridge0';

  @override
  String get container_physicalNicHint => 'e.g. em0';

  @override
  String get container_portMapping => 'Port mapping';

  @override
  String get container_portMappingHelper =>
      'Host port:container port, comma-separated';

  @override
  String get container_portMappingHelperBastille =>
      'Host port:jail port, comma-separated; applied via rdr after creation';

  @override
  String get container_dataMount => 'Data directory mount (nullfs)';

  @override
  String get container_volumeMount => 'Volume mount';

  @override
  String get container_dataMountHelper =>
      'Host path:jail path, comma-separated';

  @override
  String get container_volumeMountHelper =>
      'Host path:container path, comma-separated';

  @override
  String get container_envVars => 'Environment variables';

  @override
  String get container_envVarsHelper =>
      'One KEY=VALUE per line, e.g. MEMORY=2G, EULA=TRUE';

  @override
  String get container_restartPolicy => 'Restart policy';

  @override
  String get container_restartNo => 'no — do not auto-restart';

  @override
  String get container_restartUnlessStopped =>
      'unless-stopped — restart on exit';

  @override
  String get container_restartAlways => 'always — always restart';

  @override
  String get container_restartOnFailure =>
      'on-failure — restart on abnormal exit';

  @override
  String get container_startCommand =>
      'Start command (blank uses image default)';

  @override
  String get container_workdir => 'Working directory (blank for default)';

  @override
  String get container_workdirHelper =>
      'e.g. /data — force start inside mounted data directory';

  @override
  String get container_memoryLimit => 'Memory limit (MB, blank for unlimited)';

  @override
  String get container_cpuCores => 'CPU cores (blank for unlimited)';

  @override
  String get container_diskLimit => 'Disk limit (MB, blank for unlimited)';

  @override
  String get container_diskLimitHelper =>
      'Depends on storage driver size quota support';

  @override
  String get container_diskLimitHelperBastille => 'ZFS dataset quota';

  @override
  String get container_createHintBastille =>
      'Hint: thin (default) / thick (-T) / clone (-C) / empty (-E, name only) / linux (-L) are mutually exclusive creation methods; Linux Jail cannot be used with VNET (-V/-B); VNET requires network setup in the Settings page first, and the IP must include a subnet mask.';

  @override
  String get container_enterJailName => 'Enter jail name';

  @override
  String get container_nameAndImageRequired =>
      'Name and image / release cannot be empty';

  @override
  String get container_jailNameRule =>
      'Jail name allows only letters, digits, - and _; cannot be purely numeric';

  @override
  String get container_jailIpRequired =>
      'Bastille jail creation requires an explicit IP address';

  @override
  String get container_linuxVnetConflict =>
      'Linux Jail (-L) cannot be used with VNET (-V/-B)';

  @override
  String get container_enterBridgeNic => 'Enter bridge NIC name';

  @override
  String get container_enterPhysicalNic => 'Enter physical NIC name';

  @override
  String get container_vnetIpMustContainMask =>
      'VNET jail IP must include a subnet mask, e.g. 192.168.1.50/24';

  @override
  String get container_newName => 'New name';

  @override
  String get container_notPureNumber => 'Cannot be purely numeric';

  @override
  String get container_newIp =>
      'New IP address (blank to keep source, must include prefix)';

  @override
  String get container_newIpHint => 'e.g. 192.168.1.51/24';

  @override
  String get container_resourceLimits => 'Resource limits';

  @override
  String get container_memoryLimitKeep => 'Memory limit (MB, blank to keep)';

  @override
  String get container_cpuCoresKeep => 'CPU cores (blank to keep)';

  @override
  String get container_diskLimitKeep => 'Disk limit (MB, blank to keep)';

  @override
  String get container_diskLimitKeepHelper =>
      'Docker does not support hot-updating disk limit';

  @override
  String get container_jail => 'Jail';

  @override
  String get container_protocol => 'Protocol';

  @override
  String get container_hostPort => 'Host port';

  @override
  String get container_jailPort => 'Jail port';

  @override
  String get container_archivePath => 'Archive path (archive file on the node)';

  @override
  String get container_archivePathHint =>
      'e.g. /usr/local/bastille/backups/xxx.txz';

  @override
  String get container_specifyRelease =>
      'Specify release (blank uses archive name)';

  @override
  String get container_specifyReleaseHint => 'e.g. 14.2-RELEASE';

  @override
  String get container_skipChecksum =>
      'Skip checksum verification (-f / --force)';

  @override
  String get container_importJail => 'Import Jail';

  @override
  String get container_setupDefaultTitle => 'One-click default init';

  @override
  String get container_setupDefaultDesc =>
      'Runs bastille setup with no options: auto-configures loopback (bastille0), firewall and storage. Sufficient for most cases.';

  @override
  String get container_setupDefaultRun => 'Run bastille setup';

  @override
  String get container_setupFirewallTitle => 'Firewall (firewall)';

  @override
  String get container_setupFirewallDesc =>
      'Configures the PF firewall: enables the service and generates a default pf.conf — a prerequisite for port forwarding (bastille rdr).';

  @override
  String get container_setupFirewallRun => 'Run bastille setup firewall';

  @override
  String get container_setupVnetTitle => 'VNET network (vnet)';

  @override
  String get container_setupVnetDesc =>
      'Configures the host network for VNET jails (-V). Parameters are optional (some versions are interactive and injected by the server).';

  @override
  String get container_setupVnetRun => 'Run bastille setup vnet';

  @override
  String get container_setupBridgeTitle => 'Bridged network (bridge)';

  @override
  String get container_setupBridgeDesc =>
      'Configures the bridge NIC — a prerequisite for bridged VNET jails (-B). You must create a bridge interface on the system first (e.g. ifconfig bridge create).';

  @override
  String get container_setupBridgeRun => 'Run bastille setup bridge';

  @override
  String get container_setupSharedTitle => 'Shared NIC (shared)';

  @override
  String get container_setupSharedDesc =>
      'Sets the specified NIC as the shared interface: used by default when create specifies no INTERFACE. Mutually exclusive with loopback (configuring one disables the other).';

  @override
  String get container_setupSharedRun => 'Run bastille setup shared';

  @override
  String get container_setupLinuxTitle => 'Linux Jail (linux)';

  @override
  String get container_setupLinuxDesc =>
      'Initializes Linuxulator — a prerequisite for creating Linux jails (-L): loads required kernel modules and installs the debootstrap package.';

  @override
  String get container_setupLinuxRun => 'Run bastille setup linux';

  @override
  String get container_setupFieldExtIf => 'External NIC';

  @override
  String get container_setupFieldExtIfHint => 'e.g. em0';

  @override
  String get container_setupFieldTunIf => 'Bridge NIC';

  @override
  String get container_setupFieldTunIfHint => 'default bastille0';

  @override
  String get container_setupFieldAddr => 'Subnet';

  @override
  String get container_setupFieldAddrHint => 'e.g. 10.99.0.0/24';

  @override
  String get container_setupFieldNic => 'NIC';

  @override
  String get container_enterNicName => 'Enter NIC name';

  @override
  String get container_initDone => 'Initialization complete';

  @override
  String get container_initFailed => 'Initialization failed';

  @override
  String get container_buildImage => 'Build image';

  @override
  String get container_tag => 'Tag';

  @override
  String get container_dockerfile => 'Dockerfile';

  @override
  String get container_buildContextNote =>
      'Build context is stdin (consistent with MCSM dockerFile); when COPY of local files is needed, place them in the image base layer.';

  @override
  String get container_startBuild => 'Start build';

  @override
  String get container_buildDone => 'Build complete';

  @override
  String get container_buildFailed => 'Build failed';

  @override
  String get container_building => 'Building...';

  @override
  String get container_waitingBuildOutput => 'Waiting for build output...';

  @override
  String get container_buildInBackground => 'Build in background';

  @override
  String container_operationSuccess(String name) {
    return 'Operation succeeded: $name';
  }

  @override
  String container_created(String name) {
    return 'Created: $name';
  }

  @override
  String container_cloned(String name) {
    return 'Cloned as: $name';
  }

  @override
  String container_limitsUpdated(String name) {
    return 'Resource limits updated: $name';
  }

  @override
  String container_exportDone(String name) {
    return 'Export complete: $name';
  }

  @override
  String container_importDone(String name) {
    return 'Import complete: $name';
  }

  @override
  String container_buildTitle(String imageName) {
    return 'Build $imageName';
  }

  @override
  String container_envUnavailable(String name) {
    return '$name unavailable';
  }

  @override
  String container_envLabel(String name) {
    return '$name environment';
  }

  @override
  String container_deleteConfirmContainer(String name) {
    return 'Delete container $name?';
  }

  @override
  String container_deleteConfirmJail(String name) {
    return 'Delete Jail $name?';
  }

  @override
  String container_deleteVolumeConfirm(String name) {
    return 'Delete volume $name?';
  }

  @override
  String container_bootstrapSubmitted(String name) {
    return 'Bootstrap task submitted: $name (runs in background; refresh the list later)';
  }

  @override
  String container_pullDone(String name) {
    return 'Image pulled: $name';
  }

  @override
  String container_cloneTitle(String source) {
    return 'Clone $source';
  }

  @override
  String container_portFormatError(String port) {
    return 'Invalid port format: $port (should be host:container port)';
  }

  @override
  String container_deleteImageConfirm(String tag) {
    return 'Delete image $tag?';
  }

  @override
  String container_rdrSubtitle(String proto, int hostPort, int containerPort) {
    return '$proto  host $hostPort -> jail $containerPort';
  }

  @override
  String container_deleteForwardConfirm(
    String container,
    String proto,
    int hostPort,
    int containerPort,
  ) {
    return 'Delete $container\'s $proto $hostPort->$containerPort?';
  }

  @override
  String get addNode_title => 'Add Node';

  @override
  String get addNode_fillAddressFirst => 'Please enter the address first';

  @override
  String get addNode_connectSuccess => 'Connection successful';

  @override
  String get addNode_connectFailed =>
      'Connection failed; check the address and API Key';

  @override
  String get addNode_fillNodeAddress => 'Please enter the node address';

  @override
  String get addNode_mcsmApiKeyRequired => 'MCSM nodes require an API Key';

  @override
  String get addNode_remoteNodeKeyRequired =>
      'Remote Node requires a key (only the local loopback address may be left blank)';

  @override
  String get addNode_plaintextWarningTitle => 'Plaintext connection warning';

  @override
  String get addNode_plaintextWarningContent =>
      'This node address uses plaintext HTTP (not https); your API key and all control traffic (including file read/write and command execution) can be eavesdropped or tampered with on the same network.';

  @override
  String get addNode_continueAnyway => 'Continue anyway';

  @override
  String get addNode_cancelledEnableHttps =>
      'Cancelled: please enable HTTPS for the node';

  @override
  String get addNode_prevStep => 'Previous step';

  @override
  String get addNode_nextStep => 'Next step';

  @override
  String get addNode_testConnection => 'Test connection';

  @override
  String get addNode_finish => 'Finish';

  @override
  String get addNode_stepType => 'Type';

  @override
  String get addNode_stepName => 'Name';

  @override
  String get addNode_stepKey => 'Key';

  @override
  String get addNode_selectType => 'Select node type';

  @override
  String get addNode_mcsmSubtitle =>
      'Connect to a remote MCSManager panel\nRequires the panel API Key';

  @override
  String get addNode_nodeSubtitle =>
      'IriX local Go-language node\nLocal loopback can skip the key; remote nodes require a key';

  @override
  String get addNode_nameHint => 'e.g. My Panel / Local Node';

  @override
  String get addNode_address => 'Node address';

  @override
  String get addNode_mcsmAddressHelper =>
      'MCSManager panel address (with port, e.g. 23333); https is recommended for remote';

  @override
  String get addNode_nodeAddressHelper =>
      'Local node daemon address (default port 12346)';

  @override
  String get addNode_keyTitle => 'Node Key / API Key';

  @override
  String get addNode_mcsmKeyHint => 'MCSManager user API Key';

  @override
  String get addNode_nodeKeyHint =>
      'Local node key (may be left blank for local loopback)';

  @override
  String get addNode_copiedApiKey => 'API Key copied';

  @override
  String get addNode_show => 'Show';

  @override
  String get addNode_hide => 'Hide';

  @override
  String get addNode_mcsmKeyHelper =>
      'Generate and copy it in the MCSManager panel \"User Info\"';

  @override
  String get addNode_nodeKeyHelper =>
      'Remote nodes must provide a key; only the 127.0.0.1 local loopback may be left blank';

  @override
  String get wizard_title => 'First-time setup guide';

  @override
  String get wizard_detectingNat => 'Detecting NAT type...';

  @override
  String get wizard_jdk8Note => 'Minecraft 1.16.5 and earlier';

  @override
  String get wizard_jdk17Note => 'Minecraft 1.18+ (officially recommended)';

  @override
  String get wizard_jdk21Note => 'Minecraft 1.20.5+ (recommended)';

  @override
  String get wizard_jdk25Note => 'Latest LTS (new server versions)';

  @override
  String get wizard_skipThisStep => 'Skip this step';

  @override
  String get wizard_skipHint =>
      'Tip: you can click \"Skip\" in the top-left corner at any time to exit the guide.';

  @override
  String get wizard_stepCreateInstance => 'Step 5 · Create the first instance';

  @override
  String get wizard_createInstanceDesc =>
      'Download or import a server core to create your first Minecraft server instance.\nAfter completion, the network environment (NAT type) will be detected automatically and an intranet penetration suggestion will be given.';

  @override
  String get wizard_createFirstInstance => 'Create the first instance';

  @override
  String get wizard_noInstanceCreated =>
      'No instance created yet; please finish creating an instance first';

  @override
  String get wizard_done => 'Setup complete!';

  @override
  String get wizard_natUncertain => '(result uncertain)';

  @override
  String get wizard_frpNeeded =>
      'Your network is behind NAT; friends may not be able to connect directly.\nWould you like to configure FRP intranet penetration so external players can join?';

  @override
  String get wizard_frpNotNeeded =>
      'Your network is directly reachable on the public internet; players can connect via your public IP directly, no penetration needed.';

  @override
  String get wizard_configureFrp => 'Yes, configure FRP';

  @override
  String get wizard_notNow => 'Not now';

  @override
  String get wizard_adoptiumSource =>
      'From Adoptium (Eclipse Temurin), about 200MB download';

  @override
  String get wizard_unknownError => 'Unknown error';

  @override
  String get common_skip => 'Skip';

  @override
  String wizard_totalSteps(int count) {
    return '$count steps total; complete them in order';
  }

  @override
  String wizard_installJdk(String name) {
    return 'Install $name';
  }

  @override
  String wizard_stepInstallJdk(int step, String name) {
    return 'Step $step · Install $name';
  }

  @override
  String wizard_startInstall(String name) {
    return 'Start installing $name';
  }

  @override
  String wizard_downloading(String name, String percent) {
    return 'Downloading $name ... $percent%';
  }

  @override
  String wizard_jdkInstalled(String name) {
    return '$name installed';
  }

  @override
  String wizard_installFailed(String error) {
    return 'Installation failed: $error';
  }

  @override
  String wizard_natType(String label) {
    return 'NAT type: $label';
  }

  @override
  String wizard_natMapped(String addr) {
    return '($addr)';
  }

  @override
  String wizard_stepNumber(int index, String title) {
    return '$index. $title';
  }

  @override
  String get ai_stop => 'Stop';

  @override
  String get ai_clearConversation => 'Clear conversation';

  @override
  String get ai_modelMcpSettings => 'Model & MCP settings';

  @override
  String get ai_closePanel => 'Close AI panel';

  @override
  String get ai_addModel => 'Add model';

  @override
  String get ai_startChat => 'Start chatting with the AI';

  @override
  String get ai_addModelFirst => 'Add a model first';

  @override
  String get ai_emptyHintHasModel =>
      'The AI can view logs, analyze errors, and manage files';

  @override
  String get ai_emptyHintNoModel =>
      'Configure an OpenAI-compatible API model (DeepSeek / OpenAI / Ollama, etc.) to get started';

  @override
  String get ai_thinking => 'AI is thinking…';

  @override
  String get ai_compressingHistory =>
      'Conversation history is long; compressing…';

  @override
  String get ai_requestSensitiveOp =>
      'The AI requests to perform a sensitive operation';

  @override
  String get ai_deny => 'Deny';

  @override
  String get ai_allow => 'Allow';

  @override
  String get ai_viewLog => 'View logs';

  @override
  String get ai_viewLogHint =>
      'Pick a log from the instance\'s logs/ folder; it will be parsed and sent to the AI for analysis';

  @override
  String get ai_pickLogFileTooltip =>
      'Select a log file (.log / .log.gz); it will be parsed and sent to the AI';

  @override
  String get ai_askHint => 'Ask the AI…';

  @override
  String get ai_addModelToChat => 'Add a model first to start chatting';

  @override
  String get ai_title => 'AI Assistant';

  @override
  String get ai_milvusSaved => 'Milvus connection saved';

  @override
  String get ai_configMilvusFirst =>
      'Configure the Milvus connection above before importing the knowledge base';

  @override
  String get ai_addModelForEmbedding =>
      'Add an AI model first; importing the knowledge base requires calling the Embedding API';

  @override
  String get ai_knowledgeImported => 'Knowledge base import complete';

  @override
  String get ai_deleteDocumentTitle => 'Delete document';

  @override
  String get ai_settingsTitle => 'AI Settings';

  @override
  String get ai_models => 'Models';

  @override
  String get ai_noModelsYet =>
      'No models yet. Tap \"Add model\" in the top-right corner';

  @override
  String get ai_knowledgeBase => 'Knowledge base';

  @override
  String get ai_importing => 'Importing…';

  @override
  String get ai_importDoc => 'Import document';

  @override
  String get ai_milvusConnection => 'Vector store (Milvus) connection';

  @override
  String get ai_milvusAddress => 'Milvus address';

  @override
  String get ai_milvusToken => 'Token (optional)';

  @override
  String get ai_milvusCollection => 'Collection name';

  @override
  String get ai_saving => 'Saving…';

  @override
  String get ai_saveConnection => 'Save connection';

  @override
  String get ai_milvusNotConfigured =>
      'Milvus connection not configured; save it before importing or searching the knowledge base';

  @override
  String get ai_knowledgeEmpty =>
      'The knowledge base is empty. After importing .txt/.md documents, the AI can search the knowledge base during conversations.\n(You need to configure an Embedding model in the model settings, or leave it empty to use a model with the same name)';

  @override
  String get ai_localMcpServer => 'Local MCP server';

  @override
  String get ai_port => 'Port';

  @override
  String get ai_mcpNotRunning => 'Not running';

  @override
  String get ai_copyEndpoint => 'Copy endpoint';

  @override
  String get ai_mcpConfigNote =>
      'Configure it in tools like Claude Desktop / Cursor (auth is enabled; the token is randomly generated on each startup):';

  @override
  String get ai_mcpConfigNoteTail =>
      'Tap the copy button to copy the full configuration.';

  @override
  String get ai_selectLogFile => 'Select log file (logs/)';

  @override
  String get ai_noLogFiles => 'No .log / .log.gz files in the logs/ folder';

  @override
  String get ai_send => 'Send';

  @override
  String get ai_deleteModelTitle => 'Delete model';

  @override
  String get ai_mcpConfigCopied =>
      'Copied the full MCP configuration (including the auth token)';

  @override
  String get ai_milvusTokenHint => 'Leave empty if auth is not enabled';

  @override
  String get frp_title => 'FRP Port Mapping';

  @override
  String get frp_logoutTitle => 'Log out';

  @override
  String get frp_logoutConfirm => 'Are you sure you want to log out?';

  @override
  String get frp_logout => 'Log out';

  @override
  String get frp_tunnelCreated => 'Tunnel created successfully';

  @override
  String get frp_addTunnel => 'Add tunnel';

  @override
  String get frp_openfrpDisclaimer =>
      'This project is community-developed; OpenFrp officially provides no support except for node-related issues';

  @override
  String get frp_log => 'Logs';

  @override
  String get frp_clearMemoryLog => 'Clear in-memory logs';

  @override
  String get frp_noLogYet =>
      'No logs yet\n\nTap a tunnel card on the left to view its logs';

  @override
  String get frp_portMapping => 'Port mapping';

  @override
  String get frp_loginPromptCustom =>
      'Configure your frps server address and auth token.\nTunnels are saved locally; launch frpc with one click for intranet penetration';

  @override
  String get frp_loginPromptChml =>
      'After logging into your ChmlFrp account, you can create port mappings (tunnels) for your server,\nand start frpc with one click in IriX for intranet penetration';

  @override
  String get frp_loginPromptOpen =>
      'After logging into OpenFrp, you can create port mappings (tunnels) for your server,\nand start frpc with one click in IriX for intranet penetration';

  @override
  String get frp_configFrps => 'Configure frps';

  @override
  String get frp_login => 'Log in';

  @override
  String get frp_noAccountRegister => 'No account yet? Register';

  @override
  String get frp_traffic => 'Remaining traffic';

  @override
  String get frp_tunnels => 'Tunnels';

  @override
  String get frp_status => 'Status';

  @override
  String get frp_noTunnelsYet => 'No tunnels yet';

  @override
  String get frp_addTunnelHint =>
      'Tap \"Add tunnel\" in the top-right corner to create a port mapping';

  @override
  String get frp_online => 'Online';

  @override
  String get frp_connecting => 'Connecting';

  @override
  String get frp_offline => 'Offline';

  @override
  String get frp_start => 'Start';

  @override
  String get frp_stop => 'Stop';

  @override
  String get frp_encrypt => 'Encrypt';

  @override
  String get frp_compress => 'Compress';

  @override
  String get frp_disabledLabel => 'Disabled';

  @override
  String get frp_requestingAuth => 'Requesting authorization…';

  @override
  String get frp_cannotOpenBrowser => 'Unable to open browser; please retry';

  @override
  String get frp_authorizedDecrypting => 'Authorized; decrypting…';

  @override
  String get frp_waitingBrowserAuth => 'Waiting for browser authorization…';

  @override
  String get frp_authTimeout => 'Authorization timed out; please retry';

  @override
  String get frp_loginOpenFrpTitle => 'Log in to OpenFrp';

  @override
  String get frp_openfrpAuthDesc =>
      'After tapping the button below, the OpenFrp authorization page will open in your browser:\nLog in and confirm on the authorization page; IriX will complete the login automatically with nothing to copy.\nPolling lasts up to 5 minutes; if it times out or is canceled, you must start over';

  @override
  String get frp_authorizeInBrowser => 'Authorize in browser';

  @override
  String get frp_enterServerAddress => 'Please enter the server address';

  @override
  String get frp_configSelfHosted => 'Configure self-hosted frps';

  @override
  String get frp_serverAddress => 'Server address';

  @override
  String get frp_authToken => 'Auth token';

  @override
  String get frp_authTokenHint =>
      'auth.token from the frps config (can be empty)';

  @override
  String get frp_selfHostedHint =>
      'Tunnels are saved locally; on startup, frpc TOML config is generated and run';

  @override
  String get frp_authCallbackTimeout =>
      'Timed out or canceled while waiting for web authorization';

  @override
  String get frp_noAccessToken =>
      'No access_token received in the authorization callback; please retry';

  @override
  String get frp_loginChmlFrpTitle => 'Log in to ChmlFrp';

  @override
  String get frp_chmlfrpAuthDesc =>
      'After tapping the button below, the ChmlFrp authorization page will open in your browser:\nAfter logging in and authorizing, it will automatically return to IriX with nothing to copy or paste';

  @override
  String get frp_chmlfrpNoRegister =>
      'IriX does not provide ChmlFrp account registration; please register on the official website, then log in';

  @override
  String get frp_loginSakuraFrpTitle => 'Log in to SakuraFrp';

  @override
  String get frp_accessToken => 'Access Token';

  @override
  String get frp_accessTokenHint => 'Paste your SakuraFrp access token';

  @override
  String get frp_show => 'Show';

  @override
  String get frp_hide => 'Hide';

  @override
  String get frp_sakurafrpTokenHint =>
      'How to get it: open the SakuraFrp console → Account info → Access Token, copy it, then paste it here';

  @override
  String get frp_loginHayFrpTitle => 'Log in to HayFrp';

  @override
  String get frp_usernameOrEmail => 'Username or email';

  @override
  String get frp_password => 'Password';

  @override
  String get frp_hayfrpTokenHint =>
      'The token obtained from login is valid for 7 days; each login invalidates the previous token';

  @override
  String get frp_tunnelNameRule =>
      'Tunnel names only support English letters, digits, - and _';

  @override
  String get frp_selectNode => 'Please select a node';

  @override
  String get frp_enterLocalAddr => 'Please enter the local address';

  @override
  String get frp_localPortRange => 'Local port must be between 1 and 65535';

  @override
  String get frp_webNeedsDomain => 'HTTP/HTTPS tunnels require a bound domain';

  @override
  String get frp_remotePortRange => 'Remote port must be between 1 and 65535';

  @override
  String get frp_tunnelName => 'Tunnel name';

  @override
  String get frp_tunnelNameHint => 'e.g. my_server (Chinese not supported)';

  @override
  String get frp_tunnelType => 'Tunnel type';

  @override
  String get frp_localAddress => 'Local address';

  @override
  String get frp_selectInstance => 'Select instance';

  @override
  String get frp_manualInput => 'Manual input';

  @override
  String get frp_localPort => 'Local port';

  @override
  String get frp_localPortExample => 'e.g. 25565';

  @override
  String get frp_localPortAuto => 'Local port (auto-read)';

  @override
  String get frp_remotePortHint => 'Port exposed to the outside';

  @override
  String get frp_bindDomain => 'Bound domain';

  @override
  String get frp_noAvailableNodes => 'No available nodes';

  @override
  String get frp_node => 'Node';

  @override
  String get frp_noAvailableInstances =>
      'No available instances (server.properties must exist to auto-read the port)';

  @override
  String get frp_instanceAutoPort => 'Instance (auto-read server-port)';

  @override
  String get frp_create => 'Create';

  @override
  String get frp_cannotOpenRegisterPage =>
      'Unable to open the registration page';

  @override
  String get frp_deleteTunnelTitle => 'Delete tunnel';

  @override
  String get frp_enterAccessToken => 'Please enter the access token';

  @override
  String get frp_enterUsernamePassword =>
      'Please enter your username and password';

  @override
  String ai_logParseFailed(String e) {
    return 'Failed to parse log: $e';
  }

  @override
  String ai_compressedHistory(String summary) {
    return 'Compressed conversation history: $summary';
  }

  @override
  String ai_saveFailed(String e) {
    return 'Failed to save: $e';
  }

  @override
  String ai_readFileFailed(String e) {
    return 'Failed to read file: $e';
  }

  @override
  String ai_importFailed(String e) {
    return 'Failed to import: $e';
  }

  @override
  String ai_deleteDocumentConfirm(String title) {
    return 'Delete \"$title\" from the knowledge base?';
  }

  @override
  String ai_deleteFailed(String e) {
    return 'Failed to delete: $e';
  }

  @override
  String ai_deleteModelConfirm(String name) {
    return 'Delete the model \"$name\"?';
  }

  @override
  String ai_mcpStartFailed(String e) {
    return 'Failed to start MCP server: $e';
  }

  @override
  String ai_modelSubtitle(String baseUrl, int contextWindow) {
    return '$baseUrl\nContext window: $contextWindow tokens';
  }

  @override
  String ai_milvusConfigured(String uri) {
    return 'Milvus connection configured: $uri';
  }

  @override
  String ai_docSubtitle(int chunkCount, String createdAt) {
    return '$chunkCount chunks · $createdAt';
  }

  @override
  String ai_mcpRunning(String endpoint) {
    return 'Running: $endpoint';
  }

  @override
  String frp_loginFailed(String e) {
    return 'Login failed: $e';
  }

  @override
  String frp_createFailed(String e) {
    return 'Failed to create: $e';
  }

  @override
  String frp_deleteFailed(String e) {
    return 'Failed to delete: $e';
  }

  @override
  String frp_startFailed(String e) {
    return 'Failed to start: $e';
  }

  @override
  String frp_deleteTunnelConfirm(String name) {
    return 'Delete the tunnel \"$name\"?';
  }

  @override
  String frp_deleted(String name) {
    return 'Deleted $name';
  }

  @override
  String frp_domainLabel(String domain) {
    return 'Domain: $domain';
  }

  @override
  String frp_remotePort(String port) {
    return 'Remote port $port';
  }

  @override
  String frp_localMapping(String localAddr, int localPort, String remoteText) {
    return 'Local $localAddr:$localPort  →  $remoteText';
  }

  @override
  String frp_connectAddress(String address) {
    return 'Connect address $address';
  }

  @override
  String frp_nodeLoadFailed(String error) {
    return 'Failed to load nodes: $error';
  }

  @override
  String frp_instancePort(String name, int port) {
    return '$name · Port $port';
  }

  @override
  String frp_tunnelCount(int count) {
    return 'Tunnels ($count)';
  }

  @override
  String get dbDetail_connectionInfo => 'Connection Info';

  @override
  String get dbDetail_connected => 'Connected';

  @override
  String get dbDetail_type => 'Type';

  @override
  String get dbDetail_address => 'Address';

  @override
  String get dbDetail_user => 'User';

  @override
  String get dbDetail_database => 'Database';

  @override
  String get dbDetail_none => 'None';

  @override
  String get dbDetail_testConnection => 'Test Connection';

  @override
  String get dbDetail_runSql => 'Run SQL';

  @override
  String get dbDetail_userManagement => 'User Management';

  @override
  String get dbDetail_newUser => 'New User';

  @override
  String get dbDetail_redisNoUserManagement =>
      'Redis does not support user management';

  @override
  String get dbDetail_noUsers => 'No users yet';

  @override
  String get dbDetail_view => 'View';

  @override
  String get dbDetail_noData => 'No Data';

  @override
  String get dbDetail_databases => 'Databases';

  @override
  String get dbDetail_newDatabase => 'New Database';

  @override
  String get dbDetail_noDatabases => 'No databases found';

  @override
  String get dbDetail_noTables => 'This database has no tables';

  @override
  String get dbDetail_addRow => 'Add Row';

  @override
  String get dbDetail_noDataInTable => 'This table has no data';

  @override
  String get dbDetail_noDataInPage => 'No data on this page';

  @override
  String get dbDetail_prevPage => 'Previous Page';

  @override
  String get dbDetail_nextPage => 'Next Page';

  @override
  String get dbDetail_saved => 'Saved';

  @override
  String get dbDetail_noMatchingRow => 'No matching row, data unchanged';

  @override
  String get dbDetail_rowAdded => 'Row added';

  @override
  String get dbDetail_deleteRow => 'Delete Row';

  @override
  String get dbDetail_deleteRowConfirm =>
      'Delete this row? This cannot be undone!';

  @override
  String get dbDetail_connectionSuccess => 'Connected successfully';

  @override
  String get dbDetail_dropDatabaseTitle => 'Delete Database';

  @override
  String get dbDetail_dropUserTitle => 'Delete User';

  @override
  String get dbDetail_searchKeyPrefix => 'Search key by prefix';

  @override
  String get dbDetail_addRedisKey => 'Add Key';

  @override
  String get dbDetail_noMatchingKeys => 'No matching keys';

  @override
  String get dbDetail_emptyValue => '(empty)';

  @override
  String get dbDetail_keyRequired => 'Key cannot be empty';

  @override
  String get dbDetail_keyName => 'Key Name';

  @override
  String get dbDetail_value => 'Value';

  @override
  String get dbDetail_usernameRequired => 'Please enter username';

  @override
  String get dbDetail_passwordRequired => 'Please enter password';

  @override
  String get dbDetail_hostRequired => 'Please enter login host';

  @override
  String get dbDetail_username => 'Username';

  @override
  String get dbDetail_password => 'Password';

  @override
  String get dbDetail_loginHost => 'Login Host';

  @override
  String get dbDetail_loginHostHint => 'e.g. % or localhost';

  @override
  String get dbDetail_create => 'Create';

  @override
  String get dbDetail_databaseNameRequired => 'Please enter database name';

  @override
  String get dbDetail_databaseName => 'Database Name';

  @override
  String get dbDetail_databaseNameHintPg =>
      'lowercase letters/digits/underscore';

  @override
  String get dbDetail_databaseNameHint => 'e.g. minecraft';

  @override
  String get dbDetail_databaseAccount => 'Dedicated database account';

  @override
  String get dbDetail_autoGenerate => 'Auto-generate';

  @override
  String get dbDetail_custom => 'Custom';

  @override
  String get dbDetail_regenerate => 'Regenerate';

  @override
  String get dbDetail_databaseAccountNote =>
      'Will create a standalone database and grant this account full privileges';

  @override
  String get dbDetail_execute => 'Execute';

  @override
  String get dbDetail_selectDatabase => 'Select Database';

  @override
  String get dbDetail_resultShownAfterRun =>
      'Results will appear here after execution';

  @override
  String get dbDetail_queryNoRows => 'Query returned 0 rows';

  @override
  String get jailDetail_tabRun => 'Run';

  @override
  String get jailDetail_tabFiles => 'Files';

  @override
  String get jailDetail_tabConsole => 'Console';

  @override
  String get jailDetail_tabPackages => 'Packages';

  @override
  String get jailDetail_tabMounts => 'Mounts';

  @override
  String get jailDetail_tabSettings => 'Settings';

  @override
  String get jailDetail_running => 'Running';

  @override
  String get jailDetail_stopped => 'Stopped';

  @override
  String get jailDetail_sectionInstanceMount =>
      'Instance Mount (bastille mount)';

  @override
  String get jailDetail_selectInstance =>
      'Select node instance (auto-fill path and command)';

  @override
  String get jailDetail_loadingInstances => 'Loading instance list…';

  @override
  String get jailDetail_manualFill => 'Manual entry (no instance selected)';

  @override
  String get jailDetail_hostPath => 'Instance directory (host path on node)';

  @override
  String get jailDetail_hostPathHint =>
      'e.g. /usr/local/irix-node/instances/mc-survival';

  @override
  String get jailDetail_jailPath => 'Path inside jail (default /data)';

  @override
  String get jailDetail_mounted => 'Mounted';

  @override
  String get jailDetail_notMounted => 'Not mounted';

  @override
  String get jailDetail_mountButton => 'Mount';

  @override
  String get jailDetail_unmountButton => 'Unmount';

  @override
  String get jailDetail_sectionRunInstance =>
      'Run instance in Jail (bastille cmd)';

  @override
  String get jailDetail_startCommand => 'Start Command';

  @override
  String get jailDetail_startCommandHint =>
      'e.g. java -Xmx2G -jar server.jar nogui';

  @override
  String get jailDetail_workdir =>
      'Working directory (in-container, default /data)';

  @override
  String get jailDetail_watchdog =>
      'Watchdog: auto-stop Jail after process exits';

  @override
  String get jailDetail_watchdogSubtitle =>
      'Automatically runs bastille stop after the in-jail process (e.g. MC server) stops';

  @override
  String get jailDetail_startRun => 'Start Run';

  @override
  String get jailDetail_stopProcess => 'Stop Process';

  @override
  String get jailDetail_sessionRunning => 'Session running';

  @override
  String get jailDetail_sessionEnded => 'Session ended';

  @override
  String get jailDetail_runHint =>
      'Tip: starting a run auto-mounts the instance directory (default /data) when not mounted. View output / send commands in the console below.';

  @override
  String get jailDetail_sessionConsole => 'Run Session Console';

  @override
  String get jailDetail_sessionNoOutput =>
      '(Run not started yet; output will appear here)';

  @override
  String get jailDetail_commandInputHint =>
      'Enter command (e.g. say hello), press Enter to send';

  @override
  String get jailDetail_jailPathLabel => 'Path inside Jail';

  @override
  String get jailDetail_jailPathHint => 'e.g. /data or /usr/local/bin';

  @override
  String get jailDetail_goto => 'Go';

  @override
  String get jailDetail_mountPoints => 'Mount points:';

  @override
  String get jailDetail_upload => 'Upload';

  @override
  String get jailDetail_newFolder => 'New Folder';

  @override
  String get jailDetail_newFile => 'New File';

  @override
  String get jailDetail_upLevel => 'Up one level';

  @override
  String get jailDetail_download => 'Download';

  @override
  String get jailDetail_fillHostPath =>
      'Please enter the instance directory (host path on node)';

  @override
  String get jailDetail_jailNotRunning =>
      'Jail is not running; start the Jail first';

  @override
  String get jailDetail_fillStartCommand =>
      'Please enter a start command (e.g. java -Xmx2G -jar server.jar nogui)';

  @override
  String get jailDetail_mountInstanceFailed =>
      'Instance directory mount failed';

  @override
  String get jailDetail_noSessionId =>
      'Node returned no session id: node may be outdated and lack the run-session interface';

  @override
  String get jailDetail_runStartedWatch => 'Started inside Jail';

  @override
  String get jailDetail_watchdogSuffix =>
      ' (watchdog on: auto-stop Jail after process exits)';

  @override
  String get jailDetail_jailStoppedSuffix => ', Jail stopped';

  @override
  String get jailDetail_startFailed => 'Failed to start';

  @override
  String get jailDetail_noRunningSession => 'No running session';

  @override
  String get jailDetail_sendFailed => 'Send failed';

  @override
  String get jailDetail_noConsoleLog => '(Jail not running, no console log)';

  @override
  String get jailDetail_noOutput => '(no output)';

  @override
  String get jailDetail_execFailed => 'Execution failed';

  @override
  String get jailDetail_fillPkgName =>
      'Please enter package name (e.g. openjdk17-jre)';

  @override
  String get jailDetail_procMounted => '/proc is mounted';

  @override
  String get jailDetail_procfsMounted => 'Mounted procfs → /proc';

  @override
  String get jailDetail_loadFilesFailed => 'Failed to load file list';

  @override
  String get jailDetail_folderName => 'Folder name';

  @override
  String get jailDetail_fileName => 'File name';

  @override
  String get jailDetail_uploadFailed => 'Upload failed';

  @override
  String get jailDetail_saveFile => 'Save file';

  @override
  String get jailDetail_downloadFailed => 'Download failed';

  @override
  String get jailDetail_fileTooLarge =>
      'File too large (>2MB), download to edit';

  @override
  String get jailDetail_readFileFailed => 'Failed to read file';

  @override
  String get jailDetail_saveFailed => 'Save failed';

  @override
  String get jailDetail_editText => 'Edit (text)';

  @override
  String get jailDetail_downloadLocal => 'Download to local';

  @override
  String get jailDetail_folder => 'folder';

  @override
  String get jailDetail_file => 'file';

  @override
  String get jailDetail_deleteFailed => 'Delete failed';

  @override
  String get jailDetail_removeConfigContent =>
      'Remove this parameter from jail.conf (takes effect on next start).';

  @override
  String get jailDetail_configTitle => 'Jail Config (bastille config)';

  @override
  String get jailDetail_addConfig => 'Add Config Item';

  @override
  String get jailDetail_noConfig =>
      'No config items yet; click \"Add Config Item\"';

  @override
  String get jailDetail_removeConfig => 'Remove Config Item';

  @override
  String get jailDetail_consoleHint =>
      'Jail system console log (bastille console view) · Commands below run inside the jail (sh semantics)';

  @override
  String get jailDetail_noLogOutput => '(no log output yet)';

  @override
  String get jailDetail_consoleCmdHint =>
      'Command to run in jail (e.g. ls /data, java -version)';

  @override
  String get jailDetail_runCommand => 'Run command';

  @override
  String get jailDetail_refreshLog => 'Refresh log';

  @override
  String get jailDetail_pkgManage => 'Package Management (bastille pkg)';

  @override
  String get jailDetail_pkgName => 'Package name (comma / space separated)';

  @override
  String get jailDetail_pkgNameHint => 'e.g. openjdk17-jre openjdk21-jre';

  @override
  String get jailDetail_pkgInstall => 'Install (install)';

  @override
  String get jailDetail_pkgDelete => 'Delete (delete)';

  @override
  String get jailDetail_pkgUpdate => 'Update index (update)';

  @override
  String get jailDetail_pkgUpgrade => 'Upgrade all (upgrade)';

  @override
  String get jailDetail_pkgAutoremove => 'Clean unused deps (autoremove)';

  @override
  String get jailDetail_executing => 'Executing…';

  @override
  String get jailDetail_execute => 'Execute';

  @override
  String get jailDetail_detectJava => 'Detect Java';

  @override
  String get jailDetail_javaEnv => 'Java Environment';

  @override
  String get jailDetail_mountProc => 'Mount /proc (procfs)';

  @override
  String get jailDetail_mountProcSubtitle =>
      'Some Java versions / JVM features (GC logs, etc.) need /proc in the jail; run once, persists after restart via fstab.';

  @override
  String get jailDetail_installJava => 'Install Java Runtime';

  @override
  String get jailDetail_installJavaSubtitle =>
      'Choose Install in \"Action\", enter a package like openjdk17-jre (see quick packages above), then click \"Execute\". After install, verify with \"Detect Java\".';

  @override
  String get jailDetail_mountListTitle => 'Mount List (bastille mount / fstab)';

  @override
  String get jailDetail_noMounts => 'No mounts yet; click \"Add Mount\"';

  @override
  String get jailDetail_openDir => 'Open directory (Files Tab)';

  @override
  String get jailDetail_fstabPersist =>
      'fstab persistent (auto-mount on restart)';

  @override
  String get jailDetail_tempMount =>
      'Current mount only (remount needed after restart)';

  @override
  String get jailDetail_addMount => 'Add Mount';

  @override
  String get jailDetail_fstype => 'Filesystem type';

  @override
  String get jailDetail_fstypeNullfs => 'nullfs (host directory)';

  @override
  String get jailDetail_fstypeProcfs => 'procfs (/proc, needed by Java)';

  @override
  String get jailDetail_srcPath => 'Host source path';

  @override
  String get jailDetail_dstPath => 'Target path inside jail';

  @override
  String get jailDetail_dstPathHint => 'e.g. /data or /proc';

  @override
  String get jailDetail_mountOption => 'Mount options (default rw)';

  @override
  String get jailDetail_fstabPersistSubtitle =>
      'Write to fstab: auto-mount on jail start, survives restart (recommended)';

  @override
  String get jailDetail_nullfsHint =>
      'Tip: nullfs live mount requires the jail running; when stopped it only writes to fstab (effective on next start). After mounting, view directory contents in the Files Tab.';

  @override
  String get jailDetail_unmountTitle => 'Unmount';

  @override
  String get jailDetail_configKey => 'Config key (e.g. ip4.addr, hostname)';

  @override
  String get jailDetail_configValue => 'Config value';

  @override
  String get jailDetail_configValueHint => 'e.g. 192.168.1.51/24, yes';

  @override
  String get jailDetail_clearOutput => 'Clear output';

  @override
  String get jailDetail_noRunningSessionInput => '(no running session)';

  @override
  String get jailDetail_send => 'Send';

  @override
  String get jailDetail_mountAddedPersist =>
      'Mount added (fstab persistent, auto-mount on restart)';

  @override
  String get jailDetail_mountAddedTemp =>
      'Mount added (current only, remount needed after restart)';

  @override
  String get jailDetail_operationFailed => 'Operation failed';

  @override
  String get jailDetail_stopFailed => 'Stop failed';

  @override
  String get jailDetail_configHintIp4Addr =>
      'IPv4 address (e.g. 192.168.1.50/24)';

  @override
  String get jailDetail_configHintIp6Addr => 'IPv6 address';

  @override
  String get jailDetail_configHintHostname => 'jail hostname';

  @override
  String get jailDetail_configHintExecStart => 'Command executed at start';

  @override
  String get jailDetail_configHintExecStop => 'Command executed at stop';

  @override
  String get jailDetail_configHintExecConsolelog => 'Console log path';

  @override
  String get jailDetail_configHintAutostart => 'Autostart on boot (yes/no)';

  @override
  String get jailDetail_configHintAllowMount => 'Allow mount inside jail';

  @override
  String get jailDetail_configHintAllowMountProcfs => 'Allow mounting procfs';

  @override
  String get jailDetail_configHintVnet => 'VNET network mode';

  @override
  String get jailDetail_configHintInterface => 'Network interface';

  @override
  String get jailDetail_configHintSecurelevel => 'Securelevel';

  @override
  String dbDetail_title(String name) {
    return '$name - Database';
  }

  @override
  String dbDetail_databasePrefix(String name) {
    return 'Database: $name';
  }

  @override
  String dbDetail_tablePrefix(String name) {
    return 'Table: $name';
  }

  @override
  String dbDetail_pageInfo(int page, int maxPage, int totalRows, int pageSize) {
    return 'Page $page / $maxPage · $totalRows rows · $pageSize per page';
  }

  @override
  String dbDetail_saveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String dbDetail_addFailed(String error) {
    return 'Add failed: $error';
  }

  @override
  String dbDetail_rowsDeleted(int count) {
    return 'Deleted $count row(s)';
  }

  @override
  String dbDetail_connectionFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String dbDetail_databaseCreated(String name) {
    return 'Database created: $name';
  }

  @override
  String dbDetail_createFailed(String error) {
    return 'Creation failed: $error';
  }

  @override
  String dbDetail_dropDatabaseConfirm(String name) {
    return 'Delete database $name? This cannot be undone!';
  }

  @override
  String dbDetail_databaseDeleted(String name) {
    return 'Database deleted: $name';
  }

  @override
  String dbDetail_deleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String dbDetail_redisKeyDeleted(String name) {
    return 'Deleted $name';
  }

  @override
  String dbDetail_userCreated(String name) {
    return 'User created: $name';
  }

  @override
  String dbDetail_dropUserConfirm(String name) {
    return 'Delete user $name?';
  }

  @override
  String dbDetail_userDeleted(String name) {
    return 'User deleted: $name';
  }

  @override
  String dbDetail_affectedRows(int count) {
    return 'Rows affected: $count';
  }

  @override
  String jailDetail_releaseOf(String name) {
    return 'Release $name';
  }

  @override
  String jailDetail_forwardOf(String ports) {
    return 'Forward $ports';
  }

  @override
  String jailDetail_pathEmpty(String path) {
    return '$path is empty\nFiles will appear here after mounting the instance directory';
  }

  @override
  String jailDetail_mountedPersist(String src, String dst) {
    return 'Mounted $src → $dst (fstab persistent, survives restart)';
  }

  @override
  String jailDetail_unmounted(String path) {
    return 'Unmounted $path';
  }

  @override
  String jailDetail_processExited(String code) {
    return 'In-container process exited (exit $code)';
  }

  @override
  String jailDetail_execFailedDetail(String error) {
    return 'Execution failed: $error';
  }

  @override
  String jailDetail_detectFailedDetail(String error) {
    return 'Detection failed: $error';
  }

  @override
  String jailDetail_locatedAt(String path) {
    return 'Located at $path';
  }

  @override
  String jailDetail_selectUpload(String path) {
    return 'Select files to upload to $path';
  }

  @override
  String jailDetail_uploadedFiles(int count, String path) {
    return 'Uploaded $count file(s) to $path';
  }

  @override
  String jailDetail_downloadedTo(String path) {
    return 'Downloaded to $path';
  }

  @override
  String jailDetail_editFile(String name) {
    return 'Edit $name';
  }

  @override
  String jailDetail_savedFile(String name) {
    return 'Saved $name';
  }

  @override
  String jailDetail_deleteConfirm(String type) {
    return 'Delete $type?';
  }

  @override
  String jailDetail_deletePathConfirm(String path, bool dir) {
    return 'Delete $path? \n$dir';
  }

  @override
  String jailDetail_deletedPath(String path) {
    return 'Deleted $path';
  }

  @override
  String jailDetail_configSaved(String key) {
    return 'Saved $key';
  }

  @override
  String jailDetail_removeConfigTitle(String key) {
    return 'Remove config item $key?';
  }

  @override
  String jailDetail_configRemoved(String key) {
    return 'Removed $key';
  }

  @override
  String jailDetail_configAdded(String key) {
    return 'Added $key';
  }

  @override
  String jailDetail_optionOf(String options) {
    return 'Options $options';
  }

  @override
  String jailDetail_unmountConfirm(String display) {
    return 'Unmount $display? \n(The fstab entry will also be removed.)';
  }

  @override
  String get nbt_title => 'NBT Editor';

  @override
  String get nbt_importNbt => 'Import .nbt';

  @override
  String get nbt_pasteSnbt => 'Paste SNBT';

  @override
  String get nbt_exportNbt => 'Export .nbt';

  @override
  String get nbt_exportViewSnbt => 'Export / View SNBT';

  @override
  String get nbt_domainTree => 'General Tree';

  @override
  String get nbt_domainItem => 'Item';

  @override
  String get nbt_domainEntity => 'Entity';

  @override
  String get nbt_domainVillager => 'Villager Trades';

  @override
  String get nbt_domainRcon => 'Connect to Server';

  @override
  String get nbt_mode => 'Mode';

  @override
  String get nbt_advancedTree => 'Advanced Tree';

  @override
  String get nbt_simpleMode => 'Simple Mode';

  @override
  String get nbt_treeOnlyAdvanced =>
      'General tree mode only provides the advanced tree editor.';

  @override
  String get nbt_searchPath => 'Search path…';

  @override
  String get nbt_root => '(root)';

  @override
  String get nbt_emptyList => '(Empty list)';

  @override
  String get nbt_emptyCompound => '(Empty Compound)';

  @override
  String get nbt_editValue => 'Edit Value';

  @override
  String get nbt_addChild => 'Add Child Node';

  @override
  String get nbt_type => 'Type';

  @override
  String get nbt_keyName => 'Key Name';

  @override
  String get nbt_rootUndeletable => 'The root node cannot be deleted';

  @override
  String get nbt_loadFailed => 'Load failed';

  @override
  String get nbt_snbtParsed => 'SNBT parsed';

  @override
  String get nbt_currentSnbt => 'Current SNBT';

  @override
  String get nbt_rconPlaceholder =>
      'The Connect-to-Server (RCON) panel will be added in Phase 3:\nEnter host/port/password to connect to a server with RCON enabled,\nand send the currently edited NBT via commands like /give, /data merge.';

  @override
  String get nbt_itemId => 'Item ID';

  @override
  String get nbt_itemCount => 'Count';

  @override
  String get nbt_itemCustomName => 'Custom Name';

  @override
  String get nbt_itemLore => 'Lore (comma-separated)';

  @override
  String get nbt_itemUnbreakable => 'Unbreakable';

  @override
  String get nbt_itemFireResistant => 'Fire-resistant';

  @override
  String get nbt_itemEnchantments => 'Enchantments (JSON array)';

  @override
  String get nbt_itemDamage => 'Damage';

  @override
  String get nbt_entityCustomName => 'Custom Name';

  @override
  String get nbt_entityHealth => 'Health';

  @override
  String get nbt_entitySilent => 'Silent';

  @override
  String get nbt_entityGlowing => 'Glowing';

  @override
  String get nbt_entityNoGravity => 'No Gravity';

  @override
  String get nbt_entityInvulnerable => 'Invulnerable';

  @override
  String get nbt_entityPoiCounted => 'Poi Counted';

  @override
  String get nbt_villagerProfession => 'Profession';

  @override
  String get nbt_villagerLevel => 'Level (experience)';

  @override
  String get nbt_villagerType => 'Villager Type';

  @override
  String get nbt_villagerOffers => 'Offers (JSON)';

  @override
  String get configEditor_noConfigFiles =>
      'No config files in this directory yet';

  @override
  String get configEditor_configGeneratedAfterStart =>
      'Config files are generated after the server starts';

  @override
  String get configEditor_configFiles => 'Config Files';

  @override
  String get configEditor_importCsv => 'Import CSV Annotations';

  @override
  String get configEditor_undo => 'Undo';

  @override
  String get configEditor_searchHint =>
      'Search config items (Chinese or English)';

  @override
  String get configEditor_unsavedChanges => 'Unsaved Changes';

  @override
  String get configEditor_discardConfirm =>
      'The current file has unsaved changes. Discard them?';

  @override
  String get configEditor_discard => 'Discard';

  @override
  String get configEditor_parseFailedTextMode =>
      'Parse failed; switched to text mode';

  @override
  String get configEditor_emptyOrUnparseable =>
      'This file is empty or cannot be parsed into a form; switch to text mode to edit.';

  @override
  String get remoteTab_selectJarToUpload => 'Select .jar file to upload';

  @override
  String get remoteTab_saveFile => 'Save File';

  @override
  String get remoteTab_deleteFileHint =>
      'This file will be deleted from the node instance.';

  @override
  String get remoteTab_deleteZipHint =>
      'This archive will be deleted from the node instance.';

  @override
  String get remoteTab_plugins => 'Plugins (plugins/)';

  @override
  String get remoteTab_mods => 'Mods (mods/)';

  @override
  String get remoteTab_metaDetectionHint =>
      'Detected from jar metadata (plugin.yml / fabric.mod.json, etc.). Uploaded .jars are written directly to the corresponding node instance directory.';

  @override
  String get remoteTab_fileListHint =>
      'The node does not provide plugin metadata (outdated?). Only the file list is shown. Uploaded .jars are written directly to the node instance directory (mods supports version subfolders, listed together here).';

  @override
  String get remoteTab_uploadJar => 'Upload .jar';

  @override
  String get remoteTab_emptyNoDetection => '(Empty) No plugins/Mods detected';

  @override
  String get remoteTab_download => 'Download';

  @override
  String get remoteTab_delete => 'Delete';

  @override
  String get remoteTab_empty => '(Empty)';

  @override
  String get remoteTab_selectRestoreZip => 'Select backup to restore (.zip)';

  @override
  String get remoteTab_restoreBackupTitle => 'Restore Backup?';

  @override
  String get remoteTab_restoreBackupContent =>
      'The archive will be uploaded to the instance root directory and extracted; files with the same name will be overwritten. It is recommended to stop the instance before restoring.';

  @override
  String get remoteTab_restore => 'Restore';

  @override
  String get remoteTab_statusCreatingSnapshot => 'Creating snapshot…';

  @override
  String get remoteTab_restoreSnapshotTitle => 'Restore Snapshot?';

  @override
  String get remoteTab_statusRestoringSnapshot => 'Restoring snapshot…';

  @override
  String get remoteTab_saveSnapshot => 'Save Snapshot';

  @override
  String get remoteTab_statusDownloadingSnapshot => 'Downloading snapshot…';

  @override
  String get remoteTab_deleteSnapshotHint =>
      'This will be permanently deleted from the node snapshot area and cannot be recovered.';

  @override
  String get remoteTab_instanceBackup => 'Instance Backup';

  @override
  String get remoteTab_instanceBackupDesc =>
      'Backup compresses the entire instance directory on the node and downloads it locally; restoring overwrites files with the same name, so it is recommended to stop the instance first.';

  @override
  String get remoteTab_startBackup => 'Start Backup';

  @override
  String get remoteTab_restoreBackup => 'Restore Backup';

  @override
  String get remoteTab_statusProcessing => 'Processing…';

  @override
  String get remoteTab_nodeSnapshot => 'Node Snapshots';

  @override
  String remoteTab_nodeSnapshotDesc(String data) {
    return 'Snapshots are stored by the node under $data/backups/<instance>; restoring stops the instance first then overwrites.';
  }

  @override
  String get remoteTab_createSnapshot => 'Create Snapshot';

  @override
  String get remoteTab_noSnapshots => '(No snapshots yet)';

  @override
  String get remoteTab_nodeBackupFiles => 'Node Backup Files';

  @override
  String get remoteTab_noZipBackups => '(No .zip backups yet)';

  @override
  String get remoteTab_backupRestored => 'Backup restored';

  @override
  String nbt_searchResults(int count) {
    return 'Search Results ($count)';
  }

  @override
  String nbt_imported(String name) {
    return 'Imported $name';
  }

  @override
  String nbt_importFailed(String e) {
    return 'Import failed';
  }

  @override
  String nbt_parseFailed(String e) {
    return 'Parse failed';
  }

  @override
  String nbt_exported(String path) {
    return 'Exported $path';
  }

  @override
  String nbt_exportFailed(String e) {
    return 'Export failed';
  }

  @override
  String nbt_generateSnbtFailed(String e) {
    return 'Failed to generate SNBT';
  }

  @override
  String nbt_searchFailed(String e) {
    return 'Search failed';
  }

  @override
  String nbt_editValueTitle(String type) {
    return 'Edit Value ($type)';
  }

  @override
  String configEditor_saved(String name) {
    return 'Saved $name';
  }

  @override
  String configEditor_saveFailed(String e) {
    return 'Save failed';
  }

  @override
  String configEditor_importedAnnotations(int count) {
    return 'Imported $count annotations';
  }

  @override
  String configEditor_importFailed(String e) {
    return 'Import failed';
  }

  @override
  String configEditor_noMatch(String query) {
    return 'No config items matching \"$query\"';
  }

  @override
  String remoteTab_downloadedTo(String path) {
    return 'Downloaded to $path';
  }

  @override
  String remoteTab_deleteJar(String name) {
    return 'Delete $name?';
  }

  @override
  String remoteTab_statusDownloadingEntry(String name) {
    return 'Downloading $name…';
  }

  @override
  String remoteTab_deleteZip(String name) {
    return 'Delete $name?';
  }

  @override
  String remoteTab_restoreSnapshotContent(String name) {
    return 'The instance will be stopped and $name extracted to overwrite the instance directory; the instance remains stopped after restore.';
  }

  @override
  String remoteTab_deleteSnapshot(String name) {
    return 'Delete snapshot $name?';
  }

  @override
  String get home_mcpRequestTitle => 'AI requests a sensitive operation';

  @override
  String get home_mcpDeny => 'Deny';

  @override
  String get home_mcpAllow => 'Allow';

  @override
  String get home_navInstances => 'Instances';

  @override
  String get home_navNodes => 'Nodes';

  @override
  String get home_navMarket => 'Market';

  @override
  String get home_navDatabase => 'Database';

  @override
  String get home_navAi => 'AI';

  @override
  String get home_navFrp => 'FRP';

  @override
  String get home_navHome => 'Home';

  @override
  String get home_navContainers => 'Containers';

  @override
  String get home_navOrchestration => 'Orchestration';

  @override
  String get home_newInstance => 'New instance';

  @override
  String get home_nbtEditor => 'NBT Editor';

  @override
  String get common_settings => 'Settings';

  @override
  String get instanceDetail_title => 'Instance Details';

  @override
  String get instanceDetail_notFound => 'Instance not found';

  @override
  String get instanceDetail_adoptedTooltip =>
      'This process was inherited from a previous IriX launch; its log is taken over, stdin is disconnected and cannot accept commands—only force stop is available';

  @override
  String get instanceDetail_adopted => 'Adopted';

  @override
  String get instanceDetail_closeAi => 'Close AI Assistant';

  @override
  String get instanceDetail_openAi => 'Open AI Assistant';

  @override
  String get instanceDetail_tabOverview => 'Overview';

  @override
  String get instanceDetail_tabConfig => 'Config';

  @override
  String get instanceDetail_tabPlugins => 'Plugins/Mods';

  @override
  String get instanceDetail_tabFiles => 'Files';

  @override
  String get instanceDetail_tabBackup => 'Backup';

  @override
  String get instanceDetail_tabSettings => 'Settings';

  @override
  String get instanceDetail_commandHintAdopted =>
      'Adopted process cannot accept commands (use force stop)';

  @override
  String get instanceDetail_commandHint =>
      'Enter a server command (no / needed) then press Enter';

  @override
  String get instanceDetail_control => 'Control';

  @override
  String get instanceDetail_start => 'Start';

  @override
  String get instanceDetail_restart => 'Restart';

  @override
  String get instanceDetail_stop => 'Stop';

  @override
  String get instanceDetail_forceStop => 'Force Stop';

  @override
  String get instanceDetail_currentStatus => 'Current Status';

  @override
  String get instanceDetail_adoptedStatusNote =>
      'This process was inherited from a previous IriX launch; its log is taken over, stdin is disconnected and cannot accept commands.';

  @override
  String get instanceDetail_selectAtLeastOne =>
      'Please select at least one file or folder';

  @override
  String get instanceDetail_backupCancelled => 'Backup cancelled';

  @override
  String get instanceDetail_selectAll => 'Select All';

  @override
  String get instanceDetail_emptyRoot => 'Root directory is empty';

  @override
  String get instanceDetail_folder => 'Folder';

  @override
  String get instanceDetail_file => 'File';

  @override
  String get instanceDetail_startBackup => 'Start Backup';

  @override
  String get instanceDetail_backingUp => 'Backing up...';

  @override
  String get instanceDetail_maxMemory => 'Max Memory';

  @override
  String get instanceDetail_notSet => 'Not set';

  @override
  String get instanceDetail_noXmxHint =>
      'Current start command does not specify -Xmx; drag the slider to set memory';

  @override
  String get instanceDetail_startCommand => 'Start Command';

  @override
  String get instanceDetail_startCommandHelper =>
      'e.g. java -Xmx2G -jar paper.jar nogui';

  @override
  String get instanceDetail_deleteInstance => 'Delete Instance';

  @override
  String get instanceDetail_stopBeforeSwitch =>
      'Stop the server before switching run mode';

  @override
  String get instanceDetail_runMode => 'Run Mode';

  @override
  String get instanceDetail_nativeProcess => 'Native Process';

  @override
  String get instanceDetail_nativeProcessDesc =>
      'Runs directly as a java process (default)';

  @override
  String get instanceDetail_dockerContainer => 'Docker Container';

  @override
  String get instanceDetail_dockerDesc =>
      'Server runs in a Docker container; start/stop, console and files go through the container';

  @override
  String get instanceDetail_dockerNotFound =>
      'Docker CLI not detected; please install and start Docker Desktop';

  @override
  String get instanceDetail_unavailable => 'Unavailable';

  @override
  String get instanceDetail_containerConfig => 'Container Configuration';

  @override
  String get instanceDetail_containerConfigSaved =>
      'Container configuration saved';

  @override
  String get instanceDetail_image => 'Image';

  @override
  String get instanceDetail_imageHelper => 'e.g. itzg/minecraft-server:latest';

  @override
  String get instanceDetail_containerName =>
      'Container Name (auto-generated if empty)';

  @override
  String get instanceDetail_portMappingHelper =>
      'Host port:Container port, separate multiple with commas, e.g. 25565:25565, 8123:8123';

  @override
  String get instanceDetail_volumeMountHelper =>
      'Host path:Container path; defaults to mounting the instance directory to /data if empty';

  @override
  String get instanceDetail_workdirHelper =>
      'e.g. /data, forces startup in the data directory';

  @override
  String get instanceDetail_containerNameDerived =>
      'Container name derived from instance name, e.g. xmc-<name>-<id-suffix>';

  @override
  String get instanceDetail_deleteInstanceConfirm =>
      'Are you sure you want to delete this instance?';

  @override
  String get instanceDetail_deleteFiles => 'Also delete server files';

  @override
  String get instanceDetail_deleteFilesDesc =>
      'When checked, all files under the server root directory will be deleted, including worlds, configs and core. This action cannot be undone.';

  @override
  String get instanceDetail_nameUpdated => 'Instance name updated';

  @override
  String get instanceDetail_instanceName => 'Instance Name';

  @override
  String get instanceDetail_backupCompressionLevel =>
      'Backup Compression Level';

  @override
  String get instanceDetail_compressionLevelDesc =>
      'Lower levels compress faster but produce larger files; higher levels give better ratios but are slower. 0=no compression (store only), 6=standard, 9=best ratio.';

  @override
  String get instanceDetail_eulaAccepted => 'EULA accepted';

  @override
  String get instanceDetail_eulaRevoked => 'EULA acceptance revoked';

  @override
  String get instanceDetail_eulaTitle => 'EULA End User License Agreement';

  @override
  String get instanceDetail_eulaNotFound =>
      'eula.txt not found; it will be created automatically after acceptance.';

  @override
  String get instanceDetail_eulaAccept => 'Accept Mojang EULA';

  @override
  String get instanceDetail_eulaAcceptedSubtitle =>
      'Accepted; server can start normally';

  @override
  String get instanceDetail_eulaNotAcceptedSubtitle =>
      'Not accepted; server will exit automatically after starting';

  @override
  String get instanceDetail_eulaNote =>
      'After accepting, eula=true is written to eula.txt. See Mojang EULA for details.';

  @override
  String get nodeDetail_notFoundOrDeleted =>
      'Node not found or has been deleted';

  @override
  String get nodeDetail_tabOverview => 'Overview';

  @override
  String get nodeDetail_tabInstances => 'Instances';

  @override
  String get nodeDetail_tabUsers => 'Users';

  @override
  String get nodeDetail_tabOps => 'Ops';

  @override
  String get nodeDetail_title => 'Node';

  @override
  String get nodeDetail_launchLocal => 'Launch Local Node';

  @override
  String get nodeDetail_cannotLaunch => 'Cannot Launch';

  @override
  String get nodeDetail_hostInfo => 'Host Info';

  @override
  String get nodeDetail_hostname => 'Hostname';

  @override
  String get nodeDetail_system => 'System';

  @override
  String get nodeDetail_platform => 'Platform';

  @override
  String get nodeDetail_uptime => 'Uptime';

  @override
  String get nodeDetail_resourceUsage => 'Resource Usage';

  @override
  String get nodeDetail_memory => 'Memory';

  @override
  String get nodeDetail_cpu => 'CPU';

  @override
  String get nodeDetail_nodeProcessMemory => 'Node Process Memory';

  @override
  String get nodeDetail_nodeVersion => 'Node Version';

  @override
  String get nodeDetail_instanceStats => 'Instance Stats';

  @override
  String get nodeDetail_daemons => 'Daemons';

  @override
  String get nodeDetail_daemonList => 'Daemon List';

  @override
  String get nodeDetail_versionUnknown => 'Version unknown';

  @override
  String get nodeDetail_noDaemonId =>
      'Cannot determine daemon ID; please check the node connection';

  @override
  String get nodeDetail_selectDaemonToManage =>
      'Select a daemon to manage its instances';

  @override
  String get nodeDetail_newInstance => 'New Instance';

  @override
  String get nodeDetail_noInstances =>
      'No instances yet\nTap \"New Instance\" at the top right to create one';

  @override
  String get nodeDetail_cwdUnknown => 'Working directory unknown';

  @override
  String get nodeDetail_onlinePlayers => 'Online players  /  ';

  @override
  String get nodeDetail_start => 'Start';

  @override
  String get nodeDetail_stop => 'Stop';

  @override
  String get nodeDetail_restart => 'Restart';

  @override
  String get nodeDetail_kill => 'Kill';

  @override
  String get nodeDetail_userManagement => 'User Management (Panel API)';

  @override
  String get nodeDetail_newUser => 'New User';

  @override
  String get nodeDetail_noUsers => 'No users yet';

  @override
  String get nodeDetail_admin => 'Admin';

  @override
  String get nodeDetail_normalUser => 'Normal User';

  @override
  String get nodeDetail_setAdmin => 'Set as Admin';

  @override
  String get nodeDetail_setNormalUser => 'Set as Normal User';

  @override
  String get nodeDetail_unban => 'Unban';

  @override
  String get nodeDetail_create => 'Create';

  @override
  String get nodeDetail_username => 'Username';

  @override
  String get nodeDetail_password => 'Password';

  @override
  String get nodeDetail_permission => 'Permission';

  @override
  String get nodeDetail_instanceName => 'Instance Name';

  @override
  String get nodeDetail_workdirAbsolute =>
      'Working Directory (absolute path on server)';

  @override
  String get nodeDetail_serverCommandHelper =>
      'Start command (e.g. java -Xmx2G -jar server.jar nogui)';

  @override
  String get nodeDetail_processType => 'Process Type';

  @override
  String get nodeDetail_processUniversal => 'Universal (runs process directly)';

  @override
  String get nodeDetail_processDocker => 'Docker (runs inside container)';

  @override
  String get nodeDetail_dockerImage => 'Docker Image (e.g. mcsm-ubuntu:22.04)';

  @override
  String get nodeDetail_memoryLimit => 'Memory Limit (MB)';

  @override
  String get nodeDetail_networkMode => 'Network Mode';

  @override
  String get nodeDetail_portMappingHelper =>
      'Port Mapping (comma separated, e.g. 25565:25565/tcp)';

  @override
  String get nodeDetail_extraVolumes =>
      'Extra Volumes (comma separated, e.g. /data:/data)';

  @override
  String get nodeDetail_containerNameOptional =>
      'Container Name (optional, auto-generated)';

  @override
  String get nodeDetail_importFailed => 'Import failed';

  @override
  String get nodeDetail_gomaxprocs => 'GOMAXPROCS';

  @override
  String get nodeDetail_gcPercent => 'GC Percent';

  @override
  String get nodeDetail_cpuUsage => 'CPU Usage';

  @override
  String get nodeDetail_goroutines => 'Goroutines';

  @override
  String get nodeDetail_heapMemory => 'Heap Memory';

  @override
  String get nodeDetail_cpuCores => 'CPU Cores';

  @override
  String get nodeDetail_nodeLoad => 'Node Load';

  @override
  String get nodeDetail_importInstanceTitle => 'Import Instance from Directory';

  @override
  String get nodeDetail_importInstanceDesc =>
      'Specify a server directory that already exists on the node; the node scans its traits and creates an instance.';

  @override
  String get nodeDetail_import => 'Import';

  @override
  String get nodeDetail_downloadCoreTitle => 'Download Server Core to Instance';

  @override
  String get nodeDetail_downloadCoreDesc =>
      'Node downloads the core jar directly from URL to the instance root (supports sha512 verification).';

  @override
  String get nodeDetail_downloadCore => 'Download Core';

  @override
  String get nodeDetail_nodeLoadDesc =>
      'Daemon\'s own load-tuning status (idle/normal/busy, GOMAXPROCS, GC).';

  @override
  String get nodeDetail_view => 'View';

  @override
  String get nodeDetail_auditLog => 'Audit Log';

  @override
  String get nodeDetail_auditLogDesc =>
      'Records every API request (source IP, method, path, status code, duration).';

  @override
  String get nodeDetail_javaRuntime => 'Java Runtime';

  @override
  String get nodeDetail_noJavaRuntime => '(No Java runtime detected)';

  @override
  String get nodeDetail_unavailableParen => '(unavailable)';

  @override
  String get nodeDetail_processing => 'Processing…';

  @override
  String get nodeDetail_instanceNameOptional =>
      'Instance name (optional, defaults to directory name)';

  @override
  String get nodeDetail_nodeDirPath => 'Absolute Path of Directory on Node';

  @override
  String get nodeDetail_nodeDirPathHint => 'e.g. /home/mc/server';

  @override
  String get nodeDetail_targetUuid => 'Target Instance UUID';

  @override
  String get nodeDetail_downloadUrl => 'Download URL (http/https)';

  @override
  String get nodeDetail_fileName => 'File Name (e.g. server.jar)';

  @override
  String get nodeDetail_sha512 => 'sha512 Checksum (optional)';

  @override
  String get nodeDetail_startDownload => 'Start Download';

  @override
  String get nodeDetail_auditLogRecent => 'Audit Log (last 200 lines)';

  @override
  String get nodeDetail_noAuditLog => '(No audit log)';

  @override
  String get nodeDetail_uninstall => 'Uninstall';

  @override
  String instanceDetail_startFailed(String error) {
    return 'Failed to start:';
  }

  @override
  String instanceDetail_restartFailed(String error) {
    return 'Failed to restart:';
  }

  @override
  String instanceDetail_backupSaved(String path) {
    return 'Backup saved to';
  }

  @override
  String instanceDetail_backupFailed(String error) {
    return 'Backup failed:';
  }

  @override
  String instanceDetail_errorCode(int code) {
    return 'Error code';
  }

  @override
  String instanceDetail_selectedCount(int selected, int total) {
    return 'Selected  /  items';
  }

  @override
  String instanceDetail_switchedToMode(String mode) {
    return 'Switched to  run mode';
  }

  @override
  String instanceDetail_eulaWriteFailed(String error) {
    return 'Failed to write eula.txt:';
  }

  @override
  String nodeDetail_onlineWithAddr(String address) {
    return 'Node online ·  ';
  }

  @override
  String nodeDetail_offlineWithError(String error) {
    return 'Node offline:';
  }

  @override
  String nodeDetail_notLocalAddress(String name) {
    return '\"\" is not a local address; please confirm irix-node is running on this server.';
  }

  @override
  String nodeDetail_cannotGetInfo(String url) {
    return 'Unable to get node info\n';
  }

  @override
  String nodeDetail_daemonCount(int count) {
    return ' daemons';
  }

  @override
  String nodeDetail_runningTotal(int running, int total) {
    return 'Running  / Total  ';
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
    return ' instances total';
  }

  @override
  String nodeDetail_deleteUserConfirm(String username) {
    return 'Delete user \"\"?';
  }

  @override
  String nodeDetail_registered(String time) {
    return 'Registered  ';
  }

  @override
  String nodeDetail_instancesCount(int count) {
    return ' instances';
  }

  @override
  String nodeDetail_installingJdk(int major) {
    return 'Installing JDK …';
  }

  @override
  String nodeDetail_jdkInstalled(int major) {
    return 'JDK  installed';
  }

  @override
  String nodeDetail_jdkInstallFailed(int major) {
    return 'JDK  installation failed';
  }

  @override
  String nodeDetail_uninstallJdkTitle(int major) {
    return 'Uninstall JDK ?';
  }

  @override
  String nodeDetail_uninstallJdkContent(String data) {
    return 'This version will be deleted from node $data/jdk.';
  }

  @override
  String nodeDetail_importedInstance(String uuid) {
    return 'Imported instance ; check the \"Instances\" tab';
  }

  @override
  String nodeDetail_importFailedWith(String error) {
    return 'Import failed:';
  }

  @override
  String nodeDetail_coreDownloadStarted(String jobId) {
    return 'Started downloading core (task ); see node logs for progress';
  }

  @override
  String nodeDetail_coreDownloadFailed(String error) {
    return 'Core download failed:';
  }

  @override
  String nodeDetail_loadFailed(String error) {
    return 'Failed to read load:';
  }

  @override
  String nodeDetail_auditFailed(String error) {
    return 'Failed to read audit log:';
  }

  @override
  String nodeDetail_javaRuntimeDesc(String data) {
    return 'Detects Java installations on the node; can install Adoptium JDK to $data/jdk.';
  }

  @override
  String nodeDetail_installJdk(int major) {
    return 'Install JDK  ';
  }

  @override
  String get frp_remotePortLabel => 'Remote port';

  @override
  String get nodeDetail_cannotConnect => 'Cannot connect';

  @override
  String nodeDetail_uptimeDaysHours(int days, int hours) {
    return '${days}d ${hours}h';
  }

  @override
  String nodeDetail_uptimeHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String nodeDetail_uptimeMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String get nodeDetail_startCommandHelper =>
      'Start command (e.g. java -Xmx2G -jar server.jar nogui)';

  @override
  String get remoteTab_statusListRoot => 'Listing instance root directory…';

  @override
  String get remoteTab_statusCompressing =>
      'Compressing instance directory on node… (may be slow for large instances)';

  @override
  String get remoteTab_saveBackup => 'Save Backup';

  @override
  String get remoteTab_statusDownloading => 'Downloading backup…';

  @override
  String remoteTab_backupSaved(String path) {
    return 'Backup saved to $path';
  }

  @override
  String get clusterHome_title => 'Home';

  @override
  String get clusterHome_refreshStatus => 'Refresh status';

  @override
  String get clusterHome_addNode => 'Add node';

  @override
  String get clusterHome_noNodes =>
      'No nodes yet. Tap + at the top right to add.';

  @override
  String get clusterHome_noNodesHint =>
      'Multi-node mode requires at least 2 nodes (MCSM panel or IriX local node).';

  @override
  String get clusterHome_monitorMutual => 'Nodes monitor each other';

  @override
  String get clusterHome_monitorNoEligible =>
      '3+ nodes but all are MCSM with no eligible monitor node (MCSM does not support node linking).';

  @override
  String get clusterHome_monitorInsufficient =>
      'At least 2 nodes are required to form a cluster.';

  @override
  String get clusterHome_networkThroughput => 'Network throughput (all nodes)';

  @override
  String get clusterHome_resourceOverview => 'Node resource overview';

  @override
  String get clusterHome_colNode => 'Node';

  @override
  String get clusterHome_colCpu => 'CPU';

  @override
  String get clusterHome_colMemory => 'Memory';

  @override
  String get clusterHome_colDisk => 'Disk';

  @override
  String get clusterHome_total => 'Total';

  @override
  String get clusterHome_monitor => 'Monitor';

  @override
  String clusterHome_cpuTooltip(Object pct) {
    return 'CPU $pct%';
  }

  @override
  String clusterHome_memoryTooltip(Object detail, Object pct) {
    return 'Memory $pct% ($detail)';
  }

  @override
  String clusterHome_diskTooltip(Object detail, Object pct) {
    return 'Disk $pct% ($detail)';
  }

  @override
  String get clusterInstances_title => 'Instance management';

  @override
  String get clusterInstances_newInstance => 'New instance';

  @override
  String get clusterInstances_empty =>
      'No cluster instances yet. Tap \"New instance\" at the top right.';

  @override
  String get clusterInstances_noNodeToMigrate =>
      'No other node available to migrate to.';

  @override
  String get clusterInstances_node => 'Node';

  @override
  String get clusterInstances_workdir =>
      'Working directory (absolute path on the server)';

  @override
  String get clusterInstances_autoAllocate => 'Auto (by resource allocation)';

  @override
  String get clusterInstances_newClusterInstance => 'New cluster instance';

  @override
  String get clusterInstances_selectMigrateTarget =>
      'Select migration target node';

  @override
  String get clusterInstances_migrate => 'Migrate';

  @override
  String get clusterContainer_noNodes => 'No nodes yet';

  @override
  String get clusterContainer_noNodesHint =>
      'Add a Linux node to manage Docker, or a FreeBSD node to manage Bastille.';

  @override
  String get clusterContainer_addNode => 'Add node';

  @override
  String get clusterContainer_node => 'Node';

  @override
  String get clusterContainer_onlineDetecting => 'Online · detecting…';

  @override
  String clusterContainer_nodeOffline(Object name) {
    return 'Node offline: $name';
  }

  @override
  String get clusterOrch_title => 'Orchestration services';

  @override
  String get clusterOrch_subtitle =>
      'K8s-style: auto-heal crashes · elastic scaling by player count · cross-host save migration';

  @override
  String get clusterOrch_reconcileNow => 'Reconcile now';

  @override
  String get clusterOrch_newService => 'New service';

  @override
  String get clusterOrch_noServices => 'No orchestration service yet';

  @override
  String get clusterOrch_noServicesHint =>
      'After creating a service, the engine automatically schedules replicas to Docker / Bastille nodes.';

  @override
  String get clusterOrch_migrationTasks => 'Migration tasks';

  @override
  String get clusterOrch_runtimeBastille => 'Bastille';

  @override
  String get clusterOrch_runtimeDocker => 'Docker';

  @override
  String get clusterOrch_scaleDown => 'Scale down';

  @override
  String get clusterOrch_scaleUp => 'Scale up';

  @override
  String get clusterOrch_migrateArchive => 'Migrate save to another node';

  @override
  String get clusterOrch_deleteServiceMenuItem => 'Delete service';

  @override
  String get clusterOrch_autoHeal => 'Auto-heal on crash';

  @override
  String get clusterOrch_autoscale => 'Elastic scaling';

  @override
  String get clusterOrch_noSchedulableNode => 'No node meets the conditions';

  @override
  String get clusterOrch_continueMigration => 'Continue migration';

  @override
  String get clusterOrch_cancelMigration => 'Cancel migration';

  @override
  String get clusterOrch_newServiceDialog => 'New orchestration service';

  @override
  String get clusterOrch_serviceName => 'Service name';

  @override
  String get clusterOrch_runtime => 'Runtime';

  @override
  String get clusterOrch_runtimeDockerLinux => 'Docker (Linux node)';

  @override
  String get clusterOrch_runtimeBastilleFbsd => 'Bastille (FreeBSD node)';

  @override
  String get clusterOrch_imageOrRelease => 'Image / release';

  @override
  String get clusterOrch_imageHintRelease => 'e.g. 14.2-RELEASE';

  @override
  String get clusterOrch_imageHintDocker => 'e.g. itzg/minecraft-server:latest';

  @override
  String get clusterOrch_portsMapping =>
      'Port mapping (host ports increment by index when scaling up)';

  @override
  String get clusterOrch_volumeMount => 'Data volume mount (host:container)';

  @override
  String get clusterOrch_volumeMountHint => 'e.g. /data/mc-survival:/data';

  @override
  String get clusterOrch_worldDir =>
      'World save directory (in container, migration target)';

  @override
  String get clusterOrch_bastilleIpBase =>
      'IP base (replicas increment by index, e.g. .50 → .51)';

  @override
  String get clusterOrch_minReplicas => 'Min replicas';

  @override
  String get clusterOrch_desiredReplicas => 'Desired replicas';

  @override
  String get clusterOrch_maxReplicas => 'Max replicas';

  @override
  String get clusterOrch_autoscaleDesc =>
      'Elastic scaling (scale by player count)';

  @override
  String get clusterOrch_targetPlayersPerReplica =>
      'Target online players per replica';

  @override
  String get clusterOrch_autoHealDesc =>
      'Auto-heal on crash (exponential backoff restart)';

  @override
  String get clusterOrch_migrateToPhysical =>
      'Migrate save to another physical host';

  @override
  String get clusterOrch_replica => 'Replica';

  @override
  String get clusterOrch_targetNode => 'Target node';

  @override
  String get clusterOrch_migrateFlow =>
      'Migration flow: stop replica → compress world save → transfer → restore on target node → rebuild and start.';

  @override
  String get clusterOrch_startMigration => 'Start migration';

  @override
  String clusterOrch_serviceCreated(Object name) {
    return 'Service created: $name';
  }

  @override
  String clusterOrch_createFailed(Object e) {
    return 'Creation failed: $e';
  }

  @override
  String clusterOrch_updateFailed(Object e) {
    return 'Update failed: $e';
  }

  @override
  String clusterOrch_deleteService(Object name) {
    return 'Delete service $name';
  }

  @override
  String get clusterOrch_deleteServiceConfirm =>
      'All replicas of this service (containers / jails) will be destroyed. Continue?';

  @override
  String get clusterOrch_migrateNeedTwoNodes =>
      'Migration requires at least 2 nodes.';

  @override
  String get clusterOrch_migrationCreated => 'Migration task created.';

  @override
  String clusterOrch_migrateFailed(Object e) {
    return 'Migration failed: $e';
  }

  @override
  String clusterOrch_deleteFailed(Object e) {
    return 'Deletion failed: $e';
  }

  @override
  String get clusterOrch_nameAndImageRequired =>
      'Name and image / release cannot be empty.';

  @override
  String clusterOrch_replicaPending(Object indexNo) {
    return 'r$indexNo · pending scheduling';
  }

  @override
  String clusterOrch_replicaRunning(Object indexNo, Object nodeId) {
    return 'r$indexNo · $nodeId (running)';
  }

  @override
  String remoteInstance_deleteTitle(Object name) {
    return 'Delete instance \"$name\"?';
  }

  @override
  String get remoteInstance_deleteContent =>
      'Deleting instance files also requires panel API permission.';

  @override
  String get remoteInstance_tabConsole => 'Console';

  @override
  String get remoteInstance_noLogOutput => '(No log output yet)';

  @override
  String get remoteInstance_commandInputHint =>
      'Enter a command (e.g. say hello) and press Enter to send.';

  @override
  String get remoteInstance_sendCommand => 'Send command';

  @override
  String get remoteInstance_fInstanceId => 'Instance ID';

  @override
  String get remoteInstance_fName => 'Name';

  @override
  String get remoteInstance_fStartCommand => 'Start command';

  @override
  String get remoteInstance_fStopCommand => 'Stop command';

  @override
  String get remoteInstance_fWorkdir => 'Working directory';

  @override
  String get remoteInstance_fType => 'Type';

  @override
  String get remoteInstance_fProcessType => 'Process type';

  @override
  String get remoteInstance_fFileEncoding => 'File encoding';

  @override
  String get remoteInstance_fInputEncoding => 'Input encoding';

  @override
  String get remoteInstance_fOutputEncoding => 'Output encoding';

  @override
  String get remoteInstance_fAutoStart => 'Auto start';

  @override
  String get remoteInstance_fAutoRestart => 'Auto restart';

  @override
  String get remoteInstance_fStartCount => 'Start count';

  @override
  String get remoteInstance_fPid => 'Process PID';

  @override
  String get remoteInstance_fContainerName => 'Container name';

  @override
  String get remoteInstance_fImage => 'Image';

  @override
  String get remoteInstance_fMemoryLimit => 'Memory limit';

  @override
  String get remoteInstance_fPortMapping => 'Port mapping';

  @override
  String get remoteInstance_fExtraVolumes => 'Extra volumes';

  @override
  String get remoteInstance_fNetworkMode => 'Network mode';

  @override
  String get remoteInstance_editConfig => 'Edit config';

  @override
  String get remoteInstance_editConfigDialog => 'Edit instance config';

  @override
  String get remoteInstance_autoRestartToggle => 'Auto restart after crash';

  @override
  String get remoteInstance_processUniversal =>
      'Universal (run process directly)';

  @override
  String get remoteInstance_processDocker => 'Docker (run in container)';

  @override
  String get remoteInstance_dockerImage =>
      'Docker image (e.g. mcsm-ubuntu:22.04)';

  @override
  String get remoteInstance_memoryLimitMb => 'Memory limit (MB)';

  @override
  String get remoteInstance_portsMapping =>
      'Port mapping (comma-separated, e.g. 25565:25565/tcp)';

  @override
  String get remoteInstance_extraVolumes =>
      'Extra volumes (comma-separated, e.g. /data:/data)';

  @override
  String get remoteInstance_containerNameAuto =>
      'Container name (leave empty to auto-generate)';

  @override
  String get remoteFile_noDaemonId => 'Cannot determine daemon ID.';

  @override
  String get remoteFile_newFolder => 'New folder';

  @override
  String get remoteFile_folderName => 'Folder name';

  @override
  String get remoteFile_newFile => 'New file';

  @override
  String get remoteFile_fileName => 'File name';

  @override
  String get remoteFile_selectFilesToUpload => 'Select files to upload';

  @override
  String get remoteFile_saveFile => 'Save file';

  @override
  String get remoteFile_fileTooLarge =>
      'File too large (>2MB). Download it to edit.';

  @override
  String remoteFile_editFile(Object name) {
    return 'Edit $name';
  }

  @override
  String get remoteFile_saved => 'Saved.';

  @override
  String remoteFile_rename(Object name) {
    return 'Rename $name';
  }

  @override
  String get remoteFile_newName => 'New name';

  @override
  String remoteFile_compress(Object name) {
    return 'Compress $name';
  }

  @override
  String get remoteFile_archiveName => 'Archive file name';

  @override
  String get remoteFile_folder => 'Folder';

  @override
  String get remoteFile_download => 'Download';

  @override
  String get remoteFile_edit => 'Edit';

  @override
  String get remoteFile_renameAction => 'Rename';

  @override
  String get remoteFile_unzipHere => 'Unzip to current directory';

  @override
  String get remoteFile_compressZip => 'Compress as ZIP';

  @override
  String clusterHome_monitorAssigned(String name) {
    return 'Monitor node assigned: $name';
  }

  @override
  String clusterHome_nodeCount(int count) {
    return '$count nodes';
  }

  @override
  String clusterHome_systemInfo(String sys, String ver) {
    return 'System: $sys$ver';
  }

  @override
  String clusterInstances_cannotOpenDetail(String e) {
    return 'Cannot open details: $e';
  }

  @override
  String clusterInstances_nodeOf(String name) {
    return 'Node: $name';
  }

  @override
  String clusterInstances_crashLine(int count, String sync) {
    return 'Crashed $count times · last synced $sync';
  }

  @override
  String clusterContainer_onlineWith(String runtime) {
    return 'Online · $runtime';
  }

  @override
  String clusterOrch_replicaStat(
    int running,
    int desired,
    int players,
    String avg,
  ) {
    return '$running/$desired replicas · $players online (avg $avg)';
  }

  @override
  String clusterOrch_scaleTarget(int target, int down, int up) {
    return 'Target $target/replica · threshold $down~$up';
  }

  @override
  String remoteInstance_downloadedTo(String path) {
    return 'Downloaded to $path';
  }

  @override
  String get market_typePlugin => 'Plugin';

  @override
  String get market_sortRelevance => 'Relevance';

  @override
  String get market_sortDownloads => 'Downloads';

  @override
  String get market_sortFollows => 'Follows';

  @override
  String get market_sortNewest => 'Newest';

  @override
  String get market_sortUpdated => 'Updated';

  @override
  String get market_searchHint => 'Search Mods / Plugins...';

  @override
  String get market_type => 'Type';

  @override
  String get market_sort => 'Sort';

  @override
  String get market_loader => 'Core';

  @override
  String get market_all => 'All';

  @override
  String get market_gameVersion => 'Game Version';

  @override
  String get market_noResults => 'No matching projects found';

  @override
  String get market_downloads => 'downloads';

  @override
  String get market_stars => 'favorites';

  @override
  String get hangar_downloadRejected =>
      'Download rejected: filename contains illegal path characters';

  @override
  String get hangar_viewPath => 'View path';

  @override
  String get hangar_description => 'Description';

  @override
  String get hangar_notFound => 'Project not found';

  @override
  String get hangar_downloads => 'downloads';

  @override
  String get hangar_stars => 'favorites';

  @override
  String get hangar_platform => 'Platform';

  @override
  String get mod_downloadRejected =>
      'Download rejected: filename is empty or contains illegal path characters';

  @override
  String get mod_openDirectory => 'Open directory';

  @override
  String get mod_notFound => 'Project not found';

  @override
  String get mod_description => 'Description';

  @override
  String get mod_versionList => 'Version list';

  @override
  String get mod_downloads => 'downloads';

  @override
  String get mod_follows => 'follows';

  @override
  String get pluginsUI_empty => 'No plugins / Mods yet';

  @override
  String get pluginsUI_emptyHint =>
      'Place plugins in plugins/ and Mods in mods/, then rescan';

  @override
  String get pluginsUI_sectionPlugins => 'Plugins';

  @override
  String get pluginsUI_sectionMods => 'Mods';

  @override
  String get pluginsUI_kindPlugin => 'Plugin';

  @override
  String get pluginsUI_noConfig => 'No config';

  @override
  String get pluginsUI_configOnly => 'Config only';

  @override
  String get download_title => 'Download Core';

  @override
  String get download_step1 => 'Step 1 · Select core and version';

  @override
  String get download_source => 'Download source';

  @override
  String get download_mslSource => 'MSL Mirror';

  @override
  String get download_mslAttribution => 'Provided by MSL launcher service';

  @override
  String get download_serverCore => 'Server core';

  @override
  String get download_selectCore => 'Please select a core';

  @override
  String get download_serverVersion => 'Server version';

  @override
  String get download_selectCoreFirst => 'Please select a core first';

  @override
  String get download_noVersionsForCore =>
      'No versions available for this core';

  @override
  String get download_selectVersion => 'Please select a version';

  @override
  String get download_nextStep => 'Next';

  @override
  String get download_scenario => 'Use case';

  @override
  String download_scenarioWithCategory(String scenario, String category) {
    return '$scenario ($category)';
  }

  @override
  String get download_loadFailed => 'Failed to load';

  @override
  String get download_description => 'Description';

  @override
  String get download_downloadFailed => 'Download failed';

  @override
  String get download_step2 => 'Step 2 · Download core file';

  @override
  String get download_downloadingHint => 'Downloading… please do not leave';

  @override
  String get download_step3 => 'Step 3 · Edit launch command';

  @override
  String get download_command => 'Launch command';

  @override
  String get download_finishCreate => 'Finish and create instance';

  @override
  String get dbScreen_saved => 'Saved';

  @override
  String get dbScreen_deleteTitle => 'Delete connection';

  @override
  String get dbScreen_deleted => 'Deleted';

  @override
  String get dbScreen_connectionFailed => 'Connection failed';

  @override
  String get dbScreen_title => 'Database';

  @override
  String get dbScreen_addConnection => 'Add connection';

  @override
  String get dbScreen_manageHint =>
      'Manage MySQL / MariaDB / PostgreSQL / Redis server connections';

  @override
  String get dbScreen_emptyTitle => 'No database connections yet';

  @override
  String get dbScreen_emptyAddHint =>
      'Tap the button at the top right to add one';

  @override
  String get dbScreen_connect => 'Connect';

  @override
  String get dbScreen_nameRequired => 'Please enter a name';

  @override
  String get dbScreen_hostRequired => 'Please enter a host address';

  @override
  String get dbScreen_portRange => 'Port must be between 1 and 65535';

  @override
  String get dbScreen_editTitle => 'Edit connection';

  @override
  String get dbScreen_host => 'Host';

  @override
  String get dbScreen_hostHint => 'e.g. 127.0.0.1';

  @override
  String get dbScreen_port => 'Port';

  @override
  String get dbScreen_usernameOptional => 'Username (optional)';

  @override
  String get dbScreen_passwordOptional => 'Password (optional)';

  @override
  String get dbScreen_databaseNameOptional => 'Database name (optional)';

  @override
  String get dbScreen_useSsl => 'Use SSL connection';

  @override
  String get dbScreen_sslSubtitle =>
      'Encrypted transfer (MySQL/MariaDB/PostgreSQL/Redis, verifies server certificate)';

  @override
  String get nodes_title => 'Nodes';

  @override
  String get nodes_refreshStatus => 'Refresh status';

  @override
  String get nodes_addNode => 'Add node';

  @override
  String get nodes_empty => 'No nodes yet. Tap + at the top right to add one';

  @override
  String get nodes_emptyHint =>
      'MCSM: connect to MCSManager panel\nNode: local Go-language node (node/ directory)';

  @override
  String get nodes_daemonRunning => 'Local node daemon is running';

  @override
  String get nodes_daemonHint =>
      'Tip: Node-type nodes require running the irix-node service built from the node/ directory first';

  @override
  String hangar_installedToNode(String nodeName) {
    return 'Installed to plugins/ of node $nodeName';
  }

  @override
  String hangar_downloadedTo(String path) {
    return 'Downloaded to $path';
  }

  @override
  String hangar_directory(String path) {
    return 'Directory: $path';
  }

  @override
  String hangar_downloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String hangar_publishedOn(String date) {
    return 'Published on $date';
  }

  @override
  String hangar_versionList(int count) {
    return 'Version list ($count)';
  }

  @override
  String mod_downloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String mod_downloadedTo(String path) {
    return 'Downloaded to $path';
  }

  @override
  String mod_installedToNode(String nodeName, String dir) {
    return 'Installed to $dir/ of node $nodeName';
  }

  @override
  String mod_directory(String path) {
    return 'Directory: $path';
  }

  @override
  String mod_publishedOn(String date) {
    return 'Published on $date';
  }

  @override
  String pluginsUI_noConfigFiles(String name) {
    return '$name has no manageable config files';
  }

  @override
  String download_downloaded(String size) {
    return 'Downloaded $size';
  }

  @override
  String download_speed(String speed) {
    return 'Speed: $speed/s';
  }

  @override
  String download_coreFile(String fileName) {
    return 'Core file: $fileName';
  }

  @override
  String dbScreen_deleteConfirm(String name) {
    return 'Delete \"$name\"? This will not affect the remote server.';
  }

  @override
  String get newInstance_download => 'Download';

  @override
  String get newInstance_downloadDesc =>
      'Automatically download the core and create a new server instance';

  @override
  String get newInstance_import => 'Import';

  @override
  String get newInstance_importDesc =>
      'Import a server core to create a new server instance';

  @override
  String get importCore_title => 'Import Core';

  @override
  String get importCore_coreFile => 'Core file';

  @override
  String get importCore_coreFileHint => 'Select a .jar core file';

  @override
  String get importCore_browse => 'Browse';

  @override
  String get importCore_rootPath => 'Server root directory path';

  @override
  String get importCore_rootPathHint =>
      'Select or enter the server root directory';

  @override
  String get importCore_startCommandHint =>
      'java -Xmx2G -jar <jar filename> nogui';

  @override
  String get importCore_creating => 'Creating…';

  @override
  String get importCore_createInstance => 'Create Instance';

  @override
  String get importCore_desc =>
      'Import a downloaded core .jar file and create a new instance from it.';

  @override
  String get importCore_fillAllFields =>
      'Please fill in the core file, server root directory path, and start command';

  @override
  String get importInstance_title => 'Import Instance';

  @override
  String get importInstance_instanceName => 'Instance name';

  @override
  String get importInstance_instanceNameHint =>
      'Left empty to assign a random name automatically';

  @override
  String get importInstance_rootPath => 'Server root directory path';

  @override
  String get importInstance_rootPathHint =>
      'Select or enter the server root directory';

  @override
  String get importInstance_startCommandHint =>
      'java -Xmx2G -jar server.jar nogui';

  @override
  String get importInstance_browse => 'Browse';

  @override
  String get importInstance_creating => 'Creating…';

  @override
  String get importInstance_createInstance => 'Create Instance';

  @override
  String get importInstance_desc =>
      'Import an existing server directory, using its original file structure.';

  @override
  String get importInstance_fillRequired =>
      'Please fill in the server root directory path and start command';

  @override
  String get trash_title => 'Recycle Bin';

  @override
  String get trash_purge => 'Purge';

  @override
  String get trash_empty => 'Recycle bin is empty';

  @override
  String get trash_purgeTitle => 'Empty Recycle Bin';

  @override
  String get trash_purgeAllConfirm =>
      'Permanently delete all files in the recycle bins of every instance? This action cannot be undone.';

  @override
  String get trash_purgeScopeConfirm =>
      'Permanently delete all files in this instance\'s recycle bin? This action cannot be undone.';

  @override
  String get trash_purged => 'Recycle bin emptied';

  @override
  String get trash_restore => 'Restore';

  @override
  String get trash_permanentlyDelete => 'Permanently Delete';

  @override
  String get archive_selectExtractDir => 'Select extraction target folder';

  @override
  String get archive_extractTo => 'Extract to…';

  @override
  String get archive_cannotOpen => 'Cannot open archive file';

  @override
  String get archive_invalidArchiveHint =>
      'Please confirm this is a valid ZIP/JAR archive';

  @override
  String get archive_emptyArchive => 'Archive is empty';

  @override
  String get archive_colName => 'File name';

  @override
  String get archive_colSize => 'Size';

  @override
  String get archive_colModified => 'Modified';

  @override
  String get textEditor_undo => 'Undo';

  @override
  String get textEditor_cannotRead => 'Cannot read file';

  @override
  String get onboarding_title => 'IriX';

  @override
  String get onboarding_create => 'Create';

  @override
  String get onboarding_createDesc => 'Create a new Minecraft server instance';

  @override
  String get onboarding_import => 'Import';

  @override
  String get onboarding_importDesc => 'Import a Minecraft server instance';

  @override
  String get remoteTab_restoreFailed => 'Restore failed';

  @override
  String get remoteTab_snapshotFailed => 'Snapshot failed';

  @override
  String get remoteTab_unzippingOnNode => 'Unzipping on node…';

  @override
  String get remoteTab_uploadingBackup => 'Uploading backup…';

  @override
  String trash_purgeFailed(String e) {
    return 'Failed to purge: $e';
  }

  @override
  String trash_restored(String path) {
    return 'Restored \"$path\"';
  }

  @override
  String trash_restoreFailed(String e) {
    return 'Failed to restore: $e';
  }

  @override
  String trash_permanentlyDeleted(String path) {
    return 'Permanently deleted \"$path\"';
  }

  @override
  String trash_deleteFailed(String e) {
    return 'Failed to delete: $e';
  }

  @override
  String trash_deletedAt(String date) {
    return 'Deleted at $date';
  }

  @override
  String trash_groupHeader(String label, int count) {
    return '$label · $count items';
  }

  @override
  String trash_today(String time) {
    return 'Today $time';
  }

  @override
  String trash_yesterday(String time) {
    return 'Yesterday $time';
  }

  @override
  String archive_extracted(String name) {
    return 'Extracted: $name';
  }

  @override
  String archive_extractFailed(String e) {
    return 'Extraction failed: $e';
  }

  @override
  String archive_entryCount(int count) {
    return '$count entries';
  }

  @override
  String archive_fileNotFound(String path) {
    return 'File not found: $path';
  }

  @override
  String get common_download => 'Download';

  @override
  String remoteFile_downloadedTo(String path) {
    return 'Downloaded to $path';
  }
}
