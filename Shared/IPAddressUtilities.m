#import "IPAddressUtilities.h"
#import <arpa/inet.h>

BOOL IPValidIPv4(NSString *value)
{
    if (![value isKindOfClass:NSString.class]) {
        return NO;
    }

    struct in_addr addr;

    return inet_pton(AF_INET, value.UTF8String, &addr) == 1;
}

BOOL IPValidUnicastIPv4(NSString *value)
{
    struct in_addr addr;
    if (!IPValidIPv4(value)) {
        return NO;
    }

    inet_pton(AF_INET, value.UTF8String, &addr);
    uint32_t ip = ntohl(addr.s_addr);

    return (ip >> 24) != 0 && (ip >> 24) != 127 && (ip >> 24) < 224;
}

BOOL IPValidDNSAddress(NSString *value)
{
    if (![value isKindOfClass:NSString.class]) {
        return NO;
    }

    struct in6_addr addr;
    if (IPValidIPv4(value)) {
        struct in_addr v4;
        inet_pton(AF_INET, value.UTF8String, &v4);
        uint32_t host = ntohl(v4.s_addr);
        return (host >> 24) != 0 && (host >> 24) < 224;
    }

    return inet_pton(AF_INET6, value.UTF8String, &addr) == 1 && !IN6_IS_ADDR_UNSPECIFIED(&addr)
        && !IN6_IS_ADDR_MULTICAST(&addr);
}

NSString *IPNormalizedMAC(NSString *value)
{
    if (![value isKindOfClass:NSString.class]) {
        return nil;
    }

    NSString *hex = [[value stringByReplacingOccurrencesOfString:@":" withString:@""]
        stringByReplacingOccurrencesOfString:@"-"
                                  withString:@""];
    NSCharacterSet *digits =
        [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    if (hex.length != 12 ||
        [hex rangeOfCharacterFromSet:digits.invertedSet].location != NSNotFound) {
        return nil;
    }

    if ([hex isEqual:@"000000000000"] || [[hex lowercaseString] isEqual:@"ffffffffffff"]) {
        return nil;
    }

    unsigned firstOctet = 0;
    [[NSScanner scannerWithString:[hex substringToIndex:2]] scanHexInt:&firstOctet];
    if (firstOctet & 1) {
        return nil;
    }

    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < 12; i += 2) {
        [parts addObject:[[hex substringWithRange:NSMakeRange(i, 2)] uppercaseString]];
    }

    return [parts componentsJoinedByString:@":"];
}

NSString *IPSubnetMask(NSString *value)
{
    if (![value isKindOfClass:NSString.class]) {
        return nil;
    }

    NSString *text =
        [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([text hasPrefix:@"/"]) {
        text = [text substringFromIndex:1];
    }

    uint32_t mask;
    if ([text rangeOfString:@"."].location == NSNotFound) {
        NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
        BOOL containsNonDigit =
            [text rangeOfCharacterFromSet:digits.invertedSet].location != NSNotFound;
        if (!text.length || text.length > 2 || containsNonDigit || text.integerValue > 32) {
            return nil;
        }

        mask = text.integerValue == 0 ? 0 : UINT32_MAX << (32 - text.integerValue);
    } else {
        struct in_addr parsedAddress;
        if (inet_pton(AF_INET, text.UTF8String, &parsedAddress) != 1) {
            return nil;
        }

        mask = ntohl(parsedAddress.s_addr);
        uint32_t inverse = ~mask;
        if ((inverse & (inverse + 1)) != 0) {
            return nil;
        }
    }

    return [NSString stringWithFormat:@"%u.%u.%u.%u",
        mask >> 24,
        (mask >> 16) & 255,
        (mask >> 8) & 255,
        mask & 255];
}
