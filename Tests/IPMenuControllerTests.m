#import "IPTestSupport.h"
#import "IPMenuController.h"
#import "IPNetworkMonitor.h"
#import "IPHelperClient.h"

@interface IPMenuTestMonitor : IPNetworkMonitor
@property (nonatomic, copy) NSArray<IPAdapterSnapshot *> *testAdapters;
@end

@implementation IPMenuTestMonitor

- (NSArray<IPAdapterSnapshot *> *)adapters
{
    return self.testAdapters ?: @[];
}

- (void)refresh
{
}

@end

@interface IPTrackingTestMenu : NSMenu
@property (nonatomic) BOOL trackingCancelled;
@end

@implementation IPTrackingTestMenu

- (void)cancelTracking
{
    self.trackingCancelled = YES;
}

@end

@interface IPMenuControllerTests : IPTemporaryDirectoryTestCase
@end

@implementation IPMenuControllerTests

- (void)testEachAdapterHasItsOwnRequestsAndActiveSettings
{
    IPPreset *preset = IPTestPreset();
    XCTAssertTrue([self.store replacePresets:@[preset] error:nil]);
    IPAdapterSnapshot *first = IPTestAdapter();
    first.dns = @{};
    first.linkActive = YES;
    first.activeAddresses = @[@"192.168.10.50"];
    IPAdapterSnapshot *second = IPCopyTestAdapter(first);
    second.serviceID = @"service-B";
    second.registryID = @456;
    second.bsdName = @"en7";
    second.ipv4 = IPDesiredIPv4(second.ipv4, preset, NO);

    IPMenuTestMonitor *monitor = [IPMenuTestMonitor new];
    monitor.testAdapters = @[first, second];
    IPMenuController *controller = [[IPMenuController alloc] initWithStore:self.store
                                                                   monitor:monitor
                                                                    client:[IPHelperClient new]];
    [controller menuNeedsUpdate:controller.menu];

    NSMenu *firstMenu = [controller.menu itemAtIndex:0].submenu;
    NSMenu *secondMenu = [controller.menu itemAtIndex:1].submenu;
    XCTAssertEqualObjects([firstMenu itemAtIndex:5].title, @"Use DHCP");
    XCTAssertNil([controller.menu itemAtIndex:0].toolTip);
    XCTAssertEqualObjects([firstMenu itemAtIndex:0].title, @"Connected");
    XCTAssertFalse([firstMenu itemAtIndex:0].enabled);
    XCTAssertEqualObjects([firstMenu itemAtIndex:2].title, first.mac);
    XCTAssertFalse([firstMenu itemAtIndex:2].enabled);
    XCTAssertEqualObjects([firstMenu itemAtIndex:1].title, @"IP: 192.168.10.50");
    XCTAssertFalse([firstMenu itemAtIndex:1].enabled);
    XCTAssertTrue([firstMenu itemAtIndex:3].isSeparatorItem);
    XCTAssertEqualObjects([firstMenu itemAtIndex:4].title, @"Quick IP…");
    XCTAssertTrue([firstMenu itemAtIndex:6].isSeparatorItem);
    XCTAssertEqual([firstMenu itemAtIndex:5].state, NSControlStateValueOn);
    XCTAssertEqual([secondMenu itemAtIndex:5].state, NSControlStateValueOff);
    XCTAssertEqual([firstMenu itemAtIndex:7].state, NSControlStateValueOff);
    XCTAssertEqual([secondMenu itemAtIndex:7].state, NSControlStateValueOn);

    IPApplyRequest *firstRequest = [firstMenu itemAtIndex:7].representedObject;
    IPApplyRequest *secondRequest = [secondMenu itemAtIndex:7].representedObject;
    XCTAssertTrue([firstRequest.expected sameAttachment:first]);
    XCTAssertTrue([secondRequest.expected sameAttachment:second]);
    XCTAssertFalse([firstRequest.expected sameAttachment:second]);
    XCTAssertEqualObjects(firstRequest.preset.address, preset.address);
    XCTAssertNotEqual(firstRequest.preset, preset);
    XCTAssertTrue(((IPApplyRequest *)[firstMenu itemAtIndex:5].representedObject).useDHCP);
}

- (void)testRemovedAdaptersDoNotRemainInMenu
{
    IPMenuTestMonitor *monitor = [IPMenuTestMonitor new];
    monitor.testAdapters = @[IPTestAdapter()];
    IPMenuController *controller = [[IPMenuController alloc] initWithStore:self.store
                                                                   monitor:monitor
                                                                    client:[IPHelperClient new]];
    [controller menuNeedsUpdate:controller.menu];
    XCTAssertNotNil([controller.menu itemAtIndex:0].submenu);

    monitor.testAdapters = @[];
    [controller menuNeedsUpdate:controller.menu];
    XCTAssertEqualObjects([controller.menu itemAtIndex:0].title, @"No connected adapters");
    XCTAssertFalse([controller.menu itemAtIndex:0].enabled);
    XCTAssertNil([controller.menu itemAtIndex:0].submenu);
}

- (void)testAdapterWithoutCableStillHasDHCPAndQuickChange
{
    IPMenuTestMonitor *monitor = [IPMenuTestMonitor new];
    IPAdapterSnapshot *adapter = IPTestAdapter();
    adapter.linkActive = NO;
    monitor.testAdapters = @[adapter];
    IPMenuController *controller = [[IPMenuController alloc] initWithStore:self.store
                                                                   monitor:monitor
                                                                    client:[IPHelperClient new]];
    [controller menuNeedsUpdate:controller.menu];
    NSMenu *submenu = [controller.menu itemAtIndex:0].submenu;
    XCTAssertEqualObjects([submenu itemAtIndex:0].title, @"Not connected");
    XCTAssertFalse([submenu itemAtIndex:0].enabled);
    XCTAssertTrue([submenu itemAtIndex:5].enabled);
    XCTAssertNotNil([submenu itemWithTitle:@"Quick IP…"]);
    XCTAssertFalse([submenu itemWithTitle:@"No saved presets"].enabled);
}

- (void)testWiFiComesFirstRegardlessOfServiceNameOrLinkStatus
{
    IPAdapterSnapshot *ethernet = IPTestAdapter();
    ethernet.serviceName = @"Wi-Fi";
    IPAdapterSnapshot *wifi = IPCopyTestAdapter(ethernet);
    wifi.wiFi = YES;
    wifi.serviceID = @"wireless";
    wifi.serviceName = @"Zebra";
    wifi.bsdName = @"en8";
    wifi.linkActive = NO;
    IPAdapterSnapshot *other = IPCopyTestAdapter(ethernet);
    other.serviceID = @"second-wired";
    other.serviceName = @"Audio";

    IPMenuTestMonitor *monitor = [IPMenuTestMonitor new];
    monitor.testAdapters = @[ethernet, wifi, other];
    IPMenuController *controller = [[IPMenuController alloc] initWithStore:self.store
                                                                   monitor:monitor
                                                                    client:[IPHelperClient new]];
    [controller menuNeedsUpdate:controller.menu];
    XCTAssertEqualObjects([controller.menu itemAtIndex:0].submenu.title, @"Zebra");
    XCTAssertEqualObjects([controller.menu itemAtIndex:1].submenu.title, @"Wi-Fi");
    XCTAssertEqualObjects([controller.menu itemAtIndex:2].submenu.title, @"Audio");
}

- (void)testDHCPStatusChangesFromWaitingToSelfAssignedToConnected
{
    IPMenuTestMonitor *monitor = [IPMenuTestMonitor new];
    IPAdapterSnapshot *adapter = IPTestAdapter();
    adapter.linkActive = YES;
    monitor.testAdapters = @[adapter];
    IPMenuController *controller = [[IPMenuController alloc] initWithStore:self.store
                                                                   monitor:monitor
                                                                    client:[IPHelperClient new]];
    [controller menuNeedsUpdate:controller.menu];
    XCTAssertEqualObjects(
        [[controller.menu itemAtIndex:0].submenu itemAtIndex:0].title, @"Not connected");

    adapter.activeAddresses = @[@"169.254.10.20"];
    [controller menuNeedsUpdate:controller.menu];
    XCTAssertEqualObjects(
        [[controller.menu itemAtIndex:0].submenu itemAtIndex:0].title, @"Self Assigned IP");

    adapter.activeAddresses = @[@"192.168.10.20"];
    [controller menuNeedsUpdate:controller.menu];
    XCTAssertEqualObjects(
        [[controller.menu itemAtIndex:0].submenu itemAtIndex:0].title, @"Connected");
}

- (void)testLinkChangesUpdateOpenMenuWithoutClosingOrReplacingRows
{
    IPMenuTestMonitor *monitor = [IPMenuTestMonitor new];
    IPAdapterSnapshot *adapter = IPTestAdapter();
    monitor.testAdapters = @[adapter];
    IPMenuController *controller = [[IPMenuController alloc] initWithStore:self.store
                                                                   monitor:monitor
                                                                    client:[IPHelperClient new]];
    IPTrackingTestMenu *menu = [IPTrackingTestMenu new];
    menu.autoenablesItems = NO;
    [controller setValue:menu forKey:@"menu"];
    [controller menuNeedsUpdate:menu];
    [controller menuWillOpen:menu];
    NSMenuItem *row = [menu itemAtIndex:0];
    NSMenuItem *status = [row.submenu itemAtIndex:0];
    NSMenuItem *dhcp = [row.submenu itemAtIndex:5];
    IPApplyRequest *submittedRequest = dhcp.representedObject;
    NSMenuItem *address = [row.submenu itemAtIndex:1];
    XCTAssertEqualObjects(address.title, @"IP: Not assigned");
    IPAdapterSnapshot *updated = IPCopyTestAdapter(adapter);
    updated.linkActive = YES;
    updated.activeAddresses = @[@"169.254.10.20"];
    monitor.testAdapters = @[updated];
    [NSNotificationCenter.defaultCenter postNotificationName:IPAdaptersChanged object:monitor];
    XCTAssertFalse(menu.trackingCancelled);
    XCTAssertEqual([menu itemAtIndex:0], row);
    XCTAssertEqual([row.submenu itemAtIndex:0], status);
    XCTAssertEqualObjects(status.title, @"Self Assigned IP");
    XCTAssertEqual([row.submenu itemAtIndex:1], address);
    XCTAssertEqualObjects(address.title, @"IP: 169.254.10.20");
    XCTAssertEqual(((IPApplyRequest *)dhcp.representedObject).expected, updated);
    XCTAssertNotEqual(dhcp.representedObject, submittedRequest);
    XCTAssertEqual(submittedRequest.expected, adapter);
    XCTAssertTrue(dhcp.enabled);

    updated = IPCopyTestAdapter(updated);
    updated.linkActive = NO;
    monitor.testAdapters = @[updated];
    [NSNotificationCenter.defaultCenter postNotificationName:IPAdaptersChanged object:monitor];
    XCTAssertFalse(menu.trackingCancelled);
    XCTAssertEqualObjects(status.title, @"Not connected");
    XCTAssertTrue(dhcp.enabled);

    monitor.testAdapters = @[];
    [NSNotificationCenter.defaultCenter postNotificationName:IPAdaptersChanged object:monitor];
    XCTAssertFalse(menu.trackingCancelled);
    XCTAssertEqual([menu itemAtIndex:0], row);
    XCTAssertFalse(row.enabled);
    XCTAssertEqualObjects(address.title, @"IP: Not assigned");
    XCTAssertFalse(dhcp.enabled);
    XCTAssertFalse([row.submenu itemAtIndex:4].enabled);
    [controller menuDidClose:menu];
    [controller menuNeedsUpdate:menu];
    XCTAssertNil([menu itemAtIndex:0].submenu);
}

@end
