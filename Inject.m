#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import <spawn.h>

// 自定义手势：双指双击
@interface TwoFingerDoubleTap : UITapGestureRecognizer
@end

@implementation TwoFingerDoubleTap
@end

@interface Injector : NSObject
+ (void)load;
+ (void)onAppDidLaunch;
+ (void)addGestureToWindow;
+ (void)showMenu;
+ (void)exportAccount;
+ (void)importAccount;
+ (void)doImportFromPath:(NSString *)zipPath;
+ (void)shareFile:(NSString *)path;
+ (NSData *)dumpKeychain;
+ (void)restoreKeychain:(NSData *)data;
+ (UIViewController *)topViewController;
+ (UIWindow *)getKeyWindow;
+ (int)runCommand:(NSString *)command;
@end

@implementation Injector

+ (void)load {
    NSLog(@"[Injector] dylib loaded, waiting for app launch...");
    // 监听 App 完全启动通知（比 +load 延迟可靠得多）
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[Injector] App did finish launching, scheduling UI setup");
        // 延迟 2 秒，确保游戏 rootViewController 和 keyWindow 完全就绪
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [Injector onAppDidLaunch];
        });
    }];
}

#pragma mark - 手势注册

+ (void)onAppDidLaunch {
    [Injector addGestureToWindow];

    // 持续监听 keyWindow 变化（游戏可能重建 window）
    [NSNotificationCenter.defaultCenter addObserverForName:UISceneDidActivateNotification
                                                   object:nil
                                                    queue:[NSOperationQueue mainQueue]
                                               usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [Injector addGestureToWindow];
        });
    }];
}

+ (void)addGestureToWindow {
    UIWindow *keyWindow = [Injector getKeyWindow];
    if (!keyWindow) {
        NSLog(@"[Injector] keyWindow not found, retrying...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [Injector addGestureToWindow];
        });
        return;
    }

    // 防止重复添加
    NSNumber *token = objc_getAssociatedObject(keyWindow, @"injectorGestureAdded");
    if ([token boolValue]) {
        return;
    }

    // 双指双击手势
    TwoFingerDoubleTap *tap = [[TwoFingerDoubleTap alloc] initWithTarget:self action:@selector(showMenu)];
    tap.numberOfTapsRequired = 2;      // 双击
    tap.numberOfTouchesRequired = 2;   // 双指
    tap.cancelsTouchesInView = NO;     // 不拦截游戏触摸
    [keyWindow addGestureRecognizer:tap];

    objc_setAssociatedObject(keyWindow, @"injectorGestureAdded", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[Injector] ✅ 双指双击手势已添加到 keyWindow");
}

+ (UIWindow *)getKeyWindow {
    // iOS 13+: 优先用 UIWindowScene
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (!w.hidden && w.alpha > 0) return w;
                }
            }
        }
    }
    // Fallback: iOS 12 及以下
    UIWindow *kw = [UIApplication sharedApplication].keyWindow;
    if (kw) return kw;
    // 最终兜底
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w.hidden && w.alpha > 0) return w;
    }
    return nil;
}

#pragma mark - 菜单

+ (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"账号管理"
                                                                   message:@"双指双击触发\n选择操作"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"📤 导出账号数据" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [Injector exportAccount];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"📥 导入账号数据" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [Injector importAccount];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"❌ 取消" style:UIAlertActionStyleCancel handler:nil]];

    [[Injector topViewController] presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 导出

+ (void)exportAccount {
    NSString *home = NSHomeDirectory();
    NSString *docPath = [home stringByAppendingPathComponent:@"Documents"];
    NSString *prefPath = [home stringByAppendingPathComponent:@"Library/Preferences"];
    NSString *appSupportPath = [home stringByAppendingPathComponent:@"Library/Application Support"];

    NSString *tmpDir = NSTemporaryDirectory();
    NSString *exportDir = [tmpDir stringByAppendingPathComponent:@"export_backup"];

    [[NSFileManager defaultManager] removeItemAtPath:exportDir error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:exportDir withIntermediateDirectories:YES attributes:nil error:nil];

    // 复制需要备份的目录
    NSArray *paths = @[docPath, prefPath, appSupportPath];
    NSArray *names = @[@"Documents", @"Preferences", @"Application Support"];

    for (int i = 0; i < paths.count; i++) {
        NSString *src = paths[i];
        if ([[NSFileManager defaultManager] fileExistsAtPath:src]) {
            NSString *dest = [exportDir stringByAppendingPathComponent:names[i]];
            NSError *err;
            [[NSFileManager defaultManager] copyItemAtPath:src toPath:dest error:&err];
            if (err) NSLog(@"[Injector] 复制 %@ 失败: %@", src, err);
        }
    }

    // 导出 Keychain 数据
    NSData *keychainData = [self dumpKeychain];
    if (keychainData) {
        NSString *kcPath = [exportDir stringByAppendingPathComponent:@"keychain.json"];
        [keychainData writeToFile:kcPath atomically:YES];
        NSLog(@"[Injector] Keychain 导出成功");
    }

    // 打包为 zip
    NSString *zipPath = [docPath stringByAppendingPathComponent:@"account_backup.zip"];
    [[NSFileManager defaultManager] removeItemAtPath:zipPath error:nil];

    NSString *cmd = [NSString stringWithFormat:@"cd \"%@\" && /usr/bin/zip -r \"%@\" . 2>&1", exportDir, zipPath];
    [Injector runCommand:cmd];

    [[NSFileManager defaultManager] removeItemAtPath:exportDir error:nil];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出完成"
                                                                   message:[NSString stringWithFormat:@"备份已保存:\n%@\n\n点击分享导出文件", zipPath]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"分享文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [Injector shareFile:zipPath];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [[Injector topViewController] presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 导入

+ (void)importAccount {
    NSString *home = NSHomeDirectory();
    NSString *docPath = [home stringByAppendingPathComponent:@"Documents"];
    NSString *zipPath = [docPath stringByAppendingPathComponent:@"account_backup.zip"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:zipPath]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未找到备份"
                                                                       message:@"请将 account_backup.zip 放入游戏 Documents 目录\n或通过分享导入"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [[Injector topViewController] presentViewController:alert animated:YES completion:nil];
        return;
    }

    [Injector doImportFromPath:zipPath];
}

+ (void)doImportFromPath:(NSString *)zipPath {
    NSString *home = NSHomeDirectory();
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *extractDir = [tmpDir stringByAppendingPathComponent:@"import_backup"];

    [[NSFileManager defaultManager] removeItemAtPath:extractDir error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:extractDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *cmd = [NSString stringWithFormat:@"/usr/bin/unzip -o \"%@\" -d \"%@\" 2>&1", zipPath, extractDir];
    [Injector runCommand:cmd];

    NSArray *items = @[@"Documents", @"Preferences", @"Application Support"];
    for (NSString *item in items) {
        NSString *src = [extractDir stringByAppendingPathComponent:item];
        if ([[NSFileManager defaultManager] fileExistsAtPath:src]) {
            NSString *dest;
            if ([item isEqualToString:@"Documents"]) {
                dest = [home stringByAppendingPathComponent:@"Documents"];
            } else {
                dest = [home stringByAppendingPathComponent:[NSString stringWithFormat:@"Library/%@", item]];
            }
            [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:src toPath:dest error:nil];
        }
    }

    // 恢复 Keychain
    NSString *kcPath = [extractDir stringByAppendingPathComponent:@"keychain.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:kcPath]) {
        NSData *kcData = [NSData dataWithContentsOfFile:kcPath];
        if (kcData) {
            [Injector restoreKeychain:kcData];
            NSLog(@"[Injector] Keychain 恢复成功");
        }
    }

    [[NSFileManager defaultManager] removeItemAtPath:extractDir error:nil];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入完成"
                                                                   message:@"账号数据已恢复，请重启游戏生效"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [[Injector topViewController] presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 分享

+ (void)shareFile:(NSString *)path {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];

        UIViewController *topVC = [Injector topViewController];
        if ([activityVC respondsToSelector:@selector(popoverPresentationController)]) {
            activityVC.popoverPresentationController.sourceView = topVC.view;
            activityVC.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width / 2, topVC.view.bounds.size.height / 2, 0, 0);
        }
        [topVC presentViewController:activityVC animated:YES completion:nil];
    });
}

#pragma mark - Keychain

+ (NSData *)dumpKeychain {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecReturnData: @YES
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;

    NSArray *items = (__bridge_transfer NSArray *)result;
    NSMutableArray *exportList = [NSMutableArray array];

    for (NSDictionary *item in items) {
        NSString *service = item[(__bridge id)kSecAttrService];
        NSString *account = item[(__bridge id)kSecAttrAccount];
        NSData *data = item[(__bridge id)kSecValueData];

        if (service && account && data) {
            [exportList addObject:@{
                @"service": service,
                @"account": account,
                @"data": [data base64EncodedStringWithOptions:0]
            }];
        }
    }

    if (exportList.count == 0) return nil;
    return [NSJSONSerialization dataWithJSONObject:exportList options:NSJSONWritingPrettyPrinted error:nil];
}

+ (void)restoreKeychain:(NSData *)data {
    NSArray *list = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![list isKindOfClass:[NSArray class]]) return;

    for (NSDictionary *item in list) {
        NSString *service = item[@"service"];
        NSString *account = item[@"account"];
        NSString *base64 = item[@"data"];
        if (!service || !account || !base64) continue;

        NSData *valueData = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
        if (!valueData) continue;

        NSDictionary *delQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: service,
            (__bridge id)kSecAttrAccount: account
        };
        SecItemDelete((__bridge CFDictionaryRef)delQuery);

        NSDictionary *addQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: service,
            (__bridge id)kSecAttrAccount: account,
            (__bridge id)kSecValueData: valueData
        };
        SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    }
}

#pragma mark - 工具方法

+ (UIViewController *)topViewController {
    UIWindow *keyWindow = [Injector getKeyWindow];
    UIViewController *rootVC = keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

+ (int)runCommand:(NSString *)command {
    const char *cmd = [command UTF8String];
    char *argv[] = {"sh", "-c", (char *)cmd, NULL};
    char *envp[] = {NULL};
    pid_t pid = 0;
    int ret = posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, envp);
    if (ret != 0) return ret;
    if (pid > 0) {
        int status = 0;
        waitpid(pid, &status, 0);
        return status;
    }
    return -1;
}

@end
