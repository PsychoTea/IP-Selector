#import "IPMenuController.h"
#import "IPPresetStore.h"
#import "IPNetworkMonitor.h"
#import "IPHelperClient.h"
#import "IPQuickChangeController.h"
#import "IPQuickChangeRequestBuilder.h"
#import "IPRecentAddresses.h"
#import "IPAdapterMenu.h"

@interface IPMenuController () <IPAdapterMenuActions>
@end

@implementation IPMenuController {
    IPPresetStore *_store;
    IPNetworkMonitor *_monitor;
    IPHelperClient *_client;
    IPRecentAddresses *_history;
    IPQuickChangeController *_quickChange;
    IPAdapterSnapshot *_undoState;
    NSString *_undoToken;
    BOOL _busy;
    BOOL _tracking;
}

- (instancetype)initWithStore:(IPPresetStore *)store
                      monitor:(IPNetworkMonitor *)monitor
                       client:(IPHelperClient *)client
{
    if ((self = [super init])) {
        _store = store;
        _monitor = monitor;
        _client = client;
        _history = [[IPRecentAddresses alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        _menu = [[NSMenu alloc] initWithTitle:@"IP Selector"];
        _menu.autoenablesItems = NO;
        _menu.delegate = self;

        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:)
                                                   name:IPAdaptersChanged
                                                 object:monitor];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:)
                                                   name:IPPresetsChanged
                                                 object:store];

        __weak typeof(self) weakSelf = self;
        client.connectionLost = ^{
            [weakSelf forgetUndo];
        };
    }

    return self;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [_monitor refresh];
    if (_tracking) {
        [self refreshVisibleAdapters];
    } else {
        [self rebuildMenu];
    }
}

- (void)menuWillOpen:(NSMenu *)menu
{
    _tracking = YES;
}

- (void)menuDidClose:(NSMenu *)menu
{
    _tracking = NO;
}

- (void)changed:(NSNotification *)note
{
    if (_tracking) {
        if ([note.name isEqual:IPPresetsChanged]) {
            // Preset edits can change the actions and their order.
            [_menu cancelTracking];
        } else {
            [self refreshVisibleAdapters];
        }
    }

    if (_undoState && !_busy) {
        BOOL valid = NO;
        for (IPAdapterSnapshot *adapter in _monitor.adapters) {
            if ([adapter sameConfiguration:_undoState]) {
                valid = YES;
                break;
            }
        }

        if (!valid) {
            [self forgetUndo];
        }
    }
}

- (NSString *)aliasFor:(IPAdapterSnapshot *)adapter
{
    if (!adapter.mac.length) {
        return nil;
    }

    NSMutableSet *attachments = [NSMutableSet set];
    for (IPAdapterSnapshot *candidate in _monitor.adapters) {
        if ([candidate.mac isEqual:adapter.mac]) {
            [attachments addObject:candidate.registryID];
        }
    }

    return attachments.count == 1 ? _store.aliases[adapter.mac] : nil;
}

- (void)rebuildMenu
{
    [_menu removeAllItems];
    NSArray *adapters =
        [_monitor.adapters sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(
            IPAdapterSnapshot *first, IPAdapterSnapshot *second) {
            if (first.isWiFi == second.isWiFi) {
                return NSOrderedSame;
            }

            return first.isWiFi ? NSOrderedAscending : NSOrderedDescending;
        }];
    for (IPAdapterSnapshot *adapter in adapters) {
        NSString *title = [NSString stringWithFormat:@"%@ (%@)",
            [self aliasFor:adapter] ?: adapter.serviceName,
            adapter.bsdName];
        NSMenuItem *item = [_menu addItemWithTitle:title action:nil keyEquivalent:@""];
        IPAdapterMenu *submenu = [[IPAdapterMenu alloc] initWithAdapter:adapter
                                                                presets:_store.presets
                                                                 target:self];
        [submenu refreshWithAdapter:adapter busy:_busy];
        item.submenu = submenu;
        item.enabled = !_busy;
    }

    if (!_monitor.adapters.count) {
        NSMenuItem *empty = [_menu addItemWithTitle:@"No connected adapters" action:nil
                                      keyEquivalent:@""];
        empty.enabled = NO;
    }

    if (_busy) {
        NSMenuItem *progress = [_menu addItemWithTitle:@"Applying settings…" action:nil
                                         keyEquivalent:@""];
        progress.enabled = NO;
    }

    [_menu addItem:NSMenuItem.separatorItem];
    if (_client.service.status != SMAppServiceStatusEnabled) {
        NSMenuItem *approval = [_menu addItemWithTitle:@"Approve Helper…"
                                                action:@selector(approveHelper:)
                                         keyEquivalent:@""];
        approval.target = self;
    }

    NSMenuItem *manage = [_menu addItemWithTitle:@"Manage Presets…" action:@selector(manage:)
                                   keyEquivalent:@""];
    manage.target = self;
    [_menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *network = [_menu addItemWithTitle:@"Open Network Settings…"
                                           action:@selector(openNetworkSettings:)
                                    keyEquivalent:@""];
    network.target = self;
    network.image = [NSImage imageWithSystemSymbolName:@"gearshape"
                              accessibilityDescription:@"Settings"];
    NSMenuItem *quit = [_menu addItemWithTitle:@"Quit IP Selector" action:@selector(terminate:)
                                 keyEquivalent:@"q"];
    quit.target = NSApp;
}

- (void)refreshVisibleAdapters
{
    // Keep the same rows under the pointer. New adapters appear on the next opening.
    for (NSMenuItem *item in _menu.itemArray) {
        if (![item.submenu isKindOfClass:IPAdapterMenu.class]) {
            continue;
        }

        IPAdapterMenu *submenu = (IPAdapterMenu *)item.submenu;
        IPAdapterSnapshot *current = nil;
        for (IPAdapterSnapshot *adapter in _monitor.adapters) {
            if ([adapter sameAttachment:submenu.adapter]) {
                current = adapter;
                break;
            }
        }

        item.enabled = current && !_busy;
        [submenu refreshWithAdapter:current busy:_busy];
    }
}

- (void)apply:(NSMenuItem *)sender
{
    IPApplyRequest *request = sender.representedObject;
    if ([request isKindOfClass:IPApplyRequest.class]) {
        [self applyRequest:request];
    }
}

- (BOOL)applyRequest:(IPApplyRequest *)request
{
    if (_busy) {
        return NO;
    }

    if (_client.service.status != SMAppServiceStatusEnabled) {
        [self approveHelper:nil];
        return NO;
    }

    // The helper checks this service and physical attachment again under its lock.
    _busy = YES;
    [_client apply:request completion:^(IPApplyResult *result) {
        if (result.success && request.preset && [result.current matchesPreset:request.preset]) {
            [self->_history recordAddress:request.preset.address];
        }

        [self finish:result];
    }];

    return YES;
}

- (void)quickChange:(NSMenuItem *)sender
{
    if (_busy) {
        return;
    }

    IPAdapterSnapshot *adapter = sender.representedObject;
    [_quickChange close];
    _quickChange = [[IPQuickChangeController alloc] initWithAdapter:adapter history:_history];
    __weak typeof(self) weakSelf = self;
    _quickChange.applyPreset = ^BOOL(IPPreset *preset) {
        return [weakSelf applyQuickPreset:preset toAdapter:adapter];
    };
    [NSApp activateIgnoringOtherApps:YES];
    [_quickChange showWindow:nil];
    [_quickChange.window makeKeyAndOrderFront:nil];
}

- (BOOL)applyQuickPreset:(IPPreset *)preset toAdapter:(IPAdapterSnapshot *)expected
{
    if (_busy) {
        [self showQuickChangeError:@"Another change is in progress. Wait for it to finish."];
        return NO;
    }

    IPQuickChangeRequestBuilder *builder = [IPQuickChangeRequestBuilder new];
    NSError *error = nil;
    IPApplyRequest *request = [builder requestForPreset:preset adapter:expected error:&error];
    if (!request) {
        [self showQuickChangeError:error.localizedDescription];
        return NO;
    }

    return [self applyRequest:request];
}

- (void)showQuickChangeError:(NSString *)message
{
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Cannot apply this IP address";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:_quickChange.window completionHandler:nil];
}

- (void)undo:(id)sender
{
    if (!_undoToken || _busy) {
        return;
    }

    _busy = YES;
    [_client undo:_undoToken completion:^(IPApplyResult *result) {
        [self finish:result];
    }];
}

- (void)finish:(IPApplyResult *)result
{
    _busy = NO;
    if (result.success) {
        // A no-op can preserve an earlier Undo record on another adapter.
        if (![result.undoToken isEqual:_undoToken]) {
            _undoToken = result.undoToken;
            _undoState = result.undoToken ? result.current : nil;
        }
    } else {
        [self forgetUndo];
    }

    if (_tracking) {
        [_menu cancelTracking];
    }

    [_monitor refresh];
    if (!result.success) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Network change failed";
        alert.informativeText
            = result.message ?: @"Check the adapter settings and helper approval, then try again.";
        [alert addButtonWithTitle:@"OK"];
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
    }
}

- (void)forgetUndo
{
    _undoToken = nil;
    _undoState = nil;
}

- (void)approveHelper:(id)sender
{
    if (self.openApproval) {
        self.openApproval();
    }
}

- (void)manage:(id)sender
{
    if (self.openSettings) {
        self.openSettings();
    }
}

- (void)openNetworkSettings:(id)sender
{
    NSURL *url =
        [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Network-Settings.extension"];
    if (![NSWorkspace.sharedWorkspace openURL:url]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Cannot open Network Settings";
        alert.informativeText = @"Open System Settings, then select Network.";
        [alert addButtonWithTitle:@"OK"];
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
    }
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
