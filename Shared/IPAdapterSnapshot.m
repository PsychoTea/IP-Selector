#import "IPModels.h"
#import "IPModelCoding.h"

@implementation IPAdapterSnapshot

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _serviceID = @"";
        _serviceName = @"";
        _bsdName = @"";
        _mac = @"";

        _registryID = @0;
        _activeAddresses = @[];

        _ipv4 = @{};
        _dns = @{};
    }

    return self;
}

- (BOOL)sameAttachment:(IPAdapterSnapshot *)other
{
    return other && [self.serviceID isEqual:other.serviceID] && [self.bsdName isEqual:other.bsdName]
        && [self.mac isEqual:other.mac] && self.registryID.unsignedLongLongValue != 0 &&
        [self.registryID isEqual:other.registryID];
}

- (BOOL)sameConfiguration:(IPAdapterSnapshot *)other
{
    return [self sameAttachment:other] && [self.ipv4 isEqual:other.ipv4] &&
        [self.dns isEqual:other.dns];
}

- (BOOL)matchesPreset:(IPPreset *)preset
{
    return [self.ipv4[@"ConfigMethod"] isEqual:@"Manual"] &&
        [self.ipv4[@"Addresses"] isEqual:@[preset.address]] &&
        [self.ipv4[@"SubnetMasks"] isEqual:@[preset.mask]] &&
        [(self.ipv4[@"Router"] ?: @"") isEqual:preset.gateway] &&
        [(self.dns[@"ServerAddresses"] ?: @[]) isEqual:preset.dns];
}

- (BOOL)isAutomatic
{
    BOOL usesDHCP = [self.ipv4[@"ConfigMethod"] isEqual:@"DHCP"];

    return usesDHCP && [self.dns[@"ServerAddresses"] count] == 0;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.serviceID forKey:@"serviceID"];
    [coder encodeObject:self.serviceName forKey:@"serviceName"];
    [coder encodeObject:self.bsdName forKey:@"bsdName"];
    [coder encodeObject:self.mac forKey:@"mac"];
    [coder encodeObject:self.registryID forKey:@"registryID"];
    [coder encodeObject:self.activeAddresses forKey:@"activeAddresses"];
    [coder encodeObject:self.ipv4 forKey:@"ipv4"];
    [coder encodeObject:self.dns forKey:@"dns"];
    [coder encodeBool:self.linkActive forKey:@"linkActive"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _serviceID = [coder decodeObjectOfClass:NSString.class forKey:@"serviceID"];
        _serviceName = [coder decodeObjectOfClass:NSString.class forKey:@"serviceName"];
        _bsdName = [coder decodeObjectOfClass:NSString.class forKey:@"bsdName"];
        _mac = [coder decodeObjectOfClass:NSString.class forKey:@"mac"];
        if (!_serviceID || !_serviceName || !_bsdName || !_mac) {
            return nil;
        }

        _registryID = [coder decodeObjectOfClass:NSNumber.class forKey:@"registryID"];
        _activeAddresses =
            [coder decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, NSString.class, nil]
                                  forKey:@"activeAddresses"];

        _ipv4 = [coder decodeObjectOfClasses:IPPropertyClasses() forKey:@"ipv4"];
        _dns = [coder decodeObjectOfClasses:IPPropertyClasses() forKey:@"dns"];

        if (!_registryID || ![_ipv4 isKindOfClass:NSDictionary.class]
            || ![_dns isKindOfClass:NSDictionary.class]
            || ![_activeAddresses isKindOfClass:NSArray.class]) {
            return nil;
        }

        _linkActive = [coder decodeBoolForKey:@"linkActive"];
    }

    return self;
}

@end
