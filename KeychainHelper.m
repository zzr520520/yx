#import "KeychainHelper.h"
#import <Security/Security.h>

@implementation KeychainHelper

+ (void)clearAllItemsForService:(NSString *)service {
    // 清理 GenericPassword 类型
    NSMutableDictionary *query = [@{
        (id)kSecClass : (id)kSecClassGenericPassword,
        (id)kSecMatchLimit : (id)kSecMatchLimitAll,
        (id)kSecReturnAttributes : @YES
    } mutableCopy];
    if (service) query[(id)kSecAttrService] = service;

    CFArrayRef result = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status == errSecSuccess && result) {
        NSArray *items = (__bridge NSArray *)result;
        for (NSDictionary *item in items) {
            NSMutableDictionary *delQuery = [NSMutableDictionary dictionary];
            delQuery[(id)kSecClass] = (id)kSecClassGenericPassword;
            if (item[(id)kSecAttrService]) delQuery[(id)kSecAttrService] = item[(id)kSecAttrService];
            if (item[(id)kSecAttrAccount]) delQuery[(id)kSecAttrAccount] = item[(id)kSecAttrAccount];
            if (item[(id)kSecAttrAccessGroup]) delQuery[(id)kSecAttrAccessGroup] = item[(id)kSecAttrAccessGroup];
            SecItemDelete((CFDictionaryRef)delQuery);
        }
        CFRelease(result);
    }

    // 清理 InternetPassword 类型
    NSMutableDictionary *inetQuery = [@{
        (id)kSecClass : (id)kSecClassInternetPassword,
        (id)kSecMatchLimit : (id)kSecMatchLimitAll,
        (id)kSecReturnAttributes : @YES
    } mutableCopy];
    if (service) inetQuery[(id)kSecAttrServer] = service;

    CFArrayRef inetResult = NULL;
    if (SecItemCopyMatching((CFDictionaryRef)inetQuery, (CFTypeRef *)&inetResult) == errSecSuccess && inetResult) {
        NSArray *items = (__bridge NSArray *)inetResult;
        for (NSDictionary *item in items) {
            NSMutableDictionary *delQuery = [NSMutableDictionary dictionary];
            delQuery[(id)kSecClass] = (id)kSecClassInternetPassword;
            if (item[(id)kSecAttrServer]) delQuery[(id)kSecAttrServer] = item[(id)kSecAttrServer];
            if (item[(id)kSecAttrAccount]) delQuery[(id)kSecAttrAccount] = item[(id)kSecAttrAccount];
            SecItemDelete((CFDictionaryRef)delQuery);
        }
        CFRelease(inetResult);
    }
}

+ (BOOL)deleteItemForService:(NSString *)service account:(NSString *)account {
    NSDictionary *query = @{
        (id)kSecClass : (id)kSecClassGenericPassword,
        (id)kSecAttrService : service,
        (id)kSecAttrAccount : account,
    };
    return SecItemDelete((CFDictionaryRef)query) == errSecSuccess;
}

@end
