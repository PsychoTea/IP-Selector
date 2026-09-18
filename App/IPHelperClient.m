#import "IPHelperClient.h"
@implementation IPHelperClient {
    NSXPCConnection *_connection;
    IPHelperSetup *_setup;
}

- (IPHelperSetup *)setup
{
    if (!_setup) {
        _setup = [[IPHelperSetup alloc] initWithService:(id<IPHelperRegistration>)self.service
                                               defaults:NSUserDefaults.standardUserDefaults
                                           signingReady:^BOOL {
                                               return IPPeerRequirement(IPMachService) != nil;
                                           }];
    }

    return _setup;
}

- (SMAppService *)service
{
    return [SMAppService daemonServiceWithPlistName:IPDaemonPlist];
}

- (void)invalidate
{
    NSXPCConnection *connection = _connection;
    _connection = nil;

    connection.interruptionHandler = nil;
    connection.invalidationHandler = nil;
    [connection invalidate];
    if (self.connectionLost) {
        self.connectionLost();
    }
}

- (id<IPHelperProtocol>)proxy:(void (^)(IPApplyResult *))completion
{
    if (self.service.status != SMAppServiceStatusEnabled) {
        completion([IPApplyResult failure:@"Select Approve Helper before changing settings."]);
        return nil;
    }

    if (!_connection) {
        NSString *requirement = IPPeerRequirement(IPMachService);
        if (!requirement) {
            completion([IPApplyResult
                failure:@"This build needs a supported signing certificate before it can use the "
                        @"helper. See the signing instructions in the project README."]);
            return nil;
        }

        _connection = [[NSXPCConnection alloc] initWithMachServiceName:IPMachService
                                                               options:NSXPCConnectionPrivileged];
        [_connection setCodeSigningRequirement:requirement];
        _connection.remoteObjectInterface = IPHelperInterface();

        __weak typeof(self) weakSelf = self;
        __weak NSXPCConnection *expectedConnection = _connection;
        void (^lost)(void) = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                IPHelperClient *strongSelf = weakSelf;
                if (!strongSelf || strongSelf->_connection != expectedConnection) {
                    return;
                }

                [strongSelf invalidate];
            });
        };

        _connection.interruptionHandler = lost;
        _connection.invalidationHandler = lost;
        [_connection resume];
    }

    return [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        NSLog(@"Helper XPC connection failed (%@ %ld): %@",
            error.domain,
            (long)error.code,
            error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(
                [IPApplyResult failure:@"The helper connection failed. Check helper approval and "
                                       @"signing. Refresh the adapter settings before retrying."]);
        });
    }];
}

- (void)perform:(void (^)(id<IPHelperProtocol>, void (^)(IPApplyResult *)))operation
     completion:(void (^)(IPApplyResult *))completion
{
    __block BOOL finished = NO;
    void (^finish)(IPApplyResult *) = ^(IPApplyResult *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished) {
                return;
            }

            finished = YES;
            completion(result);
        });
    };

    id<IPHelperProtocol> proxy = [self proxy:finish];
    if (proxy) {
        operation(proxy, finish);
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!finished) {
                [self invalidate];
                finish([IPApplyResult failure:@"The helper did not reply. The outcome is unknown. "
                                              @"Refresh the adapter settings before retrying."]);
            }
        });
}

- (void)apply:(IPApplyRequest *)request completion:(void (^)(IPApplyResult *))completion
{
    [self perform:^(id<IPHelperProtocol> proxy, void (^reply)(IPApplyResult *)) {
        [proxy apply:request reply:reply];
    } completion:completion];
}

- (void)checkConnection:(void (^)(IPApplyResult *))completion
{
    [self perform:^(id<IPHelperProtocol> proxy, void (^reply)(IPApplyResult *)) {
        [proxy checkConnection:reply];
    } completion:completion];
}

- (void)undo:(NSString *)token completion:(void (^)(IPApplyResult *))completion
{
    [self perform:^(id<IPHelperProtocol> proxy, void (^reply)(IPApplyResult *)) {
        [proxy undo:token reply:reply];
    } completion:completion];
}

@end
