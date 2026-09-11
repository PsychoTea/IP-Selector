#import "IPNetworkAccess.h"

NS_ASSUME_NONNULL_BEGIN

// One instance per XPC connection. All calls run on the helper's serial queue.
@interface IPNetworkWriter : NSObject
- (instancetype)initWithAccessFactory:(id<IPNetworkAccess> (^)(void))factory;
- (IPApplyResult *)apply:(IPApplyRequest *)request;
- (IPApplyResult *)undo:(NSString *)token;
@end
NS_ASSUME_NONNULL_END
