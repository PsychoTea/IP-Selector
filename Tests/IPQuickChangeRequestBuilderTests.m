#import "IPTestSupport.h"
#import "IPQuickChangeRequestBuilder.h"

@interface IPQuickChangeRequestBuilderTests : XCTestCase
@end

@implementation IPQuickChangeRequestBuilderTests

- (void)testRequestUsesFreshConfigurationAndDoesNotMutateTheDraft
{
    IPAdapterSnapshot *expected = IPTestAdapter();
    IPAdapterSnapshot *current = IPCopyTestAdapter(expected);
    current.dns = @{ @"ServerAddresses": @[@"8.8.8.8"] };
    IPPreset *draft = IPTestPreset();
    IPQuickChangeRequestBuilder *builder =
        [[IPQuickChangeRequestBuilder alloc] initWithAdaptersProvider:^NSArray * {
            return @[current];
        } DNSProvider:^NSDictionary *(NSString *serviceID) {
            XCTFail(@"Manual DNS must take precedence over DHCP DNS.");
            return @{};
        }];
    IPApplyRequest *request = [builder requestForPreset:draft adapter:expected error:nil];
    XCTAssertEqual(request.expected, current);
    XCTAssertEqualObjects(request.preset.dns, (@[@"8.8.8.8"]));
    XCTAssertEqualObjects(draft.dns, @[]);
    XCTAssertNotEqual(request.preset, draft);
    XCTAssertFalse(request.useDHCP);
}

- (void)testDHCPDNSIsReadOnlyForTheSelectedService
{
    IPAdapterSnapshot *adapter = IPTestAdapter();
    adapter.dns = @{};
    IPQuickChangeRequestBuilder *builder =
        [[IPQuickChangeRequestBuilder alloc] initWithAdaptersProvider:^NSArray * {
            return @[adapter];
        } DNSProvider:^NSDictionary *(NSString *serviceID) {
            XCTAssertEqualObjects(serviceID, adapter.serviceID);
            return @{@"ServerAddresses": @[@"10.0.0.1"]};
        }];
    IPApplyRequest *request = [builder requestForPreset:IPTestPreset() adapter:adapter error:nil];
    XCTAssertEqualObjects(request.preset.dns, (@[@"10.0.0.1"]));
}

- (void)testStaticConfigurationDoesNotCopyDynamicDNS
{
    IPAdapterSnapshot *adapter = IPTestAdapter();
    adapter.ipv4 = IPDesiredIPv4(adapter.ipv4, IPTestPreset(), NO);
    adapter.dns = @{};
    IPQuickChangeRequestBuilder *builder =
        [[IPQuickChangeRequestBuilder alloc] initWithAdaptersProvider:^NSArray * {
            return @[adapter];
        } DNSProvider:^NSDictionary *(NSString *serviceID) {
            XCTFail(@"A static configuration must retain empty manual DNS.");
            return @{};
        }];
    IPApplyRequest *request = [builder requestForPreset:IPTestPreset() adapter:adapter error:nil];
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.preset.dns, @[]);
}

- (void)testReplacementAdapterCannotReceiveQuickChange
{
    IPAdapterSnapshot *expected = IPTestAdapter();
    IPAdapterSnapshot *replacement = IPCopyTestAdapter(expected);
    replacement.registryID = @456;
    for (NSArray *adapters in @[@[], @[replacement]]) {
        IPQuickChangeRequestBuilder *builder =
            [[IPQuickChangeRequestBuilder alloc] initWithAdaptersProvider:^NSArray * {
                return adapters;
            } DNSProvider:^NSDictionary *(NSString *serviceID) {
                XCTFail(@"A removed or replaced adapter must be rejected before reading DNS.");
                return @{};
            }];
        NSError *error = nil;
        XCTAssertNil([builder requestForPreset:IPTestPreset() adapter:expected error:&error]);
        XCTAssertNotNil(error);
    }
}

- (void)testInvalidDNSFailsBeforeSendingARequest
{
    IPAdapterSnapshot *adapter = IPTestAdapter();
    adapter.dns = @{ @"ServerAddresses": @[@"bad"] };
    IPQuickChangeRequestBuilder *builder =
        [[IPQuickChangeRequestBuilder alloc] initWithAdaptersProvider:^NSArray * {
            return @[adapter];
        } DNSProvider:^NSDictionary *(NSString *serviceID) {
            return @{};
        }];
    NSError *error = nil;
    XCTAssertNil([builder requestForPreset:IPTestPreset() adapter:adapter error:&error]);
    XCTAssertNotNil(error);
}

@end
