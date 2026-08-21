#import <Foundation/Foundation.h>

@interface SpoofConfig : NSObject
@property (nonatomic, strong) NSString *serialNumber;
@property (nonatomic, strong) NSString *modelIdentifier;   // iPhone15,2
@property (nonatomic, strong) NSString *deviceName;        // iPhone 14 Pro
@property (nonatomic, strong) NSString *udid;
@property (nonatomic, strong) NSString *imei;
@property (nonatomic, strong) NSString *wifiAddress;
@property (nonatomic, strong) NSString *bluetoothAddress;
@end

@interface SpoofManager : NSObject
+ (instancetype)sharedManager;
- (void)loadConfig;
- (BOOL)saveConfig;
+ (NSString *)configPath;
- (SpoofConfig *)currentConfig;
- (BOOL)switchToModel:(NSString *)modelIdentifier;
- (NSDictionary *)allSupportedModels;  // 返回完整型号数据库
@end
