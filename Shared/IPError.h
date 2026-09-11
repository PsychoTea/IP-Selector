#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const IPErrorDomain;
FOUNDATION_EXPORT NSError *IPError(NSString *message);
FOUNDATION_EXPORT BOOL IPValidationFailure(NSError **error, NSString *message);
NS_ASSUME_NONNULL_END
