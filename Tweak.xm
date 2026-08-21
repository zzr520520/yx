#import <Foundation/Foundation.h>
#import <substrate.h>
#import "fishhook.h"
#import <CoreMotion/CoreMotion.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import "SpoofManager.h"
#import "KeychainHelper.h"

// ========== 混淆 Key 映射表 ==========
static NSDictionary *obfuscatedKeyMap(void) {
    return @{
        // 明文 Key（兼容旧 App）
        @"SerialNumber" : @"F17LXYZ98765",
        @"ProductType"  : @"iPhone15,2",
        @"UniqueDeviceID" : @"00000000-0000-0000-0000-000000000000",
        // 混淆 Key（iOS 17 真实设备 dump 所得，需持续更新）
        @"5MSZn7w3nnJp22VbpqaxLQ" : @"F17LXYZ98765",
        @"h9jO5K8P2sLx4qWr" : @"iPhone15,2",
        @"9n6V5t3R1xZ7aC2e" : @"00000000-0000-0000-0000-000000000000",
        @"yX2yA91fH6kX1bX7" : @"00:11:22:33:44:55",
        @"zX2yA91fH6kX1bX8" : @"00:11:22:33:44:66",
    };
}

// ========== fishhook 拦截 MGCopyAnswer ==========
static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key);
static CFTypeRef hooked_MGCopyAnswer(CFStringRef key) {
    if (!key) return orig_MGCopyAnswer(key);

    NSString *keyStr = (__bridge NSString *)key;
    NSString *fakeValue = obfuscatedKeyMap()[keyStr];

    if (fakeValue) {
        // 返回 +1 retain 的 CF 对象，调用方负责释放
        return CFStringCreateWithCString(NULL, [fakeValue UTF8String], kCFStringEncodingUTF8);
    }
    return orig_MGCopyAnswer(key);
}

// ========== fishhook 拦截 sysctl ==========
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int hooked_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    SpoofConfig *config = [[SpoofManager sharedManager] currentConfig];
    if (namelen >= 2 && name[0] == CTL_HW && (name[1] == HW_MACHINE || name[1] == HW_MODEL)) {
        if (oldp && oldlenp) {
            const char *fake = [config.modelIdentifier UTF8String];
            size_t len = strlen(fake) + 1;
            if (*oldlenp >= len) {
                memcpy(oldp, fake, len);
                *oldlenp = len;
                return 0;
            }
        }
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

// ========== fishhook 拦截 uname ==========
static int (*orig_uname)(struct utsname *);
static int hooked_uname(struct utsname *name) {
    int ret = orig_uname(name);
    if (ret == 0 && name) {
        SpoofConfig *config = [[SpoofManager sharedManager] currentConfig];
        strcpy(name->machine, [config.modelIdentifier UTF8String]);
        strcpy(name->nodename, "iPhone");
    }
    return ret;
}

// ========== CMGyroData rotationRate Getter 替换 ==========
static CMRotationRate (*orig_rotationRate)(id, SEL);
static CMRotationRate hooked_rotationRate(id self, SEL _cmd) {
    CMRotationRate rate = orig_rotationRate(self, _cmd);
    // 注入符合物理规律的微小扰动
    rate.x += (double)(arc4random() % 2000 - 1000) / 1000000.0;
    rate.y += (double)(arc4random() % 2000 - 1000) / 1000000.0;
    rate.z += (double)(arc4random() % 3000 - 1500) / 1000000.0;
    return rate;
}

// ========== 初始化入口 ==========
__attribute__((constructor)) static void entry() {
    @autoreleasepool {
        // 1. 加载配置
        [[SpoofManager sharedManager] loadConfig];

        // 2. fishhook 重绑定 C 符号
        struct rebinding rebindings[] = {
            {"MGCopyAnswer", (void *)hooked_MGCopyAnswer, (void **)&orig_MGCopyAnswer},
            {"sysctl", (void *)hooked_sysctl, (void **)&orig_sysctl},
            {"uname", (void *)hooked_uname, (void **)&orig_uname}
        };
        rebind_symbols(rebindings, 3);

        // 3. Hook CMGyroData.rotationRate
        Class gyroClass = NSClassFromString(@"CMGyroData");
        if (gyroClass) {
            SEL sel = @selector(rotationRate);
            Method m = class_getInstanceMethod(gyroClass, sel);
            if (m) {
                orig_rotationRate = (void *)method_getImplementation(m);
                method_setImplementation(m, (IMP)hooked_rotationRate);
            }
        }

        // 4. 清理 Keychain（传入 nil 清理所有，或指定 Bundle ID）
        // [KeychainHelper clearAllItemsForService:@"com.tencent.xin"];
        [KeychainHelper clearAllItemsForService:nil];

        NSLog(@"DeviceSpoofPro v3.0 loaded with full iPhone 6-17 database.");
    }
}
