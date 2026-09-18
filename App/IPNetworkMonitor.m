#import "IPNetworkMonitor.h"
NSNotificationName const IPAdaptersChanged = @"IPAdaptersChanged";
@implementation IPNetworkMonitor {
    SCDynamicStoreRef _store;
    NSTimer *_timer;
    dispatch_queue_t _discoveryQueue;
    BOOL _refreshInProgress;
    BOOL _refreshPending;
}

static void IPStoreChanged(SCDynamicStoreRef store, CFArrayRef keys, void *info)
{
    [(__bridge IPNetworkMonitor *)info refresh];
}

- (instancetype)init
{
    if ((self = [super init])) {
        _adapters = @[];
        _discoveryQueue = dispatch_queue_create("org.ipselector.discovery", DISPATCH_QUEUE_SERIAL);
    }

    return self;
}

- (void)start
{
    if (_timer) {
        return;
    }

    SCDynamicStoreContext context = { 0, (__bridge void *)self, NULL, NULL, NULL };
    _store = SCDynamicStoreCreate(NULL, CFSTR("IP Selector monitor"), IPStoreChanged, &context);
    if (_store) {
        NSArray *patterns = @[@"State:/Network/.*", @"Setup:/Network/.*"];
        SCDynamicStoreSetNotificationKeys(_store, NULL, (__bridge CFArrayRef)patterns);
        SCDynamicStoreSetDispatchQueue(_store, dispatch_get_main_queue());
    }

    __weak typeof(self) weakSelf = self;

    // Hardware polling also detects an adapter with no cable link.
    _timer = [NSTimer timerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refresh];
    }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    [self refresh];
}

- (void)refresh
{
    if (_refreshInProgress) {
        _refreshPending = YES;
        return;
    }

    _refreshInProgress = YES;
    dispatch_async(_discoveryQueue, ^{
        NSArray *adapters = IPAdapterDiscovery.adapters;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self publishAdapters:adapters];
        });
    });
}

- (void)publishAdapters:(NSArray<IPAdapterSnapshot *> *)adapters
{
    BOOL changed = adapters.count != _adapters.count;
    for (NSUInteger i = 0; !changed && i < adapters.count; i++) {
        IPAdapterSnapshot *current = adapters[i];
        IPAdapterSnapshot *previous = _adapters[i];
        changed = ![current sameConfiguration:previous] || current.isWiFi != previous.isWiFi
            || current.linkActive != previous.linkActive
            || ![current.activeAddresses isEqual:previous.activeAddresses]
            || ![current.serviceName isEqual:previous.serviceName];
    }

    _adapters = adapters;
    _refreshInProgress = NO;
    if (changed) {
        [NSNotificationCenter.defaultCenter postNotificationName:IPAdaptersChanged object:self];
    }

    if (_refreshPending) {
        _refreshPending = NO;
        [self refresh];
    }
}

- (void)dealloc
{
    [_timer invalidate];
    if (_store) {
        SCDynamicStoreSetDispatchQueue(_store, NULL);
        CFRelease(_store);
    }
}

@end
