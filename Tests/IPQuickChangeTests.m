#import "IPTestSupport.h"
#import "IPQuickChangeController.h"
#import "IPRecentAddresses.h"

@interface IPQuickChangeTests : XCTestCase
@end

@implementation IPQuickChangeTests

- (void)testQuickChangeAcceptsDefaultMaskAndEmptyGateway
{
    IPPreset *preset = IPQuickChangePreset(@"192.168.10.50", @"255.255.255.0", @"", nil);
    XCTAssertEqualObjects(preset.address, @"192.168.10.50");
    XCTAssertEqualObjects(preset.mask, @"255.255.255.0");
    XCTAssertEqualObjects(preset.gateway, @"");
}

- (void)testQuickChangeAcceptsCIDRAndTrimsInput
{
    IPPreset *preset = IPQuickChangePreset(@" 10.0.0.10 ", @" /16 ", @" 10.0.0.1 ", nil);
    XCTAssertEqualObjects(preset.address, @"10.0.0.10");
    XCTAssertEqualObjects(preset.mask, @"255.255.0.0");
    XCTAssertEqualObjects(preset.gateway, @"10.0.0.1");
}

- (void)testInvalidMaskAndGatewayAreRejected
{
    for (NSString *mask in @[@"", @"/33", @"255.0.255.0"]) {
        NSError *error = nil;
        XCTAssertNil(IPQuickChangePreset(@"10.0.0.10", mask, @"", &error));
        XCTAssertNotNil(error);
    }

    for (NSString *gateway in @[@"bad", @"192.168.1.1", @"10.0.0.10"]) {
        NSError *error = nil;
        XCTAssertNil(IPQuickChangePreset(@"10.0.0.10", @"/24", gateway, &error));
        XCTAssertNotNil(error);
    }
}

- (void)testInvalidHostAddressesAreRejected
{
    for (NSString *address in
        @[@"", @"bad", @"999.0.0.1", @"192.168.10.0", @"192.168.10.255", @"127.0.0.1"]) {
        NSError *error = nil;
        XCTAssertNil(IPQuickChangePreset(address, @"/24", @"", &error));
        XCTAssertNotNil(error);
    }
}

- (void)testDialogDefaultsLayoutAndCancel
{
    [NSApplication sharedApplication];
    NSString *suite =
        [@"org.ipselector.dialogtests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    IPRecentAddresses *history = [[IPRecentAddresses alloc] initWithDefaults:defaults];
    [history recordAddress:@"10.0.0.10"];
    IPQuickChangeController *controller =
        [[IPQuickChangeController alloc] initWithAdapter:IPTestAdapter() history:history];
    __block BOOL applied = NO;
    controller.applyPreset = ^BOOL(IPPreset *preset) {
        applied = YES;
        return YES;
    };

    NSStackView *stack = controller.window.contentView.subviews.firstObject;
    NSGridView *grid = (NSGridView *)stack.arrangedSubviews[1];
    NSComboBox *address = (NSComboBox *)[grid cellAtColumnIndex:1 rowIndex:0].contentView;
    NSTextField *mask = (NSTextField *)[grid cellAtColumnIndex:1 rowIndex:1].contentView;
    NSTextField *gateway = (NSTextField *)[grid cellAtColumnIndex:1 rowIndex:2].contentView;
    [controller.window.contentView layoutSubtreeIfNeeded];
    XCTAssertEqualObjects(address.stringValue, @"");
    XCTAssertTrue(address.editable);
    XCTAssertEqualObjects(address.objectValues, (@[@"10.0.0.10"]));
    XCTAssertEqualObjects(mask.stringValue, @"255.255.255.0");
    XCTAssertEqualObjects(gateway.stringValue, @"");
    XCTAssertGreaterThan(address.frame.size.width, 150);
    NSRect addressRect = [address alignmentRectForFrame:address.frame];
    NSRect maskRect = [mask alignmentRectForFrame:mask.frame];
    NSRect gatewayRect = [gateway alignmentRectForFrame:gateway.frame];
    XCTAssertEqualWithAccuracy(addressRect.size.height, maskRect.size.height, 0.5);
    XCTAssertEqualWithAccuracy(maskRect.size.height, gatewayRect.size.height, 0.5);
    CGFloat firstGap = fabs(NSMidY(addressRect) - NSMidY(maskRect));
    CGFloat secondGap = fabs(NSMidY(maskRect) - NSMidY(gatewayRect));
    XCTAssertEqualWithAccuracy(firstGap, secondGap, 0.5);
    XCTAssertLessThan(controller.window.contentView.frame.size.height, 250);

    NSStackView *buttons = (NSStackView *)stack.arrangedSubviews[2];
    NSButton *cancel = (NSButton *)buttons.arrangedSubviews[1];
    NSButton *ok = (NSButton *)buttons.arrangedSubviews[2];
    XCTAssertEqualObjects(cancel.title, @"Cancel");
    XCTAssertEqualObjects(ok.title, @"OK");
    [NSApp sendAction:cancel.action to:cancel.target from:cancel];
    XCTAssertFalse(applied);
    [defaults removePersistentDomainForName:suite];
}

@end
