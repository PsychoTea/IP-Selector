#import "IPApprovalController.h"
#import "IPHelperClient.h"

@implementation IPApprovalController {
    IPHelperClient *_client;
    NSTextField *_heading;
    NSTextField *_message;
    NSImageView *_checkmark;
    NSButton *_open;
    NSButton *_later;
    NSTimer *_timer;
    NSError *_error;
    BOOL _approved;
}

- (instancetype)initWithClient:(IPHelperClient *)client
{
    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 240)
                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    if ((self = [super initWithWindow:window])) {
        _client = client;
        window.title = @"Approve IP Selector";
        [self buildContent];

        __weak typeof(self) weakSelf = self;
        _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
            if (weakSelf.window.visible) {
                [weakSelf refresh];
            }
        }];
        [self refresh];
        [window center];
    }

    return self;
}

- (void)buildContent
{
    _checkmark = [NSImageView new];
    _checkmark.image = [[NSImage imageWithSystemSymbolName:@"checkmark.circle.fill"
                                  accessibilityDescription:@"Helper approved"]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration
                                         configurationWithPointSize:56
                                                             weight:NSFontWeightRegular]];
    _checkmark.contentTintColor = NSColor.systemGreenColor;
    [_checkmark.widthAnchor constraintEqualToConstant:64].active = YES;
    [_checkmark.heightAnchor constraintEqualToConstant:64].active = YES;

    _heading = [NSTextField labelWithString:@""];

    _message = [NSTextField wrappingLabelWithString:@""];
    _message.preferredMaxLayoutWidth = 392;
    [_message.widthAnchor constraintEqualToConstant:392].active = YES;

    _open = [NSButton buttonWithTitle:@"Open System Settings" target:self
                               action:@selector(openSettings:)];
    _open.keyEquivalent = @"\r";

    _later = [NSButton buttonWithTitle:@"Later" target:self action:@selector(dismiss:)];
    _later.keyEquivalent = @"\e";

    NSStackView *buttons = [NSStackView stackViewWithViews:@[_later, _open]];

    NSStackView *root = [NSStackView stackViewWithViews:@[_checkmark, _heading, _message, buttons]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeCenterX;
    root.spacing = 16;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor
                                           constant:24],
        [root.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:24],
        [root.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor
                                            constant:-24]
    ]];
}

- (void)showWithError:(NSError *)error
{
    _error = error;
    [self refresh];
    [self showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)refresh
{
    SMAppServiceStatus status = _client.service.status;
    _approved = status == SMAppServiceStatusEnabled;
    if (_approved || status == SMAppServiceStatusRequiresApproval) {
        _error = nil;
    }

    _checkmark.hidden = !_approved;
    _later.hidden = _approved;
    self.window.title = _approved ? @"IP Selector is ready" : @"Approve IP Selector";
    _heading.stringValue = _approved ? @"You’re all set" : @"Permission to change network settings";
    _heading.font = [NSFont systemFontOfSize:_approved ? 22 : 16 weight:NSFontWeightSemibold];

    NSString *text
        = @"IP Selector uses a helper to change the selected adapter’s IP address and DNS "
          @"settings. macOS requires an administrator to approve this helper.\n\nOpen System "
          @"Settings → General → Login Items & Extensions. Turn on IP Selector under Allow in the "
          @"Background, and approve the request.\n\nYou can create presets now. Network changes "
          @"stay unavailable until you approve the helper.";
    if (_approved) {
        text = @"The helper is approved.";
    }

    if (_error) {
        text = [text stringByAppendingFormat:@"\n\nSetup failed: %@", _error.localizedDescription];
    }

    _message.stringValue = text;
    _message.alignment = _approved ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    _open.title = _approved ? @"Done" : @"Open System Settings";

    [self.window.contentView layoutSubtreeIfNeeded];
    NSView *root = self.window.contentView.subviews.firstObject;
    [self.window setContentSize:NSMakeSize(440, ceil(root.fittingSize.height) + 48)];
}

- (void)openSettings:(id)sender
{
    [self refresh];
    if (_approved) {
        [self close];
        return;
    }

    NSError *error = nil;
    [_client.setup registerHelper:&error];
    _error = error;
    [self refresh];
    if (!_approved) {
        [SMAppService openSystemSettingsLoginItems];
    }
}

- (void)dismiss:(id)sender
{
    [self close];
}

- (void)dealloc
{
    [_timer invalidate];
}

@end
