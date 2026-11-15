import 'package:security_flutter/security_flutter.dart';

String detectorName(String id) => _names[id] ?? id;
const _names = {
  'root': 'Root / 越狱',
  'hook': 'Hook / 注入',
  'debugger': '调试器',
  'appIntegrity': '应用完整性',
  'emulator': '模拟器',
  'multiInstance': '多开 / 分身环境',
  'automation': '自动化',
  'developerMode': '开发者模式',
  'usbDebugging': 'USB 调试',
  'accessibility': '无障碍功能',
  'vpn': 'VPN',
  'proxy': '系统代理',
  'screenshot': '截图事件',
  'screenRecording': '录屏 / 镜像',
  'timeAnomaly': '设备时间',
  'mockLocation': '位置模拟',
};

String findingConclusion(SecurityFinding finding) {
  if (finding.status == DetectionStatus.error &&
      finding.reason == FindingReason.settingValueUnavailable) {
    if (finding.values['settingPresent'] == false) {
      return '系统未返回此设置（读取值为 null），无法判断开关状态';
    }
    if (finding.values['settingPresent'] == true &&
        finding.values['settingValueValid'] == false) {
      return '系统返回了非 0/1 的设置值，无法判断开关状态';
    }
  }
  if (finding.status == DetectionStatus.notDetected) {
    if (finding.reason == FindingReason.noActiveNetwork) {
      return '当前无活动网络，无法判断 VPN 状态';
    }
    if (finding.detectorId == SecurityDetectors.accessibility) {
      if (finding.values['accessibilityEnabled'] == false) {
        return '系统无障碍开关读数为 false（未启用）';
      }
      if (finding.values['voiceOverEnabled'] == false &&
          finding.values['switchControlEnabled'] == false) {
        return 'VoiceOver 和切换控制均未启用（本次系统读数）';
      }
    }
    return switch (finding.detectorId) {
      'root' => '未发现已知 Root / 越狱特征',
      'hook' => '未发现已知 Hook / 注入特征',
      'debugger' => '本次检查未发现调试器附加或等待信号',
      'appIntegrity' =>
        finding.reason == FindingReason.signingBaselineMatched
            ? '已检查的应用标识及签名与配置基准一致'
            : '已检查的应用标识及文件与配置基准一致',
      'emulator' => '未发现已知模拟器特征',
      'multiInstance' => '未发现已知多开 / 分身特征',
      'automation' => '未发现已知自动化信号',
      'accessibility' => '系统未报告被检查的无障碍功能已启用',
      'vpn' => '本次检查未发现 VPN / 隧道信号',
      'proxy' => '未发现系统代理配置',
      'screenshot' => '本次观察期间未收到截图事件',
      'screenRecording' => '系统未报告当前窗口被录屏或镜像',
      'timeAnomaly' => '设备时间偏差在配置阈值内',
      'mockLocation' => '位置样本的模拟标记为 false',
      _ => '本次检查未命中检测条件',
    };
  }
  return _reasons[finding.reason] ??
      switch (finding.status) {
        DetectionStatus.detected => '本次检查命中检测条件',
        DetectionStatus.unsupported => '当前条件不支持检查，无法判断',
        DetectionStatus.error => '本次检查失败，无法判断',
        DetectionStatus.notDetected => '本次检查未命中检测条件',
      };
}

const _reasons = <FindingReason, String>{
  FindingReason.developerModeEnabled: '系统开发者选项读取值为 1（已启用）',
  FindingReason.usbDebuggingEnabled: '系统 USB 调试设置读取值为 1（已启用）',
  FindingReason.settingReadRestricted: '设置读取值为 0；系统可能隐藏真实状态，无法确认关闭',
  FindingReason.settingValueUnavailable: '设置缺失或读数无效，无法判断开关状态',
  FindingReason.unsupportedPlatform: '当前平台未提供这项检查',
  FindingReason.unsupportedOsVersion: '当前系统版本不支持这项检查',
  FindingReason.unimplemented: '此检测项尚无实现',
  FindingReason.unsupportedProcess: '当前进程不支持这项检查',
  FindingReason.profileTypeUnavailable: '系统未提供可用的用户配置类型，无法判断分身',
  FindingReason.executableFormatUnavailable: '无法读取可执行文件格式，无法判断分身',
  FindingReason.simulatorEnvironment: '当前为模拟器环境，这项检查不适用',
  FindingReason.unsupportedBuildMode: '当前构建模式不支持这项检查',
  FindingReason.releaseDebuggerOptInRequired: '未显式启用 iOS Release 调试器检查',
  FindingReason.missingPermission: '缺少系统访问权限，无法完成检查',
  FindingReason.noActivity: '没有可用的前台窗口，请回到前台后重试',
  FindingReason.observationRequired: '尚未开始截图观察，请先点击开始 / 重开观察',
  FindingReason.observationInterrupted: '截图观察已中断，请重新开始观察',
  FindingReason.nativeFailure: '系统接口调用失败，请重试',
  FindingReason.processIdentityMismatch: '进程身份信息不一致，本次无法完成检查',
  FindingReason.processIdentityUnavailable: '进程身份信息不可用，本次无法完成检查',
  FindingReason.debuggerPolicyInvalid: '调试器检查配置无效',
  FindingReason.processInfoMismatch: '进程信息格式不匹配，无法判断调试状态',
  FindingReason.probeAccessRestricted: '检测所需的信息访问受限，无法完成检查',
  FindingReason.scanLimitExceeded: '已达到扫描限制，本次检查未完成',
  FindingReason.integrityBaselineRequired: '未配置可信完整性基准，尚未进行比较',
  FindingReason.integrityPolicyInvalid: '完整性基准配置无效',
  FindingReason.signingInfoUnavailable: '应用签名信息不可用，无法比较',
  FindingReason.timeReferenceRequired: '缺少可信时间基准，尚未进行比较',
  FindingReason.timeReferenceExpired: '可信时间基准已过期，请更新后重试',
  FindingReason.locationConsentRequired: '尚未确认合法定位业务用途，未检查位置样本',
  FindingReason.locationPermissionRequired: '定位业务未获得权限，未检查位置样本',
  FindingReason.locationSampleRequired: '未提供位置样本，尚未检查',
  FindingReason.locationSampleStale: '位置样本已过期，请提供新样本',
  FindingReason.locationSourceUnavailable: '位置来源未提供模拟标记，无法判断',
  FindingReason.rootArtifact: '发现已知 Root 文件特征',
  FindingReason.rootMountArtifact: '发现已知 Root 挂载特征',
  FindingReason.jailbreakLoadedImage: '发现已加载的越狱模块特征',
  FindingReason.rootUid: '当前进程具有 Root 用户身份',
  FindingReason.testKeysBuild: '系统构建使用测试签名特征',
  FindingReason.jailbreakArtifact: '发现已知越狱特征',
  FindingReason.hookModule: '发现已知 Hook 模块特征',
  FindingReason.hookMemfd: '发现与 Hook 相关的匿名可执行映射特征',
  FindingReason.injectedModulePath: '发现注入模块路径特征',
  FindingReason.hookClass: '发现已知 Hook 类特征',
  FindingReason.debuggerAttached: '检测到调试器附加信号',
  FindingReason.debuggerWaiting: '当前进程正在等待调试器',
  FindingReason.applicationIdMismatch: '应用标识与配置基准不一致',
  FindingReason.signingCertificateMismatch: '签名证书与配置基准不一致',
  FindingReason.integrityFileMissing: '完整性基准要求的文件缺失',
  FindingReason.integrityFileMismatch: '文件校验值与配置基准不一致',
  FindingReason.integrityFileInvalid: '完整性检查文件类型或路径无效',
  FindingReason.emulatorBuild: '发现模拟器构建特征',
  FindingReason.managedProfile: '检测到受管理的工作资料环境',
  FindingReason.cloneProfile: '检测到系统分身资料环境',
  FindingReason.virtualContainerPath: '发现虚拟容器路径特征',
  FindingReason.virtualContainerIdentity: '发现虚拟容器身份特征',
  FindingReason.embeddedAppBundle: '发现嵌套应用包特征',
  FindingReason.appExecutableIsLibrary: '应用可执行文件呈动态库格式',
  FindingReason.monkey: '系统报告 Monkey 自动化运行状态',
  FindingReason.testHarness: '系统报告测试框架运行状态',
  FindingReason.gestureService: '检测到可执行手势的无障碍服务',
  FindingReason.accessibilityEnabled: '系统报告被检查的无障碍功能已启用',
  FindingReason.vpnTransport: '活动网络具有 VPN 传输标记',
  FindingReason.tunnelInterface: '发现活动隧道网络接口',
  FindingReason.proxyConfigured: '发现系统代理配置',
  FindingReason.screenshotObserved: '本次观察期间已收到截图事件',
  FindingReason.screenCaptured: '系统报告当前窗口正在被录屏或镜像',
  FindingReason.timeDeviation: '设备时间偏差超过配置阈值',
  FindingReason.mockLocation: '位置样本的模拟标记为 true',
};

/// Render exactly the SDK fields; do not infer missing readings from status.
String findingOutput(SecurityFinding finding) => [
  'detectorId: ${finding.detectorId}',
  'status: ${finding.status.name}',
  'reason: ${finding.reason?.name ?? "null"}',
  'detectorVersion: ${finding.detectorVersion}',
  if (finding.values.isEmpty)
    'values: {}（本次未返回底层读数）'
  else ...[
    'values:',
    for (final entry in finding.values.entries)
      '  ${entry.key}: ${entry.value}（${_valueNames[entry.key] ?? "读数"}）',
  ],
].join('\n');

const _valueNames = {
  'signalDetected': '本项检测条件是否命中',
  'settingValue': '系统设置读数，null 表示缺失或无效',
  'settingPresent': '设置是否存在',
  'settingValueValid': '是否为有效的 0/1 读数',
  'accessibilityEnabled': '无障碍功能是否启用',
  'voiceOverEnabled': 'VoiceOver 是否启用',
  'switchControlEnabled': '切换控制是否启用',
  'activeNetworkAvailable': '是否存在活动网络',
  'vpnTransport': '活动网络的 VPN 标记',
  'hostProxyConfigured': '是否配置主机代理',
  'httpProxyEnabled': 'HTTP 代理开关',
  'pacProxyConfigured': 'PAC 代理开关 / 配置',
  'javaDebuggerConnected': 'Java 调试器是否连接',
  'waitingForDebugger': '是否等待 Java 调试器',
  'processTraced': '进程是否被跟踪',
  'deviationUs': '时间绝对偏差，微秒',
  'allowedSkewUs': '允许时间偏差，微秒',
  'referenceAgeUs': '时间基准年龄，微秒',
  'referenceValidForUs': '时间基准有效期，微秒',
  'businessUseAuthorized': '是否确认合法定位用途',
  'permissionGranted': '定位业务是否有权限',
  'isMocked': '位置样本模拟标记',
  'sampleAgeUs': '位置样本年龄，微秒',
  'sampleMaxAgeUs': '位置样本最大年龄，微秒',
};
