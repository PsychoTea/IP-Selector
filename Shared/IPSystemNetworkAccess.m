#import "IPNetworkAccess.h"
#import "IPAdapterDiscovery.h"

@implementation IPSystemNetworkAccess {
    SCPreferencesRef _preferences;
    BOOL _locked;
}

- (void)dealloc
{
    [self unlock];
    if (_preferences) {
        CFRelease(_preferences);
    }
}

- (BOOL)lock:(NSError **)error
{
    if (_locked) {
        return YES;
    }

    if (_preferences) {
        CFRelease(_preferences);
    }

    _preferences = SCPreferencesCreate(NULL, CFSTR("IP Selector helper"), NULL);
    _locked = _preferences && SCPreferencesLock(_preferences, false);
    if (!_locked && error) {
        *error = IPError(@"Cannot lock network settings. Another process may be changing them.");
    }

    return _locked;
}

- (void)unlock
{
    if (_locked) {
        SCPreferencesUnlock(_preferences);
        _locked = NO;
    }
}

- (IPAdapterSnapshot *)snapshot:(NSString *)serviceID
{
    for (IPAdapterSnapshot *adapter in [IPAdapterDiscovery adaptersWithPreferences:_preferences]) {
        if ([adapter.serviceID isEqual:serviceID]) {
            return adapter;
        }
    }

    return nil;
}

- (BOOL)stageIPv4:(NSDictionary *)ipv4
              dns:(NSDictionary *)dns
          service:(NSString *)serviceID
            error:(NSError **)error
{
    SCNetworkServiceRef service
        = SCNetworkServiceCopy(_preferences, (__bridge CFStringRef)serviceID);
    if (!service) {
        if (error) {
            *error = IPError(@"The network service is no longer available.");
        }

        return NO;
    }

    SCNetworkProtocolRef ipv4Protocol
        = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeIPv4);
    SCNetworkProtocolRef dnsProtocol
        = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS);
    BOOL succeeded = ipv4Protocol && dnsProtocol
        && SCNetworkProtocolSetConfiguration(
            ipv4Protocol, ipv4.count ? (__bridge CFDictionaryRef)ipv4 : NULL)
        && SCNetworkProtocolSetConfiguration(
            dnsProtocol, dns.count ? (__bridge CFDictionaryRef)dns : NULL);

    if (ipv4Protocol) {
        CFRelease(ipv4Protocol);
    }

    if (dnsProtocol) {
        CFRelease(dnsProtocol);
    }

    CFRelease(service);

    if (!succeeded && error) {
        *error = IPError(@"Cannot set IPv4 and DNS on this service. Check its configuration in "
                         @"System Settings.");
    }

    return succeeded;
}

- (BOOL)commit:(NSError **)error
{
    BOOL succeeded = SCPreferencesCommitChanges(_preferences);

    if (!succeeded && error) {
        *error = IPError(@"macOS could not save the network settings.");
    }

    return succeeded;
}

- (BOOL)apply:(NSError **)error
{
    BOOL succeeded = SCPreferencesApplyChanges(_preferences);

    if (!succeeded && error) {
        *error = IPError(@"macOS could not apply the network settings.");
    }

    return succeeded;
}

- (IPAdapterSnapshot *)readBack:(NSString *)serviceID
{
    for (IPAdapterSnapshot *adapter in IPAdapterDiscovery.adapters) {
        if ([adapter.serviceID isEqual:serviceID]) {
            return adapter;
        }
    }

    return nil;
}

@end
