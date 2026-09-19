#import "IPSettingsController.h"
#import "IPPresetStore.h"
#import "IPPresetListCell.h"
#import <ServiceManagement/ServiceManagement.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSTextField *IPLabel(NSString *text)
{
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:12];

    return label;
}

static NSButton *IPButton(NSString *text, id target, SEL action)
{
    return [NSButton buttonWithTitle:text target:target action:action];
}

static NSStackView *IPStack(NSArray<NSView *> *views, NSUserInterfaceLayoutOrientation orientation)
{
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = orientation;
    stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical
        ? NSLayoutAttributeLeading
        : NSLayoutAttributeCenterY;
    stack.spacing = 8;

    return stack;
}

static NSBox *IPSeparator(void)
{
    NSBox *separator = [NSBox new];
    separator.boxType = NSBoxSeparator;

    return separator;
}

static NSTextField *IPHeading(NSString *text)
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont boldSystemFontOfSize:17];

    return label;
}

static NSButton *IPIconButton(NSString *symbol, NSString *label, id target, SEL action)
{
    NSButton *button = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbol
                                                           accessibilityDescription:label]
                                          target:target
                                          action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.toolTip = label;
    button.accessibilityLabel = label;
    [button.widthAnchor constraintEqualToConstant:30].active = YES;

    return button;
}

static void IPFillStackWidth(NSStackView *stack)
{
    for (NSView *view in stack.arrangedSubviews) {
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
}

@interface IPSettingsController () <NSTableViewDataSource, NSTableViewDelegate>
@end
@implementation IPSettingsController {
    IPPresetStore *_store;
    NSTableView *_table;
    NSStackView *_root;
    NSTextField *_name;
    NSTextField *_address;
    NSTextField *_mask;
    NSTextField *_gateway;
    NSTextField *_dns;
    NSTextField *_notice;
    NSButton *_login;
    NSButton *_duplicate;
    NSButton *_delete;
    NSButton *_moveUp;
    NSButton *_moveDown;
    NSButton *_save;
    NSTextField *_editorHeading;
    NSTextField *_listSummary;
    NSString *_editingID;
    NSTimer *_statusTimer;
    BOOL _reloadingPresets;
}

- (instancetype)initWithStore:(IPPresetStore *)store
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 540)
                                                   styleMask:NSWindowStyleMaskTitled
        | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    if ((self = [super initWithWindow:window])) {
        _store = store;
        window.title = [NSString stringWithFormat:@"%@ — Presets and Settings",
            [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                ?: @"IP Selector"];
        window.releasedWhenClosed = NO;
        window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
        [self build];
        [window center];

        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(storeChanged:)
                                                   name:IPPresetsChanged
                                                 object:store];

        __weak typeof(self) weakSelf = self;
        _statusTimer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES
                                                         block:^(NSTimer *timer) {
                                                             if (weakSelf.window.visible) {
                                                                 [weakSelf updateStatus];
                                                             }
                                                         }];
    }

    return self;
}

- (void)build
{
    NSStackView *list = [self makePresetList];
    NSStackView *editor = [self makePresetEditor];
    NSBox *divider = IPSeparator();
    NSStackView *columns
        = IPStack(@[list, divider, editor], NSUserInterfaceLayoutOrientationHorizontal);
    columns.alignment = NSLayoutAttributeTop;
    columns.spacing = 20;
    [NSLayoutConstraint activateConstraints:@[
        [list.widthAnchor constraintEqualToConstant:250],
        [columns.heightAnchor constraintEqualToConstant:390],
        [list.heightAnchor constraintEqualToAnchor:columns.heightAnchor],
        [editor.heightAnchor constraintEqualToAnchor:columns.heightAnchor],
        [divider.widthAnchor constraintEqualToConstant:1],
        [divider.heightAnchor constraintEqualToAnchor:columns.heightAnchor]
    ]];

    _notice = IPLabel(_store.loadError.localizedDescription ?: @"");
    _notice.textColor = _store.loadError ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    _notice.hidden = !_store.loadError;

    _login = [NSButton checkboxWithTitle:@"Open at login" target:self
                                  action:@selector(toggleLogin:)];
    NSStackView *footer = IPStack(
        @[
            IPButton(@"Import…", self, @selector(importPresets:)),
            IPButton(@"Export…", self, @selector(exportPresets:)),
            [NSView new],
            _login
        ],
        NSUserInterfaceLayoutOrientationHorizontal);

    _root = IPStack(
        @[columns, _notice, IPSeparator(), footer], NSUserInterfaceLayoutOrientationVertical);
    _root.spacing = 16;
    _root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:_root];
    [NSLayoutConstraint activateConstraints:@[
        [_root.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor
                                            constant:24],
        [_root.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:24],
        [_root.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor
                                             constant:-24],
        [_root.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor
                                           constant:-24]
    ]];
    IPFillStackWidth(_root);
    [self updateListActions];
    if (_store.presets.count) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }

    [self updateStatus];
    [self fitWindow];
}

- (NSStackView *)makePresetList
{
    NSTextField *heading = IPHeading(@"Saved Presets");
    _listSummary = IPLabel(@"");
    _listSummary.textColor = NSColor.secondaryLabelColor;
    NSStackView *header
        = IPStack(@[heading, _listSummary], NSUserInterfaceLayoutOrientationVertical);
    header.spacing = 4;

    _table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"preset"];
    column.width = 230;
    [_table addTableColumn:column];
    _table.headerView = nil;
    _table.delegate = self;
    _table.dataSource = self;
    _table.rowHeight = 52;
    _table.style = NSTableViewStyleFullWidth;
    _table.intercellSpacing = NSMakeSize(0, 2);

    NSScrollView *scroll = [NSScrollView new];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:230].active = YES;

    NSButton *add = IPButton(@"New", self, @selector(newPreset:));
    add.image = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:nil];
    add.imagePosition = NSImageLeading;
    _duplicate
        = IPIconButton(@"plus.square.on.square", @"Duplicate preset", self, @selector(duplicate:));
    _delete = IPIconButton(@"trash", @"Delete preset", self, @selector(deletePreset:));
    _moveUp = IPIconButton(@"chevron.up", @"Move preset up", self, @selector(moveUp:));
    _moveDown = IPIconButton(@"chevron.down", @"Move preset down", self, @selector(moveDown:));
    NSStackView *actions = IPStack(@[add, _duplicate, _delete, [NSView new], _moveUp, _moveDown],
        NSUserInterfaceLayoutOrientationHorizontal);
    actions.spacing = 4;

    NSStackView *list
        = IPStack(@[header, scroll, actions], NSUserInterfaceLayoutOrientationVertical);
    list.spacing = 12;
    IPFillStackWidth(list);

    return list;
}

- (NSStackView *)makePresetEditor
{
    _editorHeading = IPHeading(@"New Preset");
    NSTextField *description = IPLabel(@"Use this preset with any adapter.");
    description.textColor = NSColor.secondaryLabelColor;
    NSStackView *header
        = IPStack(@[_editorHeading, description], NSUserInterfaceLayoutOrientationVertical);
    header.spacing = 4;

    _name = [NSTextField textFieldWithString:@""];
    _address = [NSTextField textFieldWithString:@""];
    _mask = [NSTextField textFieldWithString:@"255.255.255.0"];
    _gateway = [NSTextField textFieldWithString:@""];
    _dns = [NSTextField textFieldWithString:@""];
    _address.placeholderString = @"192.168.1.20";
    _mask.toolTip = @"Subnet mask or CIDR prefix, such as /24";
    _gateway.placeholderString = @"Optional";
    _dns.placeholderString = @"Optional";

    NSArray *inputs = @[_name, _address, _mask, _gateway, _dns];
    NSArray *titles = @[@"Name", @"IP address", @"Subnet mask", @"Gateway", @"DNS servers"];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < inputs.count; i++) {
        NSTextField *field = inputs[i];
        field.accessibilityLabel = titles[i];
        [field.heightAnchor constraintEqualToConstant:28].active = YES;
        [rows addObject:@[[NSTextField labelWithString:titles[i]], field]];
        if (i + 1 < inputs.count) {
            field.nextKeyView = inputs[i + 1];
        }
    }

    NSGridView *form = [NSGridView gridViewWithViews:rows];
    form.rowAlignment = NSGridRowAlignmentNone;
    form.yPlacement = NSGridCellPlacementCenter;
    form.rowSpacing = 10;
    form.columnSpacing = 12;
    [form columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [form columnAtIndex:1].xPlacement = NSGridCellPlacementFill;

    NSTextField *help = IPLabel(
        @"Leave gateway and DNS empty to clear them. Separate DNS servers with spaces or commas.");
    help.textColor = NSColor.secondaryLabelColor;
    _save = IPButton(@"Save Preset", self, @selector(savePreset:));
    _save.keyEquivalent = @"\r";
    [_save setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *saveRow
        = IPStack(@[[NSView new], _save], NSUserInterfaceLayoutOrientationHorizontal);
    NSStackView *editor = IPStack(@[header, IPSeparator(), form, help, [NSView new], saveRow],
        NSUserInterfaceLayoutOrientationVertical);
    editor.spacing = 14;
    IPFillStackWidth(editor);
    self.window.initialFirstResponder = _name;

    return editor;
}

- (void)fitWindow
{
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.window setContentSize:NSMakeSize(800, ceil(_root.fittingSize.height) + 48)];
}

- (void)updateListActions
{
    NSInteger row = _table.selectedRow;
    BOOL selected = row >= 0 && row < (NSInteger)_store.presets.count;
    _duplicate.enabled = selected;
    _delete.enabled = selected;
    _moveUp.enabled = selected && row > 0;
    _moveDown.enabled = selected && row + 1 < (NSInteger)_store.presets.count;
    _listSummary.stringValue = _store.presets.count
        ? [NSString stringWithFormat:@"%lu saved · Available to all adapters",
              (unsigned long)_store.presets.count]
        : @"No presets yet. Select New to add one.";
}

- (void)showWindow:(id)sender
{
    NSWindow *window = self.window;
    BOOL onScreen = NO;
    for (NSScreen *screen in NSScreen.screens) {
        if (NSIntersectsRect(window.frame, screen.visibleFrame)) {
            onScreen = YES;
            break;
        }
    }

    if (!onScreen) {
        [window center];
    }

    [NSApp activate];
    if (window.miniaturized) {
        [window deminiaturize:sender];
    }

    [super showWindow:sender];
    [window makeKeyAndOrderFront:sender];

    [self updateStatus];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _store.presets.count;
}

- (NSView *)tableView:(NSTableView *)tableView
    viewForTableColumn:(NSTableColumn *)tableColumn
                   row:(NSInteger)row
{
    IPPreset *preset = _store.presets[row];
    IPPresetListCell *cell = [tableView makeViewWithIdentifier:@"preset" owner:self];
    if (!cell) {
        cell = [[IPPresetListCell alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"preset";
    }

    cell.textField.stringValue = preset.name;
    cell.addressLabel.stringValue = preset.address;

    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (_reloadingPresets) {
        return;
    }

    [self updateListActions];
    IPPreset *preset = self.selectedPreset;
    if (preset) {
        [self loadPreset:preset];
    }
}

- (IPPreset *)selectedPreset
{
    NSInteger row = _table.selectedRow;

    return row >= 0 && row < (NSInteger)_store.presets.count ? _store.presets[row] : nil;
}

- (void)selectPresetWithIdentifier:(NSString *)identifier
{
    NSUInteger index = [_store indexOfPresetWithIdentifier:identifier];
    if (index != NSNotFound) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    } else {
        [_table deselectAll:nil];
    }

    [self updateListActions];
}

- (void)loadPreset:(IPPreset *)preset
{
    _editingID = preset.identifier;
    _editorHeading.stringValue = @"Edit Preset";
    _name.stringValue = preset.name;
    _address.stringValue = preset.address;
    _mask.stringValue = preset.mask;
    _gateway.stringValue = preset.gateway;
    _dns.stringValue = [preset.dns componentsJoinedByString:@", "];
}

- (void)editNewPreset:(IPPreset *)preset
{
    [_table deselectAll:nil];
    [self loadPreset:preset];
    _editingID = nil;
    _editorHeading.stringValue = @"New Preset";
    [self updateListActions];
    [self showWindow:nil];
    [self.window makeFirstResponder:_name];
}

- (void)newPreset:(id)sender
{
    [self editNewPreset:[IPPreset new]];
}

- (void)duplicate:(id)sender
{
    IPPreset *preset = [self.selectedPreset copy];
    if (!preset) {
        return;
    }

    preset.name = [preset.name stringByAppendingString:@" Copy"];
    [self editNewPreset:preset];
}

- (void)savePreset:(id)sender
{
    IPPreset *preset = [IPPreset new];
    if (_editingID) {
        preset.identifier = _editingID;
    }

    preset.name = [_name.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    preset.address = [_address.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    preset.mask = _mask.stringValue;
    preset.gateway = [_gateway.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    NSArray *parts = [_dns.stringValue
        componentsSeparatedByCharactersInSet:[NSCharacterSet
                                                 characterSetWithCharactersInString:@", \t\r\n"]];
    preset.dns = [parts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(
                                                        NSString *server, NSDictionary *bindings) {
        return server.length > 0;
    }]];

    NSError *error = nil;
    if (![_store savePreset:preset error:&error]) {
        [self report:error];
        return;
    }

    [self loadPreset:preset];
    [self selectPresetWithIdentifier:preset.identifier];
    [self showNotice:@"Preset saved." error:NO];
}

- (void)deletePreset:(id)sender
{
    IPPreset *preset = self.selectedPreset;
    if (!preset) {
        return;
    }

    NSString *identifier = preset.identifier;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Delete this preset?";
    alert.informativeText = preset.name;
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) {
            return;
        }

        NSError *error = nil;
        if (![self->_store removePresetWithIdentifier:identifier error:&error]) {
            [self report:error];
        } else if ([self->_editingID isEqual:identifier]) {
            [self newPreset:nil];
        }
    }];
}

- (void)move:(NSInteger)offset
{
    IPPreset *preset = self.selectedPreset;
    if (!preset) {
        return;
    }

    NSError *error = nil;
    if (![_store movePresetWithIdentifier:preset.identifier by:offset error:&error]) {
        [self report:error];
    } else {
        [self selectPresetWithIdentifier:preset.identifier];
    }
}

- (void)moveUp:(id)sender
{
    [self move:-1];
}

- (void)moveDown:(id)sender
{
    [self move:1];
}

- (void)storeChanged:(NSNotification *)note
{
    BOOL hadSelection = _table.selectedRow >= 0;
    _reloadingPresets = YES;
    [_table reloadData];
    if (hadSelection && _editingID) {
        [self selectPresetWithIdentifier:_editingID];
    } else {
        [_table deselectAll:nil];
    }

    _reloadingPresets = NO;
    [self updateListActions];
}

- (void)showNotice:(NSString *)message error:(BOOL)isError
{
    _notice.stringValue = message;
    _notice.textColor = isError ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    _notice.hidden = NO;
    [self fitWindow];
}

- (void)report:(NSError *)error
{
    [self showNotice:error.localizedDescription ?: @"The operation failed." error:YES];
}

- (void)importPresets:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeJSON];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSError *error;
            if (![self->_store importURL:panel.URL error:&error]) {
                [self report:error];
            } else {
                [self showNotice:@"Presets imported as new entries." error:NO];
            }
        }
    }];
}

- (void)exportPresets:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypeJSON];
    panel.nameFieldStringValue = @"IP Selector Presets.json";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSError *error;
            if (![self->_store exportURL:panel.URL error:&error]) {
                [self report:error];
            } else {
                [self showNotice:@"Presets exported." error:NO];
            }
        }
    }];
}

- (void)updateStatus
{
    _login.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled
        ? NSControlStateValueOn
        : NSControlStateValueOff;
}

- (void)toggleLogin:(id)sender
{
    NSError *error = nil;
    BOOL ok = _login.state == NSControlStateValueOn
        ? [SMAppService.mainAppService registerAndReturnError:&error]
        : [SMAppService.mainAppService unregisterAndReturnError:&error];
    if (!ok) {
        [self report:error];
    }

    [self updateStatus];
}

- (void)dealloc
{
    [_statusTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
