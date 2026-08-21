#import <Foundation/Foundation.h>

@interface KeychainHelper : NSObject
+ (void)clearAllItemsForService:(NSString *)service;
+ (BOOL)deleteItemForService:(NSString *)service account:(NSString *)account;
@end
