#import "IPTestSupport.h"
#import "IPSettingsController.h"
#import "IPPresetListCell.h"

@interface IPSettingsControllerTests : IPTemporaryDirectoryTestCase
@end

@implementation IPSettingsControllerTests

- (void)testPresetCellOwnsItsLabels
{
    [NSApplication sharedApplication];
    IPPresetListCell *cell;
    @autoreleasepool {
        cell = [[IPPresetListCell alloc] initWithFrame:NSMakeRect(0, 0, 250, 52)];
        cell.textField.stringValue = @"Audio";
        cell.addressLabel.stringValue = @"192.168.1.20";
    }

    XCTAssertNotNil(cell.textField);
    XCTAssertEqual(cell.textField.superview, cell);
    XCTAssertEqual(cell.addressLabel.superview, cell);
    XCTAssertEqualObjects(cell.textField.stringValue, @"Audio");
    XCTAssertEqualObjects(cell.addressLabel.stringValue, @"192.168.1.20");
}

- (void)testSettingsWindowCanReopenAfterClosing
{
    [NSApplication sharedApplication];
    IPSettingsController *controller = [[IPSettingsController alloc] initWithStore:self.store];
    NSWindow *window = controller.window;
    [controller showWindow:nil];
    XCTAssertTrue(window.visible);
    [controller close];
    XCTAssertFalse(window.visible);
    [controller showWindow:nil];
    XCTAssertEqual(controller.window, window);
    XCTAssertTrue(window.visible);
    [controller close];
}

- (void)testSettingsWindowReturnsToAnAttachedScreen
{
    [NSApplication sharedApplication];
    IPSettingsController *controller = [[IPSettingsController alloc] initWithStore:self.store];
    [controller.window setFrameOrigin:NSMakePoint(-100000, -100000)];
    [controller showWindow:nil];
    BOOL onScreen = NO;
    for (NSScreen *screen in NSScreen.screens) {
        onScreen |= NSIntersectsRect(controller.window.frame, screen.visibleFrame);
    }

    XCTAssertTrue(onScreen);
    XCTAssertTrue(controller.window.visible);
    [controller close];
}

- (void)testSelectionControlsAndEditorLayout
{
    [NSApplication sharedApplication];
    IPPresetStore *store = self.store;
    IPPreset *first = IPTestPreset();
    IPPreset *second = IPTestPreset();
    second.name = @"Audio";
    XCTAssertTrue(([store replacePresets:@[first, second] error:nil]));
    IPSettingsController *controller = [[IPSettingsController alloc] initWithStore:store];
    NSTableView *table = [controller valueForKey:@"table"];
    NSButton *up = [controller valueForKey:@"moveUp"];
    NSButton *down = [controller valueForKey:@"moveDown"];
    NSButton *duplicate = [controller valueForKey:@"duplicate"];
    NSButton *delete = [controller valueForKey:@"delete"];
    XCTAssertEqual(table.selectedRow, 0);
    XCTAssertFalse(up.enabled);
    XCTAssertTrue(down.enabled);
    XCTAssertTrue(duplicate.enabled);
    XCTAssertTrue(delete.enabled);

    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    XCTAssertTrue(up.enabled);
    XCTAssertFalse(down.enabled);
    NSTextField *name = [controller valueForKey:@"name"];
    XCTAssertEqualObjects(name.stringValue, @"Audio");
    [controller.window.contentView layoutSubtreeIfNeeded];
    NSRect previous = NSZeroRect;
    CGFloat previousGap = 0;
    for (NSString *key in @[@"name", @"address", @"mask", @"gateway", @"dns"]) {
        NSTextField *field = [controller valueForKey:key];
        NSRect rect = [field convertRect:field.bounds toView:controller.window.contentView];
        XCTAssertGreaterThanOrEqual(rect.size.height, 28);
        if (!NSIsEmptyRect(previous)) {
            XCTAssertEqualWithAccuracy(rect.origin.x, previous.origin.x, 0.5);
            XCTAssertEqualWithAccuracy(rect.size.width, previous.size.width, 0.5);
            CGFloat gap = fabs(NSMidY(rect) - NSMidY(previous));
            if (previousGap) {
                XCTAssertEqualWithAccuracy(gap, previousGap, 0.5);
            }
            previousGap = gap;
        }
        previous = rect;
    }
    [controller close];
}

- (void)testEmptyListDisablesSelectionActions
{
    [NSApplication sharedApplication];
    IPSettingsController *controller = [[IPSettingsController alloc] initWithStore:self.store];
    for (NSString *key in @[@"duplicate", @"delete", @"moveUp", @"moveDown"]) {
        NSButton *button = [controller valueForKey:key];
        XCTAssertFalse(button.enabled);
    }
    NSTextField *name = [controller valueForKey:@"name"];
    XCTAssertEqualObjects(name.stringValue, @"");
    [controller close];
}

- (void)testStoreChangesPreserveSelectionAndUnsavedEditsByIdentifier
{
    [NSApplication sharedApplication];
    IPPresetStore *store = self.store;
    IPPreset *first = IPTestPreset();
    IPPreset *second = IPTestPreset();
    XCTAssertTrue(([store replacePresets:@[first, second] error:nil]));
    IPSettingsController *controller = [[IPSettingsController alloc] initWithStore:store];
    NSTableView *table = [controller valueForKey:@"table"];
    NSTextField *name = [controller valueForKey:@"name"];
    name.stringValue = @"Unsaved edit";
    XCTAssertTrue([store movePresetWithIdentifier:first.identifier by:1 error:nil]);
    XCTAssertEqual(table.selectedRow, 1);
    XCTAssertEqualObjects(name.stringValue, @"Unsaved edit");
    XCTAssertTrue([store removePresetWithIdentifier:second.identifier error:nil]);
    XCTAssertEqual(table.selectedRow, 0);
    XCTAssertEqualObjects(name.stringValue, @"Unsaved edit");
    [controller close];
}

@end
