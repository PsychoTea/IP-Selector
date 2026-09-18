#import <Cocoa/Cocoa.h>
@class IPPresetStore, IPNetworkMonitor, IPHelperClient;

NS_ASSUME_NONNULL_BEGIN
@interface IPMenuController : NSObject <NSMenuDelegate>
- (instancetype)initWithStore:(IPPresetStore *)store
                      monitor:(IPNetworkMonitor *)monitor
                       client:(IPHelperClient *)client;
- (IBAction)undo:(nullable id)sender;
@property (nonatomic, readonly) NSMenu *menu;
@property (nonatomic, copy, nullable) void (^openSettings)(void);
@property (nonatomic, copy, nullable) void (^openApproval)(void);
@end
NS_ASSUME_NONNULL_END
