#import <Cocoa/Cocoa.h>
#import "IPModels.h"
@class IPRecentAddresses;

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT IPPreset *_Nullable IPQuickChangePreset(
    NSString *address, NSString *mask, NSString *gateway, NSError **error);

@interface IPQuickChangeController : NSWindowController
- (instancetype)initWithAdapter:(IPAdapterSnapshot *)adapter history:(IPRecentAddresses *)history;
@property (nonatomic, copy, nullable) BOOL (^applyPreset)(IPPreset *preset);
@end
NS_ASSUME_NONNULL_END
