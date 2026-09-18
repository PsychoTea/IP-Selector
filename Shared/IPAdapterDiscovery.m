#import "IPAdapterDiscovery.h"
#import <IOKit/IOKitLib.h>

BOOL IPIsUSBDeviceNetworkPath(NSArray<NSString *> *classes)
{
    return [classes containsObject:@"AppleUSBDeviceNCMData"] ||
        [classes containsObject:@"IOUSBDeviceInterface"];
}

static BOOL IPIsInternalUSBNetwork(io_registry_entry_t interface)
{
    NSMutableArray<NSString *> *classes = [NSMutableArray array];
    io_registry_entry_t entry = interface;
    IOObjectRetain(entry);
    while (entry) {
        io_name_t className = { 0 };
        if (IOObjectGetClass(entry, className) == KERN_SUCCESS) {
            [classes addObject:[NSString stringWithUTF8String:className]];
        }

        io_registry_entry_t parent = IO_OBJECT_NULL;
        IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
        IOObjectRelease(entry);
        entry = parent;
    }

    return IPIsUSBDeviceNetworkPath(classes);
}

static NSDictionary<NSString *, NSNumber *> *IPAttachedNetworkInterfaces(void)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IONetworkInterface"), &iterator)
        != KERN_SUCCESS) {
        return result;
    }

    io_object_t item;
    while ((item = IOIteratorNext(iterator))) {

        // AppleUSBDeviceNCM exposes internal device-mode ports as Ethernet interfaces.

        // Their registry presence does not mean that a USB Ethernet adapter is attached.
        if (IPIsInternalUSBNetwork(item)) {
            IOObjectRelease(item);
            continue;
        }

        NSString *bsd = CFBridgingRelease(
            IORegistryEntryCreateCFProperty(item, CFSTR("BSD Name"), kCFAllocatorDefault, 0));
        uint64_t registryID = 0;
        if ([bsd isKindOfClass:NSString.class]
            && IORegistryEntryGetRegistryEntryID(item, &registryID) == KERN_SUCCESS) {
            result[bsd] = @(registryID);
        }

        IOObjectRelease(item);
    }

    IOObjectRelease(iterator);

    return result;
}

static NSDictionary *IPProtocolConfiguration(SCNetworkServiceRef service, CFStringRef type)
{
    SCNetworkProtocolRef protocol = SCNetworkServiceCopyProtocol(service, type);
    if (!protocol) {
        return @{};
    }

    NSDictionary *config =
        [(__bridge NSDictionary *)SCNetworkProtocolGetConfiguration(protocol) copy] ?: @{};
    CFRelease(protocol);

    return config;
}

@implementation IPAdapterDiscovery

+ (NSArray<IPAdapterSnapshot *> *)adapters
{
    SCPreferencesRef preferences = SCPreferencesCreate(NULL, CFSTR("IP Selector read"), NULL);
    if (!preferences) {
        return @[];
    }

    NSArray *result = [self adaptersWithPreferences:preferences];
    CFRelease(preferences);

    return result;
}

+ (NSArray<IPAdapterSnapshot *> *)adaptersWithPreferences:(SCPreferencesRef)preferences
{
    NSDictionary *hardware = IPAttachedNetworkInterfaces();
    SCNetworkSetRef set = SCNetworkSetCopyCurrent(preferences);
    if (!set) {
        return @[];
    }

    NSArray *services = CFBridgingRelease(SCNetworkSetCopyServices(set));
    CFRelease(set);

    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("IP Selector state"), NULL, NULL);

    NSMutableArray *adapters = [NSMutableArray array];
    for (id object in services) {
        SCNetworkServiceRef service = (__bridge SCNetworkServiceRef)object;
        IPAdapterSnapshot *adapter = [self snapshotForService:service hardware:hardware
                                                        store:store];
        if (adapter) {
            [adapters addObject:adapter];
        }
    }

    if (store) {
        CFRelease(store);
    }

    return [adapters sortedArrayUsingComparator:^NSComparisonResult(
        IPAdapterSnapshot *first, IPAdapterSnapshot *second) {
        NSComparisonResult order = [first.serviceName localizedStandardCompare:second.serviceName];
        return order == NSOrderedSame ? [first.serviceID compare:second.serviceID] : order;
    }];
}

+ (IPAdapterSnapshot *)snapshotForService:(SCNetworkServiceRef)service
                                 hardware:(NSDictionary<NSString *, NSNumber *> *)hardware
                                    store:(SCDynamicStoreRef)store
{
    SCNetworkInterfaceRef interface = SCNetworkServiceGetInterface(service);
    if (!interface || !SCNetworkServiceGetEnabled(service)) {
        return nil;
    }

    CFStringRef type = SCNetworkInterfaceGetInterfaceType(interface);
    BOOL isEthernet = type && CFEqual(type, kSCNetworkInterfaceTypeEthernet);
    BOOL isWiFi = type && CFEqual(type, kSCNetworkInterfaceTypeIEEE80211);
    if (!isEthernet && !isWiFi) {
        return nil;
    }

    NSString *bsdName = (__bridge NSString *)SCNetworkInterfaceGetBSDName(interface);
    if (!bsdName.length) {
        return nil;
    }

    NSNumber *registryID = hardware[bsdName];
    if (!registryID) {
        return nil;
    }

    IPAdapterSnapshot *adapter = [IPAdapterSnapshot new];
    adapter.wiFi = isWiFi;
    adapter.serviceID = (__bridge NSString *)SCNetworkServiceGetServiceID(service);
    adapter.serviceName = (__bridge NSString *)SCNetworkServiceGetName(service)
        ?: (isWiFi ? @"Wi-Fi" : @"Ethernet");
    adapter.bsdName = bsdName;
    adapter.registryID = registryID;
    adapter.mac = IPNormalizedMAC(
                      (__bridge NSString *)SCNetworkInterfaceGetHardwareAddressString(interface))
        ?: @"";
    adapter.ipv4 = IPProtocolConfiguration(service, kSCNetworkProtocolTypeIPv4);
    adapter.dns = IPProtocolConfiguration(service, kSCNetworkProtocolTypeDNS);

    if (store) {
        NSString *linkKey =
            [NSString stringWithFormat:@"State:/Network/Interface/%@/Link", bsdName];
        NSDictionary *link
            = CFBridgingRelease(SCDynamicStoreCopyValue(store, (__bridge CFStringRef)linkKey));
        adapter.linkActive = [link[@"Active"] boolValue] && ![link[@"Detaching"] boolValue];

        NSString *stateKey =
            [NSString stringWithFormat:@"State:/Network/Service/%@/IPv4", adapter.serviceID];
        NSDictionary *state
            = CFBridgingRelease(SCDynamicStoreCopyValue(store, (__bridge CFStringRef)stateKey));
        adapter.activeAddresses = state[@"Addresses"] ?: @[];
    }

    return adapter;
}

@end
