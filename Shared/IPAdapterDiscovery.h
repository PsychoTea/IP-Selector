#import "IPModels.h"
#import <SystemConfiguration/SystemConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

// Exclude internal USB device functions from the attached Ethernet interfaces.
FOUNDATION_EXPORT BOOL IPIsUSBDeviceNetworkPath(NSArray<NSString *> *classes);

@interface IPAdapterDiscovery : NSObject
+ (NSArray<IPAdapterSnapshot *> *)adapters;
+ (NSArray<IPAdapterSnapshot *> *)adaptersWithPreferences:(SCPreferencesRef)preferences;
@end

NS_ASSUME_NONNULL_END
