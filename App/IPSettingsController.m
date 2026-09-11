#import "IPSettingsController.h"
#import "IPPresetStore.h"
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
    NSString *_editingID;
    NSTimer *_statusTimer;
}

- (instancetype)initWithStore:(IPPresetStore *)store
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 744, 440)
                                                   styleMask:NSWindowStyleMaskTitled
        | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    if ((self = [super initWithWindow:window])) {
        _store = store;
        window.title = [NSString stringWithFormat:@"%@ — Presets and Settings",
            [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                ?: @"IP Selector"];
        [window center];
        [self build];

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
    NSStackView *columns = IPStack(@[list, editor], NSUserInterfaceLayoutOrientationHorizontal);
    columns.alignment = NSLayoutAttributeTop;
    columns.spacing = 20;

    _notice = IPLabel(_store.loadError ? _store.loadError.localizedDescription
                                       : @"Select a preset to edit it, or create a new one.");
    [_notice.widthAnchor constraintEqualToConstant:704].active = YES;

    _login = [NSButton checkboxWithTitle:@"Open at login" target:self
                                  action:@selector(toggleLogin:)];
    NSStackView *fileActions = IPStack(
        @[
            IPButton(@"Import…", self, @selector(importPresets:)),
            IPButton(@"Export…", self, @selector(exportPresets:)),
            _login
        ],
        NSUserInterfaceLayoutOrientationHorizontal);

    NSStackView *root
        = IPStack(@[columns, _notice, fileActions], NSUserInterfaceLayoutOrientationVertical);
    _root = root;
    root.spacing = 10;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor
                                           constant:20],
        [root.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:20],
        [root.trailingAnchor
            constraintLessThanOrEqualToAnchor:self.window.contentView.trailingAnchor
                                     constant:-20],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:self.window.contentView.bottomAnchor
                                                    constant:-20]
    ]];

    [self updateStatus];
    [self fitWindow];
}

- (NSStackView *)makePresetList
{
    _table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"preset"];
    column.title = @"Saved presets";
    column.width = 230;
    [_table addTableColumn:column];
    _table.delegate = self;
    _table.dataSource = self;
    _table.rowHeight = 42;

    NSScrollView *scroll = [NSScrollView new];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    [scroll.widthAnchor constraintEqualToConstant:240].active = YES;
    [scroll.heightAnchor constraintEqualToConstant:214].active = YES;

    NSStackView *editActions = IPStack(
        @[
            IPButton(@"New", self, @selector(newPreset:)),
            IPButton(@"Duplicate", self, @selector(duplicate:)),
            IPButton(@"Delete", self, @selector(deletePreset:))
        ],
        NSUserInterfaceLayoutOrientationHorizontal);

    NSStackView *orderActions = IPStack(
        @[
            IPButton(@"Move Up", self, @selector(moveUp:)),
            IPButton(@"Move Down", self, @selector(moveDown:))
        ],
        NSUserInterfaceLayoutOrientationHorizontal);

    NSStackView *list
        = IPStack(@[scroll, editActions, orderActions], NSUserInterfaceLayoutOrientationVertical);

    return list;
}

- (NSStackView *)makePresetEditor
{
    _name = [NSTextField textFieldWithString:@""];
    _address = [NSTextField textFieldWithString:@""];
    _mask = [NSTextField textFieldWithString:@"255.255.255.0"];
    _gateway = [NSTextField textFieldWithString:@""];
    _dns = [NSTextField textFieldWithString:@""];

    _address.placeholderString = @"192.168.10.20";
    _mask.placeholderString = @"255.255.255.0 or /24";
    _gateway.placeholderString = @"Empty = no gateway";
    _dns.placeholderString = @"Empty = clear manual DNS";

    NSGridView *form = [NSGridView gridViewWithViews:@[
        @[IPLabel(@"Name"), _name],
        @[IPLabel(@"IPv4 address"), _address],
        @[IPLabel(@"Subnet mask"), _mask],
        @[IPLabel(@"Gateway"), _gateway],
        @[IPLabel(@"DNS servers"), _dns]
    ]];
    form.rowSpacing = 12;
    form.columnSpacing = 10;
    [form columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [_name.widthAnchor constraintEqualToConstant:320].active = YES;

    NSTextField *help = IPLabel(
        @"Separate DNS addresses with spaces or commas.\nEach preset assigns one IPv4 address.");
    [help.widthAnchor constraintEqualToConstant:444].active = YES;

    NSStackView *editor
        = IPStack(@[form, help, IPButton(@"Save Preset", self, @selector(savePreset:))],
            NSUserInterfaceLayoutOrientationVertical);

    return editor;
}

- (void)fitWindow
{
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.window setContentSize:NSMakeSize(744, ceil(_root.fittingSize.height) + 40)];
}

- (void)showWindow:(id)sender
{
    [super showWindow:sender];
    [NSApp activateIgnoringOtherApps:YES];

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
    NSTextField *label
        = IPLabel([NSString stringWithFormat:@"%@\n%@", preset.name, preset.address]);
    label.lineBreakMode = NSLineBreakByTruncatingTail;

    return label;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger row = _table.selectedRow;
    if (row >= 0 && row < (NSInteger)_store.presets.count) {
        [self loadPreset:_store.presets[row]];
    }
}

- (void)loadPreset:(IPPreset *)preset
{
    _editingID = preset.identifier;
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
    [self showWindow:nil];
}

- (void)newPreset:(id)sender
{
    [self editNewPreset:[IPPreset new]];
}

- (void)duplicate:(id)sender
{
    NSInteger row = _table.selectedRow;
    if (row < 0) {
        return;
    }

    IPPreset *preset = [_store.presets[row] copy];
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
    if (![preset validate:&error]) {
        [self report:error];
        return;
    }

    NSMutableArray *presets = [_store.presets mutableCopy];
    NSUInteger index =
        [presets indexOfObjectPassingTest:^BOOL(IPPreset *existing, NSUInteger idx, BOOL *stop) {
            return [existing.identifier isEqual:preset.identifier];
        }];
    if (index == NSNotFound) {
        index = presets.count;
        [presets addObject:preset];
    } else {
        presets[index] = preset;
    }

    if (![_store replacePresets:presets error:&error]) {
        [self report:error];
        return;
    }

    _editingID = preset.identifier;
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    _notice.stringValue = @"Preset saved.";
}

- (void)deletePreset:(id)sender
{
    NSInteger row = _table.selectedRow;
    if (row < 0) {
        return;
    }

    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Delete this preset?";
    alert.informativeText = _store.presets[row].name;
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) {
            return;
        }

        NSMutableArray *presets = [self->_store.presets mutableCopy];
        [presets removeObjectAtIndex:row];
        NSError *error;
        if (![self->_store replacePresets:presets error:&error]) {
            [self report:error];
        } else {
            [self newPreset:nil];
        }
    }];
}

- (void)move:(NSInteger)offset
{
    NSInteger row = _table.selectedRow;
    NSInteger destination = row + offset;
    if (row < 0 || destination < 0 || destination >= (NSInteger)_store.presets.count) {
        return;
    }

    NSMutableArray *presets = [_store.presets mutableCopy];
    [presets exchangeObjectAtIndex:row withObjectAtIndex:destination];

    NSError *error;
    if (![_store replacePresets:presets error:&error]) {
        [self report:error];
    } else {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:destination]
            byExtendingSelection:NO];
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
    [_table reloadData];
}

- (void)report:(NSError *)error
{
    _notice.stringValue = error.localizedDescription ?: @"The operation failed.";
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
                self->_notice.stringValue = @"Presets imported as new entries.";
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
                self->_notice.stringValue = @"Presets exported. Adapter names were not included.";
            }
        }
    }];
}

- (void)updateStatus
{
    [self fitWindow];
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
