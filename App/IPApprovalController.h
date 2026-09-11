#import <Cocoa/Cocoa.h>
@class IPHelperClient;

NS_ASSUME_NONNULL_BEGIN
@interface IPApprovalController : NSWindowController
- (instancetype)initWithClient:(IPHelperClient *)client;
- (void)showWithError:(nullable NSError *)error;
@end
NS_ASSUME_NONNULL_END
