#import "IPModels.h"

@implementation IPApplyResult

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _message = @"";
    }

    return self;
}

+ (instancetype)failure:(NSString *)message
{
    IPApplyResult *result = [self new];
    result.message = message;

    return result;
}

+ (instancetype)success:(NSString *)message
                current:(IPAdapterSnapshot *)current
              undoToken:(NSString *)undoToken
{
    IPApplyResult *result = [self new];
    result.success = YES;
    result.message = message;
    result.current = current;
    result.undoToken = undoToken;

    return result;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeBool:self.success forKey:@"success"];
    [coder encodeObject:self.message forKey:@"message"];
    [coder encodeObject:self.current forKey:@"current"];
    [coder encodeObject:self.undoToken forKey:@"undoToken"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _success = [coder decodeBoolForKey:@"success"];
        _message =
            [coder decodeObjectOfClass:NSString.class forKey:@"message"] ?: @"No result message.";
        _current = [coder decodeObjectOfClass:IPAdapterSnapshot.class forKey:@"current"];
        _undoToken = [coder decodeObjectOfClass:NSString.class forKey:@"undoToken"];
    }

    return self;
}

@end
