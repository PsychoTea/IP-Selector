#import "IPTestSupport.h"
#import "IPAdapterDiscovery.h"

// Use saved services and supplied hardware IDs without changing this Mac's settings.
@interface IPAdapterDiscovery (Tests)
+ (IPAdapterSnapshot *)snapshotForService:(SCNetworkServiceRef)service
                                 hardware:(NSDictionary<NSString *, NSNumber *> *)hardware
                                    store:(SCDynamicStoreRef)store;
@end

@interface IPAdapterDiscoveryTests : IPTemporaryDirectoryTestCase
@end

@implementation IPAdapterDiscoveryTests

- (IPAdapterSnapshot *)snapshotWithType:(NSString *)type
                               attached:(BOOL)attached
                                enabled:(BOOL)enabled
{
    BOOL isWiFi = [type isEqual:@"IEEE80211"];
    NSString *hardwareType = isWiFi ? @"AirPort" : type;
    NSString *storedType = isWiFi ? @"Ethernet" : type;
    NSDictionary *document = @{
        @"NetworkServices": @{
            @"test-service": @{
                @"UserDefinedName": @"Studio Network",
                @"Interface":
                    @{ @"Type": storedType, @"Hardware": hardwareType, @"DeviceName": @"en60003" },
                @"IPv4": @{ @"ConfigMethod": @"DHCP" },
                @"DNS": @{ @"ServerAddresses": @[@"1.1.1.1"] }
            }
        }
    };
    NSURL *url = [self.directory URLByAppendingPathComponent:@"service.plist"];
    XCTAssertTrue([document writeToURL:url error:NULL]);

    SCPreferencesRef preferences = SCPreferencesCreate(
        NULL, CFSTR("IP Selector service test"), (__bridge CFStringRef)url.path);
    XCTAssertNotEqual(preferences, NULL);
    if (!preferences) {
        return nil;
    }

    SCNetworkServiceRef service = SCNetworkServiceCopy(preferences, CFSTR("test-service"));
    XCTAssertNotEqual(service, NULL);
    if (!service) {
        CFRelease(preferences);
        return nil;
    }

    // macOS stores Wi-Fi as Ethernet/AirPort but exposes it as IEEE80211 through the API.
    SCNetworkInterfaceRef interface = SCNetworkServiceGetInterface(service);
    XCTAssertNotEqual(interface, NULL);
    if (interface) {
        XCTAssertEqualObjects(
            (__bridge NSString *)SCNetworkInterfaceGetInterfaceType(interface), type);
    }

    XCTAssertTrue(SCNetworkServiceSetEnabled(service, enabled));
    NSDictionary *hardware = attached ? @{ @"en60003": @123 } : @{};
    IPAdapterSnapshot *snapshot = [IPAdapterDiscovery snapshotForService:service hardware:hardware
                                                                   store:NULL];
    CFRelease(service);
    CFRelease(preferences);

    return snapshot;
}

- (void)testWiFiIsAvailableWithoutAnActiveConnection
{
    IPAdapterSnapshot *adapter = [self snapshotWithType:@"IEEE80211" attached:YES enabled:YES];

    XCTAssertNotNil(adapter);
    XCTAssertTrue(adapter.isWiFi);
    XCTAssertEqualObjects(adapter.serviceName, @"Studio Network");
    XCTAssertEqualObjects(adapter.serviceID, @"test-service");
    XCTAssertEqualObjects(adapter.bsdName, @"en60003");
    XCTAssertEqualObjects(adapter.registryID, @123);
    XCTAssertEqualObjects(adapter.ipv4[@"ConfigMethod"], @"DHCP");
    XCTAssertEqualObjects(adapter.dns[@"ServerAddresses"], @[@"1.1.1.1"]);
    XCTAssertFalse(adapter.linkActive);
    XCTAssertEqual(adapter.activeAddresses.count, 0u);
}

- (void)testEthernetIsStillAvailable
{
    IPAdapterSnapshot *adapter = [self snapshotWithType:@"Ethernet" attached:YES enabled:YES];
    XCTAssertNotNil(adapter);
    XCTAssertFalse(adapter.isWiFi);
}

- (void)testWiFiRequiresAttachedHardware
{
    XCTAssertNil([self snapshotWithType:@"IEEE80211" attached:NO enabled:YES]);
}

- (void)testDisabledWiFiServiceIsExcluded
{
    XCTAssertNil([self snapshotWithType:@"IEEE80211" attached:YES enabled:NO]);
}

- (void)testOtherInterfaceTypesAreExcluded
{
    XCTAssertNil([self snapshotWithType:@"FireWire" attached:YES enabled:YES]);
}

- (void)testDisconnectedSavedServicesAreNotListed
{
    NSMutableDictionary *services = [NSMutableDictionary dictionary],
                        *links = [NSMutableDictionary dictionary];
    NSArray *names = @[@"AX88179A", @"USB 10/100/1000LAN"];
    for (NSUInteger index = 0; index < names.count; index++) {
        NSString *identifier = NSUUID.UUID.UUIDString;
        services[identifier] = @{
            @"UserDefinedName": names[index],
            @"Interface": @{
                @"Type": @"Ethernet",
                @"Hardware": @"Ethernet",
                @"DeviceName": [NSString stringWithFormat:@"en%lu", (unsigned long)(60000 + index)],
                @"UserDefinedName": names[index]
            },
            @"IPv4": @{ @"ConfigMethod": @"DHCP" },
            @"DNS": @{}
        };

        links[identifier] =
            @{ @"__LINK__": [@"/NetworkServices/" stringByAppendingString:identifier] };
    }

    NSDictionary *document = @{
        @"CurrentSet": @"/Sets/Test",
        @"NetworkServices": services,
        @"Sets": @{ @"Test": @{ @"Network": @{ @"Service": links } } }
    };

    NSURL *url = [self.directory URLByAppendingPathComponent:@"network.plist"];

    XCTAssertTrue([document writeToURL:url error:NULL]);

    SCPreferencesRef preferences = SCPreferencesCreate(
        NULL, CFSTR("IP Selector discovery test"), (__bridge CFStringRef)url.path);

    XCTAssertNotEqual(preferences, NULL);

    NSArray<IPAdapterSnapshot *> *adapters =
        [IPAdapterDiscovery adaptersWithPreferences:preferences];
    CFRelease(preferences);

    XCTAssertEqual(adapters.count, 0u);
}

- (void)testInternalUSBDeviceNetworkIsExcluded
{
    // Class chain observed for en4, en5, and en6 on an Apple silicon Mac.

    XCTAssertTrue(IPIsUSBDeviceNetworkPath(@[
        @"IOEthernetInterface",
        @"AppleUSBDeviceNCMData",
        @"IOUSBDeviceInterface",
        @"AppleT8103USBXDCI",
        @"AppleARMIODevice"
    ]));

    // A different device-mode network driver must also remain excluded.

    XCTAssertTrue(IPIsUSBDeviceNetworkPath(
        @[@"IOEthernetInterface", @"OtherDeviceNetworkDriver", @"IOUSBDeviceInterface"]));
}

- (void)testHostSideEthernetAdaptersAreNotExcluded
{
    // Host NCM adapters are different from the Mac's device-side NCM functions.

    XCTAssertFalse(IPIsUSBDeviceNetworkPath(
        @[@"IOEthernetInterface", @"AppleUSBNCM", @"IOUSBHostInterface", @"IOUSBHostDevice"]));
    XCTAssertFalse(IPIsUSBDeviceNetworkPath(
        @[@"IOEthernetInterface", @"AX88179", @"IOUSBHostInterface", @"IOUSBHostDevice"]));
    XCTAssertFalse(
        IPIsUSBDeviceNetworkPath(@[@"IOEthernetInterface", @"EthernetController", @"IOPCIDevice"]));
}

@end
