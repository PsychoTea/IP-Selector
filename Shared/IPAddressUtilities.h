#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *_Nullable IPNormalizedMAC(NSString *_Nullable value);
FOUNDATION_EXPORT NSString *_Nullable IPSubnetMask(NSString *value);
FOUNDATION_EXPORT BOOL IPValidIPv4(NSString *value);
FOUNDATION_EXPORT BOOL IPValidUnicastIPv4(NSString *value);
FOUNDATION_EXPORT BOOL IPValidDNSAddress(NSString *value);
NS_ASSUME_NONNULL_END
