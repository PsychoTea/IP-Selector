#import "IPRecentAddresses.h"
#import "IPAddressUtilities.h"

static NSString *const IPRecentAddressesKey = @"RecentIPv4Addresses";
static const NSUInteger IPRecentAddressLimit = 20;

@implementation IPRecentAddresses {
    NSUserDefaults *_defaults;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
    if ((self = [super init])) {
        _defaults = defaults;
        NSMutableOrderedSet *addresses = [NSMutableOrderedSet orderedSet];
        id saved = [defaults objectForKey:IPRecentAddressesKey];
        if ([saved isKindOfClass:NSArray.class]) {
            for (id address in saved) {
                if (IPValidUnicastIPv4(address)) {
                    [addresses addObject:address];
                }

                if (addresses.count == IPRecentAddressLimit) {
                    break;
                }
            }
        }

        _addresses = addresses.array;
    }

    return self;
}

- (void)recordAddress:(NSString *)address
{
    if (!IPValidUnicastIPv4(address)) {
        return;
    }

    NSMutableArray *addresses = self.addresses.mutableCopy;
    [addresses removeObject:address];
    [addresses insertObject:address atIndex:0];
    if (addresses.count > IPRecentAddressLimit) {
        [addresses removeLastObject];
    }

    _addresses = addresses.copy;
    [_defaults setObject:_addresses forKey:IPRecentAddressesKey];
}

@end
