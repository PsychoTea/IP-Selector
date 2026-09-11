#import "IPAdapterDiscovery.h"
FOUNDATION_EXPORT NSNotificationName const IPAdaptersChanged;
@interface IPNetworkMonitor : NSObject
@property (nonatomic, readonly, copy) NSArray<IPAdapterSnapshot *> *adapters;
- (void)start;
- (void)refresh;
@end
