#import "IPHelperProtocol.h"
#import "IPHelperSetup.h"
#import <ServiceManagement/ServiceManagement.h>
@interface IPHelperClient : NSObject
@property (nonatomic, readonly) SMAppService *service;
@property (nonatomic, readonly) IPHelperSetup *setup;
@property (nonatomic, copy) void (^connectionLost)(void);
- (void)apply:(IPApplyRequest *)request completion:(void (^)(IPApplyResult *))completion;
- (void)undo:(NSString *)token completion:(void (^)(IPApplyResult *))completion;
- (void)invalidate;
- (void)checkConnection:(void (^)(IPApplyResult *))completion;
@end
