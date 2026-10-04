# CPUthermal（CPU 解除温控）

适配 iOS 15–17 与不同 iPhone / iPad 机型的温控管理插件（Theos tweak）。注入 `thermalmonitord`，固定解除温控模式，支持 CPU / GPU / Package 温控旁路、ProMotion 120Hz、防温控暗屏、智能停充，以及 `/System/Library/ThermalMonitor` 一键挂载优化。

原始版本：1.6.2-103，作者 [Huayuarc](https://github.com/huayuarc)。本仓库在原始源码基础上新增「过热自动锁屏」功能。

## 功能

- **温度保护引擎**：低功耗 / 稳定高性能 / 极限满频三种运行方式，过热自动降功耗，温度正常后自动恢复
- **解除温控**：拦截 thermalmonitord 的 CPU / GPU / Package 降频约束
- **屏蔽高温警告**：阻止全屏「iPhone 需要冷却」警告及高温强制锁屏行为
- **防温控暗屏**：屏幕亮度上限锁定在本机最高值
- **设备朝下自动锁屏**：屏幕朝下时模拟按下锁屏键
- **过热自动锁屏（新增）**：电池温度或系统热压力达到阈值且持续过热时自动锁定屏幕
- **强制 120Hz**：ProMotion 设备统一提升到 120Hz
- **智能停充**：移植 ChargeLimiter 电量阈值核心，支持 SmartBatteryAPI 与禁流
- **屏蔽部件与维修记录**：隐藏设置页与「关于本机」中的部件 / 服务历史

## 新增：过热自动锁屏

注入 SpringBoard 的独立模块（`AutoLock.xm`），周期性（每 5 秒）读取电池温度（IOKit `AppleSmartBattery`）与系统热压力（`com.apple.system.thermalpressurelevel`），任一项达到设定阈值并**连续过热约 10 秒**后，模拟按下锁屏键锁定屏幕。

- 触发后进入 **90 秒冷却期**，不会反复锁屏
- 设备已锁定时不重复触发
- 默认关闭，需在设置中手动开启

### 设置项

| 设置 | 键名 | 默认值 | 说明 |
|---|---|---|---|
| 过热自动锁屏 | `autoLockOnOverheatEnabled` | 关 | 总开关 |
| 锁屏温度阈值 | `autoLockTempThreshold` | 45°C | 40 / 45 / 50 / 55 / 60°C |
| 锁屏压力级别 | `autoLockPressureLevel` | 重度 (30) | 轻度 / 中度 / 重度 / 临界 / 休眠 |

## 构建

需要 [Theos](https://theos.dev) 与 iOS SDK（Xcode toolchain）。

```bash
# rootless（默认）
make package

# roothide
make package SCHEME=roothide
```

产物为 `.deb` 安装包，使用 Sileo / Zebra / Filza 安装（依赖 `mobilesubstrate` 与 `preferenceloader`）。

## 项目结构

```
Tweak.x                 # 主模块：注入 thermalmonitord，解除温控
Tweak_PrefHook.xm       # 屏蔽部件维修记录等（Preferences / SpringBoard）
FaceDownLock.xm         # 设备朝下自动锁屏（SpringBoard）
AutoLock.xm             # ★ 新增：过热自动锁屏（SpringBoard）
DisplayGuard.xm         # 防温控暗屏（backboardd / SpringBoard）
RefreshRate.xm          # 强制 120Hz（UIKit / SpringBoard）
Settings/               # 设置页（PreferenceLoader bundle）
ControlCenter/          # 控制中心模块
Tools/                  # CPUthermalTool / CPUthermalChargeTool
layout/                 # 安装脚本与 LaunchDaemon
```

## 免责声明

解除温控会削弱系统过热保护，可能加速硬件老化或导致不稳定。请自行评估风险，本插件不对因使用导致的任何设备损坏负责。
