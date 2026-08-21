#import <Foundation/Foundation.h>

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier; // Bundle ID
@property (nonatomic, readonly) NSString *localizedName;         // App显示名称
@property (nonatomic, readonly) NSURL *bundleURL;               // 安装包路径
@property (nonatomic, readonly) NSURL *dataContainerURL;        // 沙盒数据路径
@property (nonatomic, readonly) NSString *applicationType;       // User / System
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
- (NSArray<LSApplicationProxy *> *)allApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end
