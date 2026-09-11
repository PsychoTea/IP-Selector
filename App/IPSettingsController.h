#import <Cocoa/Cocoa.h>
@class IPPresetStore;

NS_ASSUME_NONNULL_BEGIN
@interface IPSettingsController : NSWindowController
- (instancetype)initWithStore:(IPPresetStore *)store;
@end
NS_ASSUME_NONNULL_END
