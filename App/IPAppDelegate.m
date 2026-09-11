#import "IPAppDelegate.h"
#import "IPMenuController.h"
#import "IPSettingsController.h"
#import "IPApprovalController.h"
#import "IPPresetStore.h"
#import "IPNetworkMonitor.h"
#import "IPHelperClient.h"

@implementation IPAppDelegate {
    NSStatusItem *_statusItem;
    NSPopover *_popover;
    IPPresetStore *_store;
    IPNetworkMonitor *_monitor;
    IPHelperClient *_client;
    IPSettingsController *_settings;
    IPApprovalController *_approval;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self createServices];
    [self createStatusItem];
    [self createMainMenu];

    [_monitor start];
    if (_store.loadError) {
        [self showSettings];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self prepareHelper];
    });
}

- (void)createServices
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *support = [fileManager URLsForDirectory:NSApplicationSupportDirectory
                                         inDomains:NSUserDomainMask]
                         .firstObject;
    NSURL *directory = [support URLByAppendingPathComponent:@"IP Selector" isDirectory:YES];
    NSURL *presetsURL = [directory URLByAppendingPathComponent:@"presets.json"];

    _store = [[IPPresetStore alloc] initWithURL:presetsURL];
    _monitor = [IPNetworkMonitor new];
    _client = [IPHelperClient new];
}

- (void)createStatusItem
{
    IPMenuController *menu = [[IPMenuController alloc] initWithStore:_store monitor:_monitor
                                                              client:_client];

    __weak typeof(self) weakSelf = self;
    menu.openSettings = ^{
        [weakSelf showSettings];
    };

    menu.openApproval = ^{
        [weakSelf showApproval:nil];
    };

    menu.contentSizeChanged = ^(NSSize size) {
        [weakSelf resizePopover:size];
    };

    _popover = [NSPopover new];
    _popover.behavior = NSPopoverBehaviorTransient;
    _popover.contentViewController = menu;
    _popover.contentSize = menu.preferredContentSize;

    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    _statusItem.button.image = [NSImage imageWithSystemSymbolName:@"network"
                                         accessibilityDescription:@"IP Selector"];
    _statusItem.button.toolTip = @"IP Selector";
    _statusItem.button.target = self;
    _statusItem.button.action = @selector(toggle:);
}

- (void)createMainMenu
{
    NSMenu *mainMenu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"Quit IP Selector" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *editItem = [NSMenuItem new];
    editItem.title = @"Edit";
    [mainMenu addItem:editItem];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = edit;
    NSApp.mainMenu = mainMenu;
}

- (void)prepareHelper
{
    NSError *error = nil;
    if (![_client.setup prepareOnFirstLaunch:&error]) {
        return;
    }

    if (error || _client.service.status != SMAppServiceStatusEnabled) {
        [self showApproval:error];
    }
}

- (void)resizePopover:(NSSize)size
{
    _popover.contentSize = size;
}

- (void)showApproval:(NSError *)error
{
    [_popover close];
    if (!_approval) {
        _approval = [[IPApprovalController alloc] initWithClient:_client];
    }

    [_approval showWithError:error];
}

- (void)toggle:(id)sender
{
    if (_popover.shown) {
        [_popover close];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
        [_popover showRelativeToRect:_statusItem.button.bounds ofView:_statusItem.button
                       preferredEdge:NSRectEdgeMinY];
    }
}

- (void)showSettings
{
    [_popover close];
    if (!_settings) {
        _settings = [[IPSettingsController alloc] initWithStore:_store];
    }

    [_settings showWindow:nil];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    if (!flag) {
        [self toggle:nil];
    }

    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [_client invalidate];
}

@end
