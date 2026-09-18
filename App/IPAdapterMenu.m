#import "IPAdapterMenu.h"

@implementation IPAdapterMenu {
    NSMenuItem *_status;
    NSMenuItem *_address;
    NSMenuItem *_quick;
}

- (instancetype)initWithAdapter:(IPAdapterSnapshot *)adapter
                        presets:(NSArray<IPPreset *> *)presets
                         target:(id<IPAdapterMenuActions>)target
{
    if ((self = [super initWithTitle:adapter.serviceName])) {
        _adapter = adapter;
        self.autoenablesItems = NO;
        _status = [self addItemWithTitle:@"" action:nil keyEquivalent:@""];
        _status.state = NSControlStateValueOn;
        _status.enabled = NO;
        _address = [self addItemWithTitle:@"" action:nil keyEquivalent:@""];
        _address.enabled = NO;
        NSMenuItem *mac =
            [self addItemWithTitle:adapter.mac.length ? adapter.mac : @"MAC unavailable" action:nil
                     keyEquivalent:@""];
        mac.enabled = NO;
        [self addItem:NSMenuItem.separatorItem];

        _quick = [self addItemWithTitle:@"Quick IP…" action:@selector(quickChange:)
                          keyEquivalent:@""];
        _quick.target = target;
        _quick.representedObject = adapter;
        [self addPreset:nil target:target];
        [self addItem:NSMenuItem.separatorItem];
        for (IPPreset *preset in presets) {
            [self addPreset:preset target:target];
        }

        if (!presets.count) {
            NSMenuItem *empty = [self addItemWithTitle:@"No saved presets" action:nil
                                         keyEquivalent:@""];
            empty.enabled = NO;
        }

        [self refreshWithAdapter:adapter busy:NO];
    }

    return self;
}

- (void)addPreset:(IPPreset *)preset target:(id<IPAdapterMenuActions>)target
{
    NSString *title = preset ? [NSString stringWithFormat:@"%@ — %@", preset.name, preset.address]
                             : @"Use DHCP";
    NSMenuItem *item = [self addItemWithTitle:title action:@selector(apply:) keyEquivalent:@""];
    IPApplyRequest *request = [IPApplyRequest new];
    request.expected = self.adapter;
    request.preset = [preset copy];
    request.useDHCP = preset == nil;
    item.representedObject = request;
    item.target = target;
    if (preset) {
        item.toolTip = [NSString stringWithFormat:@"%@ / %@\nGateway: %@\nDNS: %@",
            preset.address,
            preset.mask,
            preset.gateway.length ? preset.gateway : @"None",
            preset.dns.count ? [preset.dns componentsJoinedByString:@", "] : @"No manual servers"];
    }
}

- (void)refreshWithAdapter:(IPAdapterSnapshot *)adapter busy:(BOOL)busy
{
    IPConnectionStatus status = adapter.connectionStatus;
    switch (status) {
    case IPConnectionStatusConnected:
        _status.title = @"Connected";
        break;
    case IPConnectionStatusSelfAssigned:
        _status.title = @"Self Assigned IP";
        break;
    case IPConnectionStatusNotConnected:
        _status.title = @"Not connected";
        break;
    }

    _status.onStateImage = [NSImage
        imageWithSystemSymbolName:status == IPConnectionStatusConnected ? @"checkmark" : @"xmark"
         accessibilityDescription:nil];
    NSMutableArray<NSString *> *addresses = [NSMutableArray array];
    for (NSString *address in adapter.activeAddresses) {
        if (IPValidUnicastIPv4(address)) {
            [addresses addObject:address];
        }
    }

    _address.title = addresses.count
        ? [@"IP: " stringByAppendingString:[addresses componentsJoinedByString:@", "]]
        : @"IP: Not assigned";
    _quick.enabled = adapter && !busy;
    if (adapter) {
        _quick.representedObject = adapter;
    }

    for (NSMenuItem *item in self.itemArray) {
        IPApplyRequest *previous = item.representedObject;
        if (![previous isKindOfClass:IPApplyRequest.class]) {
            continue;
        }

        // Do not mutate a request that may already have been sent to the helper.
        if (adapter) {
            IPApplyRequest *request = [IPApplyRequest new];
            request.expected = adapter;
            request.preset = previous.preset;
            request.useDHCP = previous.useDHCP;
            item.representedObject = request;
        }

        BOOL active = adapter
            && (previous.useDHCP ? adapter.isAutomatic : [adapter matchesPreset:previous.preset]);
        item.state = active ? NSControlStateValueOn : NSControlStateValueOff;
        item.enabled = adapter && !busy;
    }
}

@end
