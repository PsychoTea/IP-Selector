#import "IPModels.h"

@implementation IPApplyRequest

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.expected forKey:@"expected"];
    [coder encodeObject:self.preset forKey:@"preset"];
    [coder encodeBool:self.useDHCP forKey:@"dhcp"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        _expected = [coder decodeObjectOfClass:IPAdapterSnapshot.class forKey:@"expected"];
        _preset = [coder decodeObjectOfClass:IPPreset.class forKey:@"preset"];
        _useDHCP = [coder decodeBoolForKey:@"dhcp"];
        if (!_expected) {
            return nil;
        }
    }

    return self;
}

@end
