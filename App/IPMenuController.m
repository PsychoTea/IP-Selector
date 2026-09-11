#import "IPMenuController.h"
#import "IPPresetStore.h"
#import "IPNetworkMonitor.h"
#import "IPHelperClient.h"

@interface IPPresetButton : NSButton
@property (nonatomic, strong) IPPreset *preset;
@end
@implementation IPPresetButton
@end

static NSTextField *IPMenuLabel(NSString *text)
{
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:12];

    return label;
}

@implementation IPMenuController {
    IPPresetStore *_store;
    IPNetworkMonitor *_monitor;
    IPHelperClient *_client;
    NSPopUpButton *_adapterPicker;
    NSStackView *_presets;
    NSButton *_dhcp;
    NSButton *_approval;
    NSStackView *_root;
    NSLayoutConstraint *_presetHeight;
    NSTimer *_statusTimer;
    IPAdapterSnapshot *_selected;
    IPAdapterSnapshot *_undoState;
    NSString *_undoToken;
    BOOL _busy;
}

- (instancetype)initWithStore:(IPPresetStore *)store
                      monitor:(IPNetworkMonitor *)monitor
                       client:(IPHelperClient *)client
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _store = store;
        _monitor = monitor;
        _client = client;

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

- (void)loadView
{
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 430, 320)];

    NSTextField *heading = [NSTextField
        labelWithString:[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
            ?: @"IP Selector"];
    heading.font = [NSFont boldSystemFontOfSize:17];

    _adapterPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _adapterPicker.target = self;
    _adapterPicker.action = @selector(selectAdapter:);

    _presets = [NSStackView new];
    _presets.orientation = NSUserInterfaceLayoutOrientationVertical;
    _presets.alignment = NSLayoutAttributeLeading;
    _presets.spacing = 6;
    _presets.edgeInsets = NSEdgeInsetsMake(4, 0, 4, 8);

    NSScrollView *scroll = [NSScrollView new];
    scroll.documentView = _presets;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    _presets.translatesAutoresizingMaskIntoConstraints = NO;
    [_presets.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active = YES;
    _presetHeight = [scroll.heightAnchor constraintEqualToConstant:32];
    _presetHeight.active = YES;

    _dhcp = [NSButton buttonWithTitle:@"Use DHCP" target:self action:@selector(useDHCP:)];
    NSButton *manage = [NSButton buttonWithTitle:@"Manage Presets…" target:self
                                          action:@selector(manage:)];
    NSButton *quit = [NSButton buttonWithTitle:@"Quit" target:NSApp action:@selector(terminate:)];

    NSView *footerSpace = [NSView new];
    NSStackView *footer = [NSStackView stackViewWithViews:@[manage, footerSpace, quit]];
    footer.spacing = 8;
    footer.distribution = NSStackViewDistributionFill;
    for (NSButton *button in @[manage, quit]) {
        [button setContentHuggingPriority:NSLayoutPriorityRequired
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    }

    _approval = [NSButton buttonWithTitle:@"Approve Helper…" target:self
                                   action:@selector(approveHelper:)];

    NSStackView *root = [NSStackView
        stackViewWithViews:@[heading, _adapterPicker, scroll, _dhcp, _approval, footer]];
    _root = root;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 8;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [root.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [root.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:16],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor constant:-16]
    ]];
    for (NSView *view in @[_adapterPicker, scroll, footer]) {
        [view.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
    }

    for (NSView *view in root.arrangedSubviews) {
        [view setContentHuggingPriority:NSLayoutPriorityRequired
                         forOrientation:NSLayoutConstraintOrientationVertical];
    }

    __weak typeof(self) weakSelf = self;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        if (weakSelf.view.window.visible) {
            [weakSelf refreshApprovalStatus];
        }
    }];
    [self render];
}

- (void)refreshApprovalStatus
{
    if (_approval.hidden != (_client.service.status == SMAppServiceStatusEnabled)) {
        [self render];
    }
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    [_monitor refresh];
    [self render];
}

- (void)changed:(NSNotification *)note
{
    if (_selected) {
        IPAdapterSnapshot *replacement = nil;
        for (IPAdapterSnapshot *adapter in _monitor.adapters) {
            if ([adapter sameAttachment:_selected]) {
                replacement = adapter;
            }
        }

        _selected = replacement;
    }

    if (_undoState && !_busy) {
        BOOL valid = NO;
        for (IPAdapterSnapshot *adapter in _monitor.adapters) {
            if ([adapter sameConfiguration:_undoState]) {
                valid = YES;
            }
        }

        if (!valid) {
            _undoToken = nil;
            _undoState = nil;
        }
    }

    if (self.isViewLoaded) {
        [self render];
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

- (void)render
{
    [self updateAdapterPicker];
    [self updatePresetButtons];

    _approval.hidden = _client.service.status == SMAppServiceStatusEnabled;
    _dhcp.title = [_selected isAutomatic] ? @"✓ Use DHCP" : @"Use DHCP";
    _dhcp.enabled = _selected && !_busy;

    [self.view layoutSubtreeIfNeeded];
    self.preferredContentSize = NSMakeSize(430, ceil(_root.fittingSize.height) + 32);
    if (self.contentSizeChanged) {
        self.contentSizeChanged(self.preferredContentSize);
    }
}

- (void)updateAdapterPicker
{
    [_adapterPicker removeAllItems];
    [_adapterPicker addItemWithTitle:@"Select an Ethernet adapter…"];
    for (IPAdapterSnapshot *adapter in _monitor.adapters) {
        NSString *title = [NSString stringWithFormat:@"%@ — %@ (%@)",
            [self aliasFor:adapter] ?: adapter.serviceName,
            adapter.mac.length ? adapter.mac : @"MAC unavailable",
            adapter.bsdName];
        [_adapterPicker addItemWithTitle:title];
        _adapterPicker.lastItem.representedObject = adapter;
        if ([adapter sameAttachment:_selected]) {
            [_adapterPicker selectItem:_adapterPicker.lastItem];
        }
    }

    _adapterPicker.enabled = !_busy;
}

- (void)updatePresetButtons
{
    for (NSView *view in _presets.arrangedSubviews.copy) {
        [_presets removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    if (!_store.presets.count) {
        [_presets
            addArrangedSubview:IPMenuLabel(@"No saved presets. Select Manage Presets to add one.")];
    }

    for (IPPreset *preset in _store.presets) {
        IPPresetButton *button =
            [IPPresetButton buttonWithTitle:[NSString stringWithFormat:@"%@%@ — %@",
                                                [_selected matchesPreset:preset] ? @"✓ " : @"",
                                                preset.name,
                                                preset.address]
                                     target:self
                                     action:@selector(applyPreset:)];
        button.preset = preset;
        button.alignment = NSTextAlignmentLeft;
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        button.toolTip = [NSString stringWithFormat:@"%@ / %@\nGateway: %@\nDNS: %@",
            preset.address,
            preset.mask,
            preset.gateway.length ? preset.gateway : @"None",
            preset.dns.count ? [preset.dns componentsJoinedByString:@", "] : @"No manual servers"];
        button.enabled = _selected && !_busy;
        [_presets addArrangedSubview:button];
        [button.widthAnchor constraintEqualToAnchor:_presets.widthAnchor constant:-8].active = YES;
    }

    _presetHeight.constant = MIN(180, MAX(32, _store.presets.count * 32 + 8));
}

- (void)selectAdapter:(id)sender
{
    _selected = _adapterPicker.selectedItem.representedObject;
    [self render];
}

- (void)applyPreset:(IPPresetButton *)sender
{
    [self applyPreset:sender.preset dhcp:NO];
}

- (void)useDHCP:(id)sender
{
    [self applyPreset:nil dhcp:YES];
}

- (void)applyPreset:(IPPreset *)preset dhcp:(BOOL)dhcp
{
    if (!_selected || _busy) {
        return;
    }

    if (_client.service.status != SMAppServiceStatusEnabled) {
        [self approveHelper:nil];
        return;
    }

    IPApplyRequest *request = [IPApplyRequest new];
    request.expected = _selected;
    request.preset = preset;
    request.useDHCP = dhcp;

    _busy = YES;
    [self render];

    [_client apply:request completion:^(IPApplyResult *result) {
        [self finish:result];
    }];
}

- (void)undo:(id)sender
{
    if (!_undoToken || _busy) {
        return;
    }

    _busy = YES;
    [self render];

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

        if ([result.current sameAttachment:_selected]) {
            _selected = result.current;
        }
    } else {
        _undoToken = nil;
        _undoState = nil;
    }

    [_monitor refresh];
    [self render];
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
    if (self.isViewLoaded) {
        [self render];
    }
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

- (void)dealloc
{
    [_statusTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
