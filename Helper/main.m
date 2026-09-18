#import <Foundation/Foundation.h>
#import "IPHelperProtocol.h"
#import "IPNetworkWriter.h"
#import "IPAdapterDiscovery.h"
#import <unistd.h>

@interface IPHelperSession : NSObject <IPHelperProtocol>
@property (nonatomic, strong) IPNetworkWriter *writer;
@property (nonatomic, strong) dispatch_queue_t queue;
@end
@implementation IPHelperSession

- (void)checkConnection:(void (^)(IPApplyResult *))reply
{
    IPApplyResult *result = [IPApplyResult new];
    result.success = geteuid() == 0;
    result.message = result.success ? @"Helper connection works. The helper is running as root."
                                    : @"The helper is not running as root.";
    reply(result);
}

- (void)apply:(IPApplyRequest *)request reply:(void (^)(IPApplyResult *))reply
{
    dispatch_async(self.queue, ^{
        reply([self.writer apply:request]);
    });
}

- (void)undo:(NSString *)token reply:(void (^)(IPApplyResult *))reply
{
    dispatch_async(self.queue, ^{
        reply([self.writer undo:token]);
    });
}

@end
@interface IPHelperDelegate : NSObject <NSXPCListenerDelegate>
@property (nonatomic, copy) NSString *peerRequirement;
@property (nonatomic, strong) dispatch_queue_t queue;
@end
@implementation IPHelperDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection
{
    if (!self.peerRequirement) {
        return NO;
    }

    // Use the identity read at startup. An app update can replace our executable
    // while this process is still running. XPC still checks every client.
    [connection setCodeSigningRequirement:self.peerRequirement];

    IPHelperSession *session = [IPHelperSession new];
    session.queue = self.queue;
    session.writer = [[IPNetworkWriter alloc] initWithAccessFactory:^id<IPNetworkAccess> {
        return [IPSystemNetworkAccess new];
    }];

    connection.exportedInterface = IPHelperInterface();
    connection.exportedObject = session;
    [connection resume];

    return YES;
}

@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSString *requirement = IPPeerRequirement(IPAppIdentifier);
        if (!requirement) {
            NSLog(@"IP Selector helper requires a supported signing certificate.");
            return 1;
        }

        IPHelperDelegate *delegate = [IPHelperDelegate new];
        delegate.peerRequirement = requirement;
        delegate.queue
            = dispatch_queue_create("org.ipselector.network-writes", DISPATCH_QUEUE_SERIAL);

        NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:IPMachService];
        [listener setConnectionCodeSigningRequirement:requirement];
        listener.delegate = delegate;
        [listener resume];
        [[NSRunLoop currentRunLoop] run];
    }

    return 0;
}
