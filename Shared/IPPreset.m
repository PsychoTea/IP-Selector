#import "IPModels.h"
#import "IPModelCoding.h"
#import <arpa/inet.h>

@implementation IPPreset

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _identifier = NSUUID.UUID.UUIDString;
        _name = @"";
        _address = @"";
        _mask = @"255.255.255.0";
        _gateway = @"";
        _dns = @[];
    }

    return self;
}

- (BOOL)validate:(NSError **)error
{
    if (![self.name isKindOfClass:NSString.class]
        || ![self.name
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
            .length
        || self.name.length > 100) {
        return IPValidationFailure(error, @"Enter a preset name of 1 to 100 characters.");
    }

    if (!IPValidUnicastIPv4(self.address)) {
        return IPValidationFailure(error, @"Enter a valid unicast IPv4 address.");
    }

    NSString *mask = IPSubnetMask(self.mask);
    if (!mask) {
        return IPValidationFailure(
            error, @"Enter a continuous subnet mask or a prefix from /0 to /32.");
    }

    struct in_addr ip, netmask;
    inet_pton(AF_INET, self.address.UTF8String, &ip);
    inet_pton(AF_INET, mask.UTF8String, &netmask);
    uint32_t hostAddress = ntohl(ip.s_addr), maskBits = ntohl(netmask.s_addr);
    if (maskBits < 0xfffffffe
        && ((hostAddress & ~maskBits) == 0 || (hostAddress & ~maskBits) == ~maskBits)) {
        return IPValidationFailure(
            error, @"The address is a subnet or broadcast address for this mask.");
    }

    if (![self.gateway isKindOfClass:NSString.class]) {
        return IPValidationFailure(error, @"The gateway must be text.");
    }

    if (self.gateway.length) {
        if (!IPValidUnicastIPv4(self.gateway)) {
            return IPValidationFailure(error, @"Enter a valid gateway address, or leave it empty.");
        }

        struct in_addr parsedGateway;
        inet_pton(AF_INET, self.gateway.UTF8String, &parsedGateway);
        uint32_t gatewayAddress = ntohl(parsedGateway.s_addr);
        if (gatewayAddress == hostAddress || (gatewayAddress & maskBits) != (hostAddress & maskBits)
            || (maskBits < 0xfffffffe
                && ((gatewayAddress & ~maskBits) == 0
                    || (gatewayAddress & ~maskBits) == ~maskBits))) {
            return IPValidationFailure(
                error, @"The gateway must be another host in the same subnet.");
        }
    }

    if (![self.dns isKindOfClass:NSArray.class] || self.dns.count > 16) {
        return IPValidationFailure(error, @"Enter no more than 16 DNS servers.");
    }

    for (id server in self.dns) {
        if (!IPValidDNSAddress(server)) {
            return IPValidationFailure(error, @"Each DNS server must be an IPv4 or IPv6 address.");
        }
    }

    self.mask = mask;

    return YES;
}

- (NSDictionary *)JSON
{
    return @{
        @"id": self.identifier,
        @"name": self.name,
        @"address": self.address,
        @"mask": self.mask,
        @"gateway": self.gateway,
        @"dns": self.dns
    };
}

+ (instancetype)fromJSON:(id)object error:(NSError **)error
{
    if (![object isKindOfClass:NSDictionary.class]) {
        IPValidationFailure(error, @"A preset must be a JSON object.");
        return nil;
    }

    NSDictionary *document = object;
    for (NSString *key in @[@"id", @"name", @"address", @"mask", @"gateway"]) {
        if (![document[key] isKindOfClass:NSString.class]) {
            IPValidationFailure(error, @"A preset has a missing or invalid text field.");
            return nil;
        }
    }

    if (![[NSUUID alloc] initWithUUIDString:document[@"id"]]) {
        IPValidationFailure(error, @"A preset has an invalid ID.");
        return nil;
    }

    IPPreset *preset = [self new];
    preset.identifier = document[@"id"];
    preset.name = document[@"name"];
    preset.address = document[@"address"];
    preset.mask = document[@"mask"];
    preset.gateway = document[@"gateway"];
    preset.dns = document[@"dns"];

    return [preset validate:error] ? preset : nil;
}

- (id)copyWithZone:(NSZone *)zone
{
    IPPreset *preset = [[[self class] allocWithZone:zone] init];
    preset.identifier = self.identifier;
    preset.name = self.name;
    preset.address = self.address;
    preset.mask = self.mask;
    preset.gateway = self.gateway;
    preset.dns = self.dns;

    return preset;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.JSON forKey:@"value"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [IPPreset fromJSON:[coder decodeObjectOfClasses:IPPropertyClasses() forKey:@"value"]
                        error:NULL];
}

@end
