#import "IPTestSupport.h"
#import "IPAdapterDiscovery.h"

@interface IPAdapterDiscoveryTests : IPTemporaryDirectoryTestCase
@end

@implementation IPAdapterDiscoveryTests

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
