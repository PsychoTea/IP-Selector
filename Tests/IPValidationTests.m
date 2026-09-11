#import "IPTestSupport.h"

@interface IPValidationTests : XCTestCase
@end

@implementation IPValidationTests

- (void)testSubnetMasks
{
    XCTAssertEqualObjects(IPSubnetMask(@"/24"), @"255.255.255.0");
    XCTAssertEqualObjects(IPSubnetMask(@"32"), @"255.255.255.255");
    XCTAssertEqualObjects(IPSubnetMask(@"0"), @"0.0.0.0");

    for (NSString *value in @[@"/33", @"-1", @"abc", @"255.0.255.0", @"24x", @""]) {
        XCTAssertNil(IPSubnetMask(value));
    }
}

- (void)testAddressValidation
{
    for (NSString *value in @[
             @"999.1.1.1",
             @"192.168.10.0",
             @"192.168.10.255",
             @"224.0.0.1",
             @"127.0.0.1",
             @"0.0.0.0"
         ]) {
        IPPreset *preset = IPTestPreset();
        preset.address = value;

        XCTAssertFalse([preset validate:NULL], @"%@", value);
    }
}

- (void)testPointToPointAndHostMasks
{
    IPPreset *preset = IPTestPreset();
    preset.address = @"10.0.0.0";
    preset.mask = @"/31";
    preset.gateway = @"10.0.0.1";

    XCTAssertTrue([preset validate:NULL]);

    preset.mask = @"/32";
    preset.gateway = @"";

    XCTAssertTrue([preset validate:NULL]);
}

- (void)testGatewayValidation
{
    IPPreset *preset = IPTestPreset();
    for (NSString *value in
        @[@"192.168.11.1", @"192.168.10.20", @"192.168.10.0", @"192.168.10.255", @"wrong"]) {
        preset.gateway = value;

        XCTAssertFalse([preset validate:NULL]);
    }

    preset.gateway = @"192.168.10.1";

    XCTAssertTrue([preset validate:NULL]);
}

- (void)testDNSValidation
{
    IPPreset *preset = IPTestPreset();
    preset.dns = @[@"1.1.1.1", @"2606:4700:4700::1111"];

    XCTAssertTrue([preset validate:NULL]);

    for (NSString *s in @[@"example.com", @"0.0.0.0", @"::", @"ff02::1", @"1.2.3.999"]) {
        preset.dns = @[s];

        XCTAssertFalse([preset validate:NULL]);
    }
}

- (void)testMACNormalization
{
    XCTAssertEqualObjects(IPNormalizedMAC(@"a0-b1-c2-d3-e4-f5"), @"A0:B1:C2:D3:E4:F5");

    for (NSString *s in
        @[@"", @"bad", @"00:00:00:00:00:00", @"FF:FF:FF:FF:FF:FF", @"01:00:00:00:00:01"]) {

        XCTAssertNil(IPNormalizedMAC(s));
    }
}

- (void)testMalformedPresetTypesAreRejected
{
    NSMutableDictionary *document = [IPTestPreset().JSON mutableCopy];
    document[@"dns"] = @"1.1.1.1";

    XCTAssertNil([IPPreset fromJSON:document error:NULL]);

    document[@"dns"] = @[@1];

    XCTAssertNil([IPPreset fromJSON:document error:NULL]);

    document[@"dns"] = @[];
    document[@"address"] = @17;

    XCTAssertNil([IPPreset fromJSON:document error:NULL]);
}

@end
