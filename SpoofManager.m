#import "SpoofManager.h"

@implementation SpoofConfig
@end

@interface SpoofManager ()
@property (nonatomic, strong) SpoofConfig *config;
@property (nonatomic, strong) NSDictionary *modelDatabase;
@end

@implementation SpoofManager

+ (instancetype)sharedManager {
    static SpoofManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[SpoofManager alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self buildModelDatabase];
        self.config = [[SpoofConfig alloc] init];
    }
    return self;
}

- (void)buildModelDatabase {
    // iPhone 6 到 iPhone 17 全系列型号数据库
    self.modelDatabase = @{
        // ===== iPhone 6 系列 (2014) =====
        @"iPhone7,2": @{@"name": @"iPhone 6", @"chip": @"A8", @"release": @"2014"},
        @"iPhone7,1": @{@"name": @"iPhone 6 Plus", @"chip": @"A8", @"release": @"2014"},

        // ===== iPhone 6s 系列 (2015) =====
        @"iPhone8,1": @{@"name": @"iPhone 6s", @"chip": @"A9", @"release": @"2015"},
        @"iPhone8,2": @{@"name": @"iPhone 6s Plus", @"chip": @"A9", @"release": @"2015"},
        @"iPhone8,4": @{@"name": @"iPhone SE (1st gen)", @"chip": @"A9", @"release": @"2016"},

        // ===== iPhone 7 系列 (2016) =====
        @"iPhone9,1": @{@"name": @"iPhone 7", @"chip": @"A10", @"release": @"2016"},
        @"iPhone9,3": @{@"name": @"iPhone 7", @"chip": @"A10", @"release": @"2016"},
        @"iPhone9,2": @{@"name": @"iPhone 7 Plus", @"chip": @"A10", @"release": @"2016"},
        @"iPhone9,4": @{@"name": @"iPhone 7 Plus", @"chip": @"A10", @"release": @"2016"},

        // ===== iPhone 8 系列 (2017) =====
        @"iPhone10,1": @{@"name": @"iPhone 8", @"chip": @"A11", @"release": @"2017"},
        @"iPhone10,4": @{@"name": @"iPhone 8 (Global)", @"chip": @"A11", @"release": @"2017"},
        @"iPhone10,2": @{@"name": @"iPhone 8 Plus", @"chip": @"A11", @"release": @"2017"},
        @"iPhone10,5": @{@"name": @"iPhone 8 Plus (Global)", @"chip": @"A11", @"release": @"2017"},

        // ===== iPhone X (2017) =====
        @"iPhone10,3": @{@"name": @"iPhone X", @"chip": @"A11", @"release": @"2017"},
        @"iPhone10,6": @{@"name": @"iPhone X (Global)", @"chip": @"A11", @"release": @"2017"},

        // ===== iPhone XS / XR 系列 (2018) =====
        @"iPhone11,2": @{@"name": @"iPhone XS", @"chip": @"A12", @"release": @"2018"},
        @"iPhone11,4": @{@"name": @"iPhone XS Max (Global)", @"chip": @"A12", @"release": @"2018"},
        @"iPhone11,6": @{@"name": @"iPhone XS Max", @"chip": @"A12", @"release": @"2018"},
        @"iPhone11,8": @{@"name": @"iPhone XR", @"chip": @"A12", @"release": @"2018"},

        // ===== iPhone 11 系列 (2019) =====
        @"iPhone12,1": @{@"name": @"iPhone 11", @"chip": @"A13", @"release": @"2019"},
        @"iPhone12,3": @{@"name": @"iPhone 11 Pro", @"chip": @"A13", @"release": @"2019"},
        @"iPhone12,5": @{@"name": @"iPhone 11 Pro Max", @"chip": @"A13", @"release": @"2019"},
        @"iPhone12,8": @{@"name": @"iPhone SE (2nd gen)", @"chip": @"A13", @"release": @"2020"},

        // ===== iPhone 12 系列 (2020) =====
        @"iPhone13,1": @{@"name": @"iPhone 12 mini", @"chip": @"A14", @"release": @"2020"},
        @"iPhone13,2": @{@"name": @"iPhone 12", @"chip": @"A14", @"release": @"2020"},
        @"iPhone13,3": @{@"name": @"iPhone 12 Pro", @"chip": @"A14", @"release": @"2020"},
        @"iPhone13,4": @{@"name": @"iPhone 12 Pro Max", @"chip": @"A14", @"release": @"2020"},

        // ===== iPhone 13 系列 (2021) =====
        @"iPhone14,4": @{@"name": @"iPhone 13 mini", @"chip": @"A15", @"release": @"2021"},
        @"iPhone14,5": @{@"name": @"iPhone 13", @"chip": @"A15", @"release": @"2021"},
        @"iPhone14,2": @{@"name": @"iPhone 13 Pro", @"chip": @"A15", @"release": @"2021"},
        @"iPhone14,3": @{@"name": @"iPhone 13 Pro Max", @"chip": @"A15", @"release": @"2021"},
        @"iPhone14,6": @{@"name": @"iPhone SE (3rd gen)", @"chip": @"A15", @"release": @"2022"},

        // ===== iPhone 14 系列 (2022) =====
        @"iPhone14,7": @{@"name": @"iPhone 14", @"chip": @"A15", @"release": @"2022"},
        @"iPhone14,8": @{@"name": @"iPhone 14 Plus", @"chip": @"A15", @"release": @"2022"},
        @"iPhone15,2": @{@"name": @"iPhone 14 Pro", @"chip": @"A16", @"release": @"2022"},
        @"iPhone15,3": @{@"name": @"iPhone 14 Pro Max", @"chip": @"A16", @"release": @"2022"},

        // ===== iPhone 15 系列 (2023) =====
        @"iPhone15,4": @{@"name": @"iPhone 15", @"chip": @"A16", @"release": @"2023"},
        @"iPhone15,5": @{@"name": @"iPhone 15 Plus", @"chip": @"A16", @"release": @"2023"},
        @"iPhone16,1": @{@"name": @"iPhone 15 Pro", @"chip": @"A17 Pro", @"release": @"2023"},
        @"iPhone16,2": @{@"name": @"iPhone 15 Pro Max", @"chip": @"A17 Pro", @"release": @"2023"},

        // ===== iPhone 16 系列 (2024) =====
        @"iPhone17,3": @{@"name": @"iPhone 16", @"chip": @"A18", @"release": @"2024"},
        @"iPhone17,4": @{@"name": @"iPhone 16 Plus", @"chip": @"A18", @"release": @"2024"},
        @"iPhone17,1": @{@"name": @"iPhone 16 Pro", @"chip": @"A18 Pro", @"release": @"2024"},
        @"iPhone17,2": @{@"name": @"iPhone 16 Pro Max", @"chip": @"A18 Pro", @"release": @"2024"},
        @"iPhone17,5": @{@"name": @"iPhone 16e", @"chip": @"A18", @"release": @"2025"},

        // ===== iPhone 17 系列 (2025) =====
        @"iPhone18,3": @{@"name": @"iPhone 17", @"chip": @"A19", @"release": @"2025"},
        @"iPhone18,4": @{@"name": @"iPhone Air", @"chip": @"A19 Pro", @"release": @"2025"},
        @"iPhone18,1": @{@"name": @"iPhone 17 Pro", @"chip": @"A19 Pro", @"release": @"2025"},
        @"iPhone18,2": @{@"name": @"iPhone 17 Pro Max", @"chip": @"A19 Pro", @"release": @"2025"},
        @"iPhone18,5": @{@"name": @"iPhone 17e", @"chip": @"A19", @"release": @"2026"},
    };
}

- (void)loadConfig {
    NSString *configPath = @"/var/mobile/Library/DeviceSpoofPro/config.plist";
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:configPath];

    if (dict) {
        self.config.modelIdentifier = dict[@"modelIdentifier"] ?: @"iPhone15,2";
        self.config.serialNumber = dict[@"serialNumber"] ?: [self generateSerialNumber];
        self.config.udid = dict[@"udid"] ?: [self generateUDID];
        self.config.imei = dict[@"imei"] ?: [self generateIMEI];
    } else {
        // 默认：伪装成 iPhone 14 Pro
        self.config.modelIdentifier = @"iPhone15,2";
        self.config.serialNumber = [self generateSerialNumber];
        self.config.udid = [self generateUDID];
        self.config.imei = [self generateIMEI];
    }

    NSDictionary *modelInfo = self.modelDatabase[self.config.modelIdentifier];
    self.config.deviceName = modelInfo[@"name"] ?: @"iPhone";
    self.config.wifiAddress = [self generateMACAddress];
    self.config.bluetoothAddress = [self generateMACAddress];
}

- (SpoofConfig *)currentConfig { return self.config; }

- (BOOL)switchToModel:(NSString *)modelIdentifier {
    if (!self.modelDatabase[modelIdentifier]) return NO;
    self.config.modelIdentifier = modelIdentifier;
    self.config.deviceName = self.modelDatabase[modelIdentifier][@"name"];
    self.config.serialNumber = [self generateSerialNumber];
    self.config.udid = [self generateUDID];
    self.config.imei = [self generateIMEI];
    return YES;
}

- (NSDictionary *)allSupportedModels { return self.modelDatabase; }

#pragma mark - 生成器函数
- (NSString *)generateSerialNumber {
    NSString *chars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *serial = [NSMutableString stringWithCapacity:12];
    for (int i = 0; i < 12; i++) {
        [serial appendFormat:@"%c", [chars characterAtIndex:arc4random_uniform((uint32_t)chars.length)]];
    }
    return serial;
}

- (NSString *)generateUDID {
    NSMutableString *udid = [NSMutableString stringWithCapacity:40];
    for (int i = 0; i < 40; i++) {
        [udid appendFormat:@"%x", arc4random_uniform(16)];
    }
    return udid;
}

- (NSString *)generateIMEI {
    NSMutableString *imei = [NSMutableString stringWithCapacity:15];
    for (int i = 0; i < 15; i++) {
        [imei appendFormat:@"%d", arc4random_uniform(10)];
    }
    return imei;
}

- (NSString *)generateMACAddress {
    NSMutableString *mac = [NSMutableString stringWithCapacity:17];
    for (int i = 0; i < 6; i++) {
        if (i > 0) [mac appendString:@":"];
        [mac appendFormat:@"%02X", arc4random_uniform(256)];
    }
    return mac;
}

@end
