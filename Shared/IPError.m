#import "IPError.h"

NSString *const IPErrorDomain = @"org.ipselector.error";

NSError *IPError(NSString *message)
{
    return [NSError errorWithDomain:IPErrorDomain code:1
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

BOOL IPValidationFailure(NSError **error, NSString *message)
{
    if (error) {
        *error = IPError(message);
    }

    return NO;
}
