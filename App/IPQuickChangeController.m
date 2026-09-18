#import "IPQuickChangeController.h"
#import "IPRecentAddresses.h"

IPPreset *IPQuickChangePreset(NSString *address, NSString *mask, NSString *gateway, NSError **error)
{
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    IPPreset *preset = [IPPreset new];
    preset.name = @"Quick Change";
    preset.address = [address stringByTrimmingCharactersInSet:whitespace];
    preset.mask = [mask stringByTrimmingCharactersInSet:whitespace];
    preset.gateway = [gateway stringByTrimmingCharactersInSet:whitespace];
    if (![preset validate:error]) {
        return nil;
    }

    return preset;
}

@implementation IPQuickChangeController {
    NSComboBox *_address;
    NSTextField *_mask;
    NSTextField *_gateway;
}

- (instancetype)initWithAdapter:(IPAdapterSnapshot *)adapter history:(IPRecentAddresses *)history
{
    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 230)
                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    if ((self = [super initWithWindow:window])) {
        window.title = @"IP Selector — Quick IP";
        window.releasedWhenClosed = NO;
        NSTextField *name = [NSTextField
            labelWithString:[NSString
                                stringWithFormat:@"%@ (%@)", adapter.serviceName, adapter.bsdName]];
        name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        name.alignment = NSTextAlignmentCenter;
        name.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];

        _address = [NSComboBox new];
        _address.placeholderString = @"IPv4 address";
        _address.accessibilityLabel = @"IP address";
        _address.completes = NO;
        _address.numberOfVisibleItems = 8;
        [_address addItemsWithObjectValues:history.addresses];

        _mask = [NSTextField textFieldWithString:@"255.255.255.0"];
        _mask.accessibilityLabel = @"Subnet mask";
        _mask.toolTip = @"Subnet mask or CIDR prefix, such as 255.255.255.0 or /24";
        _gateway = [NSTextField textFieldWithString:@""];
        _gateway.placeholderString = @"Optional";
        _gateway.accessibilityLabel = @"Gateway";
        for (NSTextField *field in @[_address, _mask, _gateway]) {
            [field.heightAnchor constraintEqualToConstant:28].active = YES;
            [field setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                            forOrientation:NSLayoutConstraintOrientationVertical];
        }

        NSGridView *fields = [NSGridView gridViewWithViews:@[
            @[[NSTextField labelWithString:@"IP address"], _address],
            @[[NSTextField labelWithString:@"Subnet mask"], _mask],
            @[[NSTextField labelWithString:@"Gateway"], _gateway]
        ]];
        fields.rowAlignment = NSGridRowAlignmentNone;
        fields.rowSpacing = 10;
        fields.columnSpacing = 12;
        [fields columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
        fields.yPlacement = NSGridCellPlacementCenter;

        NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self
                                              action:@selector(cancel:)];
        cancel.keyEquivalent = @"\e";
        NSButton *ok = [NSButton buttonWithTitle:@"OK" target:self action:@selector(apply:)];
        ok.keyEquivalent = @"\r";
        NSStackView *buttons = [NSStackView stackViewWithViews:@[[NSView new], cancel, ok]];
        buttons.spacing = 8;
        for (NSButton *button in @[cancel, ok]) {
            [button setContentHuggingPriority:NSLayoutPriorityRequired
                               forOrientation:NSLayoutConstraintOrientationHorizontal];
            [button.widthAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
        }

        NSStackView *stack = [NSStackView stackViewWithViews:@[name, fields, buttons]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 16;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [window.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor
                                                constant:16],
            [stack.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor
                                                 constant:-16],
            [stack.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:16],
            [stack.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor
                                               constant:-16]
        ]];
        for (NSView *view in stack.arrangedSubviews) {
            [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
            [view setContentHuggingPriority:NSLayoutPriorityRequired
                             forOrientation:NSLayoutConstraintOrientationVertical];
        }

        [window.contentView layoutSubtreeIfNeeded];
        [window setContentSize:NSMakeSize(400, stack.fittingSize.height + 32)];
        window.initialFirstResponder = _address;
        _address.nextKeyView = _mask;
        _mask.nextKeyView = _gateway;
        [window center];
    }

    return self;
}

- (void)apply:(id)sender
{
    NSError *error = nil;
    IPPreset *preset = IPQuickChangePreset(
        _address.stringValue, _mask.stringValue, _gateway.stringValue, &error);
    if (!preset) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Invalid network settings";
        alert.informativeText = error.localizedDescription;
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    if (self.applyPreset && self.applyPreset(preset)) {
        [self close];
    }
}

- (void)cancel:(id)sender
{
    [self close];
}

@end
