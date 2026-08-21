#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import <dlfcn.h>

@interface Injector : NSObject
+ (void)load;
+ (void)setupUI;
+ (void)showMenu;
+ (void)exportAccount;
+ (void)importAccount;
+ (void)shareFile:(NSString *)path;
+ (NSData *)dumpKeychain;
+ (void)restoreKeychain:(NSData *)data;
+ (UIViewController *)topViewController;
@end

@implementation Injector

+ (void)load {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [Injector setupUI];
    });
}

#pragma mark - UI

+ (void)setupUI {
    UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.windowLevel = UIWindowLevelAlert + 1;
    window.backgroundColor = [UIColor clearColor];
    window.userInteractionEnabled = YES;
    window.rootViewController = [[UIViewController alloc] init];
    window.hidden = NO;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(20, 100, 80, 40);
    [button setTitle:@"备份" forState:UIControlStateNormal];
    button.backgroundColor = [UIColor whiteColor];
    button.layer.cornerRadius = 8;
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOpacity = 0.5;
    button.layer.shadowOffset = CGSizeMake(2, 2);
    button.tintColor = [UIColor blackColor];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [button addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:button];

    // 添加拖拽手势
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [button addGestureRecognizer:pan];

    objc_setAssociatedObject([UIApplication sharedApplication], @"injectorWindow", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIButton *btn = (UIButton *)gesture.view;
    CGPoint translation = [gesture translationInView:btn.superview];
    btn.center = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:btn.superview];
}

+ (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"账号管理"
                                                                   message:@"选择操作"
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

    // 清理旧的临时目录
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

    // 导出 Keychain 数据（dylib 在进程内运行，有直接 Keychain 访问权限）
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
    system([cmd UTF8String]);

    // 清理临时目录
    [[NSFileManager defaultManager] removeItemAtPath:exportDir error:nil];

    // 弹窗提示 + 分享
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
        // 没有备份文件，弹出文件选择器让用户选择
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.zip-archive"] inMode:UIDocumentPickerModeImport];
        picker.delegate = (id<UIDocumentPickerDelegate>)self;
        picker.allowsMultipleSelection = NO;
        // 用 block 关联
        objc_setAssociatedObject(picker, @"importCallback", ^(NSString *selectedPath) {
            [Injector doImportFromPath:selectedPath];
        }, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [[Injector topViewController] presentViewController:picker animated:YES completion:nil];
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
    system([cmd UTF8String]);

    // 覆盖沙盒文件
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

    // 清理
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
    if (status != errSecSuccess || !result) {
        return nil;
    }

    NSArray *items = (__bridge_transfer NSArray *)result;
    NSMutableArray *exportList = [NSMutableArray array];

    for (NSDictionary *item in items) {
        NSString *service = item[(__bridge id)kSecAttrService];
        NSString *account = item[(__bridge id)kSecAttrAccount];
        NSData *data = item[(__bridge id)kSecValueData];

        if (service && account && data) {
            // 导出所有 keychain 条目（在游戏进程内，这些基本都是游戏自己的）
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

        // 先删除旧条目
        NSDictionary *delQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: service,
            (__bridge id)kSecAttrAccount: account
        };
        SecItemDelete((__bridge CFDictionaryRef)delQuery);

        // 添加新条目
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
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

@end
