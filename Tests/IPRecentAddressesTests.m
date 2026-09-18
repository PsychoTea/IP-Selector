#import <XCTest/XCTest.h>
#import "IPRecentAddresses.h"

@interface IPRecentAddressesTests : XCTestCase
@property (nonatomic, copy) NSString *suite;
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation IPRecentAddressesTests

- (void)setUp
{
    [super setUp];
    self.suite = [@"org.ipselector.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suite];
}

- (void)tearDown
{
    [self.defaults removePersistentDomainForName:self.suite];
    [super tearDown];
}

- (void)testHistoryPersistsAndMovesDuplicatesToFront
{
    IPRecentAddresses *history = [[IPRecentAddresses alloc] initWithDefaults:self.defaults];
    [history recordAddress:@"192.168.1.10"];
    [history recordAddress:@"10.0.0.2"];
    [history recordAddress:@"192.168.1.10"];
    IPRecentAddresses *reloaded = [[IPRecentAddresses alloc] initWithDefaults:self.defaults];
    XCTAssertEqualObjects(reloaded.addresses, (@[@"192.168.1.10", @"10.0.0.2"]));
}

- (void)testHistoryRejectsInvalidDataAndLimitsSize
{
    [self.defaults setObject:@[@"bad", @5, @"127.0.0.1", @"10.0.0.1", @"10.0.0.1"]
                      forKey:@"RecentIPv4Addresses"];
    IPRecentAddresses *history = [[IPRecentAddresses alloc] initWithDefaults:self.defaults];
    XCTAssertEqualObjects(history.addresses, (@[@"10.0.0.1"]));
    [history recordAddress:@"999.0.0.1"];
    XCTAssertEqual(history.addresses.count, 1u);

    for (NSUInteger i = 1; i <= 25; i++) {
        [history recordAddress:[NSString stringWithFormat:@"10.0.0.%lu", (unsigned long)i]];
    }

    XCTAssertEqual(history.addresses.count, 20u);
    XCTAssertEqualObjects(history.addresses.firstObject, @"10.0.0.25");
    XCTAssertEqualObjects(history.addresses.lastObject, @"10.0.0.6");
}

@end
