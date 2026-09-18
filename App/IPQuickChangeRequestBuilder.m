#import "IPQuickChangeRequestBuilder.h"
#import "IPAdapterDiscovery.h"

static NSDictionary *IPCurrentServiceDNS(NSString *serviceID)
{
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("IP Selector Quick IP"), NULL, NULL);
    if (!store) {
        return @{};
    }

    NSString *key = [NSString stringWithFormat:@"State:/Network/Service/%@/DNS", serviceID];
    id state = CFBridgingRelease(SCDynamicStoreCopyValue(store, (__bridge CFStringRef)key));
    CFRelease(store);

    return [state isKindOfClass:NSDictionary.class] ? state : @{};
}

@implementation IPQuickChangeRequestBuilder {
    NSArray<IPAdapterSnapshot *> * (^_adaptersProvider)(void);
    NSDictionary * (^_DNSProvider)(NSString *);
}

- (instancetype)init
{
    return [self initWithAdaptersProvider:^NSArray<IPAdapterSnapshot *> * {
        return IPAdapterDiscovery.adapters;
    } DNSProvider:^NSDictionary *(NSString *serviceID) {
        return IPCurrentServiceDNS(serviceID);
    }];
}

- (instancetype)initWithAdaptersProvider:(NSArray<IPAdapterSnapshot *> * (^)(void))adaptersProvider
                             DNSProvider:(NSDictionary * (^)(NSString *))DNSProvider
{
    if ((self = [super init])) {
        _adaptersProvider = [adaptersProvider copy];
        _DNSProvider = [DNSProvider copy];
    }

    return self;
}

- (IPApplyRequest *)requestForPreset:(IPPreset *)preset
                             adapter:(IPAdapterSnapshot *)expected
                               error:(NSError **)error
{
    IPAdapterSnapshot *current = nil;
    for (IPAdapterSnapshot *adapter in _adaptersProvider()) {
        if ([adapter sameAttachment:expected]) {
            current = adapter;
            break;
        }
    }

    if (!current) {
        IPValidationFailure(error,
            @"This adapter is no longer connected. Close this window and select an adapter again.");
        return nil;
    }

    // Preserve manual DNS, or this service's current DNS when leaving DHCP.
    NSArray *dns = current.dns[@"ServerAddresses"];
    if (!dns && [current.ipv4[@"ConfigMethod"] isEqual:@"DHCP"]) {
        dns = _DNSProvider(current.serviceID)[@"ServerAddresses"];
    }

    IPPreset *settings = [preset copy];
    settings.dns = dns ?: @[];
    if (![settings validate:error]) {
        return nil;
    }

    IPApplyRequest *request = [IPApplyRequest new];
    request.expected = current;
    request.preset = settings;

    return request;
}

@end
