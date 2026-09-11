#import "IPModels.h"
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const IPMachService;
FOUNDATION_EXPORT NSString *const IPDaemonPlist;
FOUNDATION_EXPORT NSString *const IPAppIdentifier;
@protocol IPHelperProtocol
- (void)checkConnection:(void (^)(IPApplyResult *result))reply;
- (void)apply:(IPApplyRequest *)request reply:(void (^)(IPApplyResult *result))reply;
- (void)undo:(NSString *)token reply:(void (^)(IPApplyResult *result))reply;
@end
FOUNDATION_EXPORT NSXPCInterface *IPHelperInterface(void);
// Return nil for unsigned/ad-hoc code. Release peers must use the same Apple team.
// LocalTest peers must use the exact same signing certificate and local identifiers.
FOUNDATION_EXPORT NSString *_Nullable IPPeerRequirement(NSString *identifier);
#if IP_LOCAL_TEST
FOUNDATION_EXPORT NSString *_Nullable IPLocalCertificateRequirement(
    NSString *identifier, NSData *certificateDER);
#endif
NS_ASSUME_NONNULL_END
