#import <Cocoa/Cocoa.h>
@class IPPresetStore, IPNetworkMonitor, IPHelperClient;

NS_ASSUME_NONNULL_BEGIN
@interface IPMenuController : NSViewController
- (instancetype)initWithStore:(IPPresetStore *)store
                      monitor:(IPNetworkMonitor *)monitor
                       client:(IPHelperClient *)client;
// Keep network Undo available through the app's Edit menu and responder chain.
- (IBAction)undo:(nullable id)sender;
@property (nonatomic, copy, nullable) void (^openSettings)(void);
@property (nonatomic, copy, nullable) void (^openApproval)(void);
@property (nonatomic, copy, nullable) void (^contentSizeChanged)(NSSize size);
@end
NS_ASSUME_NONNULL_END
