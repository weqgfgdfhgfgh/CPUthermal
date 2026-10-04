#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <dlfcn.h>
#import <IOKit/IOKitLib.h>
#import <CPUthermalPaths.h>
#import <CPUthermalPressure.h>

@interface SpringBoard : UIApplication
+ (instancetype)sharedApplication;
- (void)_simulateLockButtonPress;
@end

// ============================================================================
// 过热自动锁屏（Auto Lock on Overheat）
// 注入 SpringBoard：周期性读取电池温度与系统热压力，
// 任一项达到设定阈值并持续过热一段时间后，模拟按下锁屏键锁定屏幕，
// 触发后进入冷却期，避免反复锁屏；设备已锁定时不重复触发。
//
// 设置键（com.huayuarc.cputhermal）：
//   autoLockOnOverheatEnabled  (BOOL)  总开关，默认关
//   autoLockTempThreshold      (int)   锁屏温度阈值（°C），默认 45
//   autoLockPressureLevel      (int)   锁屏热压力级别，默认 30 (Heavy/重度)
// ============================================================================

static BOOL gAutoLockEnabled = NO;
static int gAutoLockTempThreshold = 45;
static int gAutoLockPressureLevel = CPUthermalPressureLevelHeavy;

static int gAutoLockSettingsToken = 0;
static int gAutoLockLockStateToken = 0;
static BOOL gAutoLockDeviceLocked = NO;

static const double kAutoLockCheckInterval = 5.0;   // 检查周期（秒）
static const int    kAutoLockRequiredStreak = 2;    // 连续过热采样次数（约 10 秒）才触发
static const double kAutoLockCooldown      = 90.0;  // 触发后的冷却期（秒）
static CFAbsoluteTime gAutoLockCooldownUntil = 0;

static void CPUthermalAutoLockReloadPrefs(void) {
    NSDictionary *prefs = CPUthermalReadPrefs();
    if (!prefs) return;
    gAutoLockEnabled = [prefs[S("autoLockOnOverheatEnabled")] boolValue];
    id temp = prefs[S("autoLockTempThreshold")];
    if ([temp respondsToSelector:@selector(intValue)]) {
        int v = [temp intValue];
        if (v >= 40 && v <= 60) gAutoLockTempThreshold = v;
    }
    id pressure = prefs[S("autoLockPressureLevel")];
    if ([pressure respondsToSelector:@selector(intValue)]) {
        int v = [pressure intValue];
        if (v == 10 || v == 20 || v == 30 || v == 40 || v == 50) gAutoLockPressureLevel = v;
    }
}

// 电池温度（摄氏）。AppleSmartBattery 的 Temperature 属性为 deci-Celsius。
static double CPUthermalAutoLockBatteryTempCelsius(void) {
    io_registry_entry_t entry = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (entry == IO_OBJECT_NULL) return -1.0;
    CFTypeRef temperature = IORegistryEntryCreateCFProperty(entry, CFSTR("Temperature"), kCFAllocatorDefault, 0);
    int raw = temperature ? [(__bridge NSNumber *)temperature intValue] : -1;
    if (temperature) CFRelease(temperature);
    IOObjectRelease(entry);
    if (raw <= 0) return -1.0;
    return raw > 2000 ? raw / 100.0 : raw / 10.0;
}

static void CPUthermalAutoLockRefreshLockState(void) {
    int token = 0;
    uint64_t state = 0;
    if (notify_register_check("com.apple.springboard.lockstate", &token) == NOTIFY_STATUS_OK) {
        if (notify_get_state(token, &state) == NOTIFY_STATUS_OK) gAutoLockDeviceLocked = (state == 1);
        notify_cancel(token);
    }
}

static void CPUthermalAutoLockLockScreen(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gAutoLockDeviceLocked) return;
        id springBoard = [%c(SpringBoard) sharedApplication];
        if ([springBoard respondsToSelector:@selector(_simulateLockButtonPress)])
            [springBoard _simulateLockButtonPress];
    });
}

static void CPUthermalAutoLockTick(void) {
    static int overheatStreak = 0;
    @autoreleasepool {
        if (gAutoLockEnabled && !gAutoLockDeviceLocked) {
            double tempC = CPUthermalAutoLockBatteryTempCelsius();
            int pressure = (int)CPUthermalGetPressureLevel();
            BOOL overheat = (tempC >= gAutoLockTempThreshold) || (pressure >= gAutoLockPressureLevel);
            if (overheat) {
                overheatStreak++;
                if (overheatStreak >= kAutoLockRequiredStreak &&
                    CFAbsoluteTimeGetCurrent() >= gAutoLockCooldownUntil) {
                    overheatStreak = 0;
                    gAutoLockCooldownUntil = CFAbsoluteTimeGetCurrent() + kAutoLockCooldown;
                    CPUthermalAutoLockLockScreen();
                }
            } else {
                overheatStreak = 0;
            }
        } else {
            overheatStreak = 0;
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAutoLockCheckInterval * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ CPUthermalAutoLockTick(); });
}

%ctor {
    @autoreleasepool {
        CPUthermalAutoLockReloadPrefs();
        notify_register_dispatch(kCPUthermalSettingsChangedNotifC, &gAutoLockSettingsToken,
                                 dispatch_get_main_queue(), ^(int token) {
            (void)token;
            CPUthermalAutoLockReloadPrefs();
        });
        // 锁屏状态变化时同步缓存，已锁定时不再触发
        notify_register_dispatch("com.apple.springboard.lockstate", &gAutoLockLockStateToken,
                                 dispatch_get_main_queue(), ^(int token) {
            (void)token;
            CPUthermalAutoLockRefreshLockState();
        });
        CPUthermalAutoLockRefreshLockState();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ CPUthermalAutoLockTick(); });
    }
}
