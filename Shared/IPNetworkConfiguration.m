#import "IPModels.h"

NSDictionary *IPDesiredIPv4(NSDictionary *existing, IPPreset *preset, BOOL dhcp)
{
    NSMutableDictionary *configuration = [existing mutableCopy];
    [configuration removeObjectsForKeys:@[
        @"Addresses",
        @"SubnetMasks",
        @"Router",
        @"DestAddresses",
        @"BroadcastAddresses"
    ]];
    configuration[@"ConfigMethod"] = dhcp ? @"DHCP" : @"Manual";
    if (!dhcp) {
        configuration[@"Addresses"] = @[preset.address];
        configuration[@"SubnetMasks"] = @[preset.mask];
        if (preset.gateway.length) {
            configuration[@"Router"] = preset.gateway;
        }
    }

    return configuration;
}

NSDictionary *IPDesiredDNS(NSDictionary *existing, IPPreset *preset, BOOL dhcp)
{
    NSMutableDictionary *configuration = [existing mutableCopy];
    [configuration removeObjectForKey:@"ServerAddresses"];
    if (!dhcp && preset.dns.count) {
        configuration[@"ServerAddresses"] = preset.dns;
    }

    return configuration;
}
