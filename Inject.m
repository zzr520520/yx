#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import <spawn.h>
#import "SSZipArchive.h"
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 140000
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

// 前向声明
@class Injector;

// 双指双击手势
@interface TwoFingerDoubleTap : UITapGestureRecognizer @end
@implementation TwoFingerDoubleTap @end

// 文件选择器代理（实例对象，不能用类方法做 delegate）
@interface DocPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, copy) void (^onPicked)(NSString *path);
@end

@implementation DocPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    // 安全访问 -> 复制 -> 释放（顺序不能错）
    [url startAccessingSecurityScopedResource];
    NSString *tmpZip = [NSTemporaryDirectory() stringByAppendingPathComponent:@"picked_import.zip"];
    [[NSFileManager defaultManager] removeItemAtPath:tmpZip error:nil];
    NSError *err;
    [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:tmpZip] error:&err];
    [url stopAccessingSecurityScopedResource];
    if (err) {
        NSLog(@"[Injector] 复制选中文件失败: %@", err);
        return;
    }
    if (self.onPicked) self.onPicked(tmpZip);
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [url startAccessingSecurityScopedResource];
    NSString *tmpZip = [NSTemporaryDirectory() stringByAppendingPathComponent:@"picked_import.zip"];
    [[NSFileManager defaultManager] removeItemAtPath:tmpZip error:nil];
    [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:tmpZip] error:nil];
    [url stopAccessingSecurityScopedResource];
    if (self.onPicked) self.onPicked(tmpZip);
}
@end

// 进度 HUD 视图
@interface ProgressHUD : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *percentLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
+ (instancetype)shared;
- (void)showWithTitle:(NSString *)title;
- (void)updateProgress:(double)progress;
- (void)hide;
@end

@implementation ProgressHUD

+ (instancetype)shared {
    static ProgressHUD *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ProgressHUD alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super initWithFrame:CGRectMake(0, 0, 200, 90)];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        self.layer.cornerRadius = 14;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 12, 200, 22)];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:_titleLabel];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _spinner.center = CGPointMake(100, 45);
        [self addSubview:_spinner];

        _percentLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 65, 200, 20)];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        _percentLabel.textColor = [UIColor whiteColor];
        _percentLabel.font = [UIFont systemFontOfSize:14];
        _percentLabel.text = @"0%";
        [self addSubview:_percentLabel];
    }
    return self;
}

- (void)showWithTitle:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = [Injector getKeyWindow];
        if (!win) return;
        self.center = win.center;
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.8, 0.8);
        [win addSubview:self];
        self.titleLabel.text = title;
        self.percentLabel.text = @"0%";
        [self.spinner startAnimating];
        [UIView animateWithDuration:0.25 animations:^{
            self.alpha = 1;
            self.transform = CGAffineTransformIdentity;
        }];
    });
}

- (void)updateProgress:(double)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        int percent = (int)(progress * 100);
        self.percentLabel.text = [NSString stringWithFormat:@"%d%%", percent];
    });
}

- (void)hide {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating];
        [UIView animateWithDuration:0.25 animations:^{
            self.alpha = 0;
            self.transform = CGAffineTransformMakeScale(0.8, 0.8);
        } completion:^(BOOL finished) {
            [self removeFromSuperview];
        }];
    });
}

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
+ (void)showAlert:(NSString *)title message:(NSString *)msg;
@end

@implementation Injector

+ (void)load {
    NSLog(@"[Injector] dylib loaded, waiting for app launch...");
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        NSLog(@"[Injector] App did finish launching, scheduling UI setup");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [Injector onAppDidLaunch];
        });
    }];
}

#pragma mark - 手势注册

+ (void)onAppDidLaunch {
    [Injector addGestureToWindow];
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
    NSNumber *token = objc_getAssociatedObject(keyWindow, @"injectorGestureAdded");
    if ([token boolValue]) return;

    TwoFingerDoubleTap *tap = [[TwoFingerDoubleTap alloc] initWithTarget:self action:@selector(showMenu)];
    tap.numberOfTapsRequired = 2;
    tap.numberOfTouchesRequired = 2;
    tap.cancelsTouchesInView = NO;
    [keyWindow addGestureRecognizer:tap];

    objc_setAssociatedObject(keyWindow, @"injectorGestureAdded", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[Injector] ✅ 双指双击手势已添加到 keyWindow");
}

+ (UIWindow *)getKeyWindow {
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
    UIWindow *kw = [UIApplication sharedApplication].keyWindow;
    if (kw) return kw;
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

#pragma mark - 导出（SSZipArchive + 进度百分比）

+ (void)exportAccount {
    [[ProgressHUD shared] showWithTitle:@"导出中..."];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
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

        // 导出 Keychain
        NSData *keychainData = [self dumpKeychain];
        if (keychainData) {
            NSString *kcPath = [exportDir stringByAppendingPathComponent:@"keychain.json"];
            [keychainData writeToFile:kcPath atomically:YES];
            NSLog(@"[Injector] Keychain 导出成功");
        }

        // 使用 SSZipArchive 压缩（带进度回调）
        NSString *zipPath = [docPath stringByAppendingPathComponent:@"account_backup.zip"];
        [[NSFileManager defaultManager] removeItemAtPath:zipPath error:nil];

        BOOL success = [SSZipArchive createZipFileAtPath:zipPath
                                 withContentsOfDirectory:exportDir
                                     keepParentDirectory:NO
                                       compressionLevel:-1
                                               password:nil
                                                    AES:NO
                                         progressHandler:^(NSUInteger entryNumber, NSUInteger total) {
            if (total > 0) {
                double progress = (double)entryNumber / (double)total;
                [[ProgressHUD shared] updateProgress:progress];
            }
        }];

        [[NSFileManager defaultManager] removeItemAtPath:exportDir error:nil];
        [[ProgressHUD shared] hide];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success || ![[NSFileManager defaultManager] fileExistsAtPath:zipPath]) {
                [Injector showAlert:@"导出失败" message:@"压缩失败，请重试"];
                return;
            }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出完成"
                                                                           message:[NSString stringWithFormat:@"备份已保存:\n%@\n\n点击分享导出", zipPath]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"分享文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [Injector shareFile:zipPath];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [[Injector topViewController] presentViewController:alert animated:YES completion:nil];
        });
    });
}

#pragma mark - 导入（文件选择器 + SSZipArchive 进度）

+ (void)importAccount {
    NSString *docPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString *zipPath = [docPath stringByAppendingPathComponent:@"account_backup.zip"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入账号数据"
                                                                   message:@"选择导入方式"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if ([[NSFileManager defaultManager] fileExistsAtPath:zipPath]) {
        [alert addAction:[UIAlertAction actionWithTitle:@"使用 Documents 下的备份" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [Injector doImportFromPath:zipPath];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"从文件 App 选择 .zip" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIDocumentPickerViewController *picker;
            if (@available(iOS 14.0, *)) {
                picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.zip-archive"]]];
            } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.zip-archive"] inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
            }
            picker.allowsMultipleSelection = NO;

            DocPickerDelegate *delegate = [[DocPickerDelegate alloc] init];
            delegate.onPicked = ^(NSString *path) {
                [Injector doImportFromPath:path];
            };
            picker.delegate = delegate;
            objc_setAssociatedObject(picker, @"pickerDelegate", delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [[Injector topViewController] presentViewController:picker animated:YES completion:nil];
        });
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [[Injector topViewController] presentViewController:alert animated:YES completion:nil];
}

+ (void)doImportFromPath:(NSString *)zipPath {
    [[ProgressHUD shared] showWithTitle:@"导入中..."];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *home = NSHomeDirectory();
        NSString *tmpDir = NSTemporaryDirectory();
        NSString *extractDir = [tmpDir stringByAppendingPathComponent:@"import_backup"];

        [[NSFileManager defaultManager] removeItemAtPath:extractDir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:extractDir withIntermediateDirectories:YES attributes:nil error:nil];

        // 使用 SSZipArchive 解压（带进度回调）
        BOOL success = [SSZipArchive unzipFileAtPath:zipPath
                                       toDestination:extractDir
                                           overwrite:YES
                                            password:nil
                                      progressHandler:^(NSString *entry, unz_file_info zipInfo, long entryNumber, long total) {
            if (total > 0) {
                double progress = (double)entryNumber / (double)total;
                [[ProgressHUD shared] updateProgress:progress];
            }
        }
                                    completionHandler:^(NSString *path, BOOL succeeded, NSError * _Nullable error) {
            NSLog(@"[Injector] 解压完成: succeeded=%d", succeeded);
        }];

        [[ProgressHUD shared] hide];

        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [Injector showAlert:@"导入失败" message:@"解压 ZIP 失败，请确认文件格式正确"];
            });
            [[NSFileManager defaultManager] removeItemAtPath:extractDir error:nil];
            return;
        }

        NSArray *items = @[@"Documents", @"Preferences", @"Application Support"];
        for (NSString *item in items) {
            NSString *src = [extractDir stringByAppendingPathComponent:item];
            if (![[NSFileManager defaultManager] fileExistsAtPath:src]) continue;

            NSString *dest;
            if ([item isEqualToString:@"Documents"]) {
                dest = [home stringByAppendingPathComponent:@"Documents"];
            } else {
                dest = [home stringByAppendingPathComponent:[NSString stringWithFormat:@"Library/%@", item]];
            }
            [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:src toPath:dest error:nil];
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

        dispatch_async(dispatch_get_main_queue(), ^{
            [Injector showAlert:@"导入完成" message:@"账号数据已恢复，请重启游戏生效"];
        });
    });
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

+ (void)showAlert:(NSString *)title message:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [[Injector topViewController] presentViewController:alert animated:YES completion:nil];
    });
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
