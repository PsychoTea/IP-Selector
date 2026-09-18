#import "IPTestSupport.h"
#import "IPHelperProtocol.h"

@interface IPModelTests : XCTestCase
@end

@implementation IPModelTests

- (void)testIdentityIncludesPhysicalAttachment
{
    IPAdapterSnapshot *adapter = IPTestAdapter(), *other = IPCopyTestAdapter(adapter);
    other.serviceName = @"Lighting";

    XCTAssertTrue([adapter sameAttachment:other]);

    other.registryID = @124;

    XCTAssertFalse([adapter sameAttachment:other]);

    other = IPCopyTestAdapter(adapter);
    other.mac = @"00:11:22:33:44:66";

    XCTAssertFalse([adapter sameAttachment:other]);

    other = IPCopyTestAdapter(adapter);
    other.serviceID = @"other";

    XCTAssertFalse([adapter sameAttachment:other]);
}

- (void)testPresetMatchingIncludesMaskGatewayAndDNS
{
    IPAdapterSnapshot *adapter = IPTestAdapter();
    IPPreset *preset = IPTestPreset();
    adapter.ipv4 = IPDesiredIPv4(adapter.ipv4, preset, NO);
    adapter.dns = IPDesiredDNS(adapter.dns, preset, NO);

    XCTAssertTrue([adapter matchesPreset:preset]);

    preset.gateway = @"192.168.10.1";

    XCTAssertFalse([adapter matchesPreset:preset]);

    preset.gateway = @"";
    preset.dns = @[@"1.1.1.1"];

    XCTAssertFalse([adapter matchesPreset:preset]);
}

- (void)testConfigurationPreservesUnrelatedKeys
{
    IPAdapterSnapshot *adapter = IPTestAdapter();
    NSDictionary *v4 = IPDesiredIPv4(adapter.ipv4, IPTestPreset(), NO),
                 *dns = IPDesiredDNS(adapter.dns, IPTestPreset(), NO);

    XCTAssertEqualObjects(v4[@"Unrelated"], @YES);
    XCTAssertEqualObjects(v4[@"DHCPClientID"], @"desk");
    XCTAssertEqualObjects(dns[@"SearchDomains"], @[@"studio.example"]);
    XCTAssertNil(dns[@"ServerAddresses"]);
    XCTAssertNil(v4[@"Router"]);
}

- (void)testDHCPRemovesStaticSettingsAndManualDNS
{
    IPPreset *preset = IPTestPreset();
    preset.gateway = @"192.168.10.1";
    IPAdapterSnapshot *adapter = IPTestAdapter();
    adapter.ipv4 = IPDesiredIPv4(adapter.ipv4, preset, NO);
    adapter.ipv4 = IPDesiredIPv4(adapter.ipv4, nil, YES);
    adapter.dns = IPDesiredDNS(adapter.dns, nil, YES);

    XCTAssertTrue(adapter.isAutomatic);
    XCTAssertNil(adapter.ipv4[@"Addresses"]);
    XCTAssertNil(adapter.ipv4[@"SubnetMasks"]);
    XCTAssertNil(adapter.ipv4[@"Router"]);
}

- (void)testSecureCodingRoundTrip
{
    IPApplyRequest *request = [IPApplyRequest new];
    request.expected = IPTestAdapter();
    request.expected.wiFi = YES;
    request.preset = IPTestPreset();
    NSError *error;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:request requiringSecureCoding:YES
                                                         error:&error];

    XCTAssertNotNil(data);

    IPApplyRequest *decoded =
        [NSKeyedUnarchiver unarchivedObjectOfClass:IPApplyRequest.class fromData:data error:&error];

    XCTAssertNotNil(decoded);
    XCTAssertTrue(decoded.expected.isWiFi);
    XCTAssertTrue([decoded.expected sameConfiguration:request.expected]);
    XCTAssertEqualObjects(decoded.preset.JSON, request.preset.JSON);
    XCTAssertNotNil(IPHelperInterface());
}

- (void)testConnectionRequiresLinkAndActiveIPv4Address
{
    IPAdapterSnapshot *adapter = IPTestAdapter();
    adapter.linkActive = YES;
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusNotConnected);

    adapter.activeAddresses = @[@"0.0.0.0", @"bad", @"127.0.0.1", @"::1"];
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusNotConnected);
    adapter.activeAddresses = @[@"192.168.10.20"];
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusConnected);
    adapter.linkActive = NO;
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusNotConnected);
}

- (void)testAutomaticLinkLocalAddressIsSelfAssigned
{
    IPAdapterSnapshot *adapter = IPTestAdapter();
    adapter.linkActive = YES;
    adapter.activeAddresses = @[@"169.254.10.20"];
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusSelfAssigned);
    adapter.activeAddresses = @[@"169.254.10.20", @"10.0.0.20"];
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusConnected);
    adapter.activeAddresses = @[@"169.254.10.20"];
    adapter.linkActive = NO;
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusNotConnected);
}

- (void)testManualConfigurationNeedsAnActiveAddress
{
    IPAdapterSnapshot *adapter = IPTestAdapter();
    adapter.linkActive = YES;
    adapter.ipv4 = IPDesiredIPv4(adapter.ipv4, IPTestPreset(), NO);
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusNotConnected);
    adapter.activeAddresses = @[@"192.168.10.20"];
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusConnected);
}

- (void)testExplicitManualLinkLocalAddressIsNotSelfAssigned
{
    IPAdapterSnapshot *adapter = IPTestAdapter();
    IPPreset *preset = IPTestPreset();
    preset.address = @"169.254.10.20";
    preset.mask = @"255.255.0.0";
    adapter.ipv4 = IPDesiredIPv4(adapter.ipv4, preset, NO);
    adapter.linkActive = YES;
    adapter.activeAddresses = @[preset.address];
    XCTAssertEqual(adapter.connectionStatus, IPConnectionStatusConnected);
}

@end
