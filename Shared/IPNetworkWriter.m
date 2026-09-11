#import "IPNetworkWriter.h"

@implementation IPNetworkWriter {
    id<IPNetworkAccess> (^_accessFactory)(void);
    IPAdapterSnapshot *_undoBefore;
    IPAdapterSnapshot *_undoAfter;
    NSString *_undoToken;
}

- (instancetype)initWithAccessFactory:(id<IPNetworkAccess> (^)(void))factory
{
    if ((self = [super init])) {
        _accessFactory = [factory copy];
    }

    return self;
}

- (IPApplyResult *)apply:(IPApplyRequest *)request
{
    if (!request.expected.serviceID.length || !request.expected.registryID.unsignedLongLongValue) {
        return [IPApplyResult failure:@"The change request is invalid."];
    }

    // A request must specify exactly one operation.
    if ((request.useDHCP && request.preset) || (!request.useDHCP && !request.preset)) {
        return [IPApplyResult failure:@"The change request is invalid."];
    }

    NSError *error = nil;
    if (request.preset && ![request.preset validate:&error]) {
        return [IPApplyResult failure:error.localizedDescription];
    }

    NSDictionary *ipv4 = IPDesiredIPv4(request.expected.ipv4, request.preset, request.useDHCP);
    NSDictionary *dns = IPDesiredDNS(request.expected.dns, request.preset, request.useDHCP);

    return [self change:request.expected ipv4:ipv4 dns:dns isUndo:NO];
}

- (IPApplyResult *)undo:(NSString *)token
{
    if (!_undoToken || ![token isEqual:_undoToken] || !_undoBefore || !_undoAfter) {
        return [IPApplyResult failure:@"Undo is no longer available."];
    }

    return [self change:_undoAfter ipv4:_undoBefore.ipv4 dns:_undoBefore.dns isUndo:YES];
}

- (void)clearUndo
{
    _undoToken = nil;
    _undoBefore = nil;
    _undoAfter = nil;
}

- (IPApplyResult *)change:(IPAdapterSnapshot *)expected
                     ipv4:(NSDictionary *)ipv4
                      dns:(NSDictionary *)dns
                   isUndo:(BOOL)isUndo
{
    id<IPNetworkAccess> access = _accessFactory();
    NSError *error = nil;
    if (![access lock:&error]) {
        return [IPApplyResult failure:error.localizedDescription];
    }

    @try {
        return [self changeLockedService:expected ipv4:ipv4 dns:dns isUndo:isUndo access:access];
    } @finally {
        [access unlock];
    }
}

// The caller holds the preferences lock through verification and any restoration.
- (IPApplyResult *)changeLockedService:(IPAdapterSnapshot *)expected
                                  ipv4:(NSDictionary *)ipv4
                                   dns:(NSDictionary *)dns
                                isUndo:(BOOL)isUndo
                                access:(id<IPNetworkAccess>)access
{
    IPAdapterSnapshot *before = [access snapshot:expected.serviceID];
    if (![before sameConfiguration:expected]) {
        [self clearUndo];
        return [IPApplyResult
            failure:@"The adapter or its settings changed. Select it again and retry."];
    }

    if ([before.ipv4 isEqual:ipv4] && [before.dns isEqual:dns]) {
        return [IPApplyResult success:@"These settings are already applied." current:before
                            undoToken:_undoToken];
    }

    NSError *error = nil;
    if (![access stageIPv4:ipv4 dns:dns service:expected.serviceID error:&error]) {
        return [IPApplyResult failure:error.localizedDescription];
    }

    // A service ID alone does not prove that the same physical adapter is attached.
    if (![[access snapshot:expected.serviceID] sameAttachment:expected]) {
        [self clearUndo];
        return [IPApplyResult failure:@"The adapter disconnected. No settings were saved."];
    }

    if (![access commit:&error]) {
        [self clearUndo];
        return [IPApplyResult
            failure:error.localizedDescription ?: @"The settings could not be saved."];
    }

    BOOL applied = [access apply:&error];
    IPAdapterSnapshot *current = applied ? [access readBack:expected.serviceID] : nil;
    BOOL verified = [current sameAttachment:expected] && [current.ipv4 isEqual:ipv4] &&
        [current.dns isEqual:dns];
    if (!verified) {
        [self clearUndo];
        return [self restoreAfterFailure:error before:before access:access];
    }

    if (isUndo) {
        [self clearUndo];
    } else {
        _undoBefore = before;
        _undoAfter = current;
        _undoToken = NSUUID.UUID.UUIDString;
    }

    return [IPApplyResult success:isUndo ? @"Previous settings restored." : @"Settings applied."
                          current:current
                        undoToken:_undoToken];
}

- (IPApplyResult *)restoreAfterFailure:(NSError *)error
                                before:(IPAdapterSnapshot *)before
                                access:(id<IPNetworkAccess>)access
{
    BOOL restored = [self restore:before access:access];
    NSString *reason = error.localizedDescription ?: @"The saved settings could not be verified.";
    NSString *outcome = restored
        ? @" Previous settings were restored."
        : @" Previous settings could not be restored. Check this service in System Settings.";

    return [IPApplyResult failure:[reason stringByAppendingString:outcome]];
}

- (BOOL)restore:(IPAdapterSnapshot *)before access:(id<IPNetworkAccess>)access
{
    if (![[access snapshot:before.serviceID] sameAttachment:before]) {
        return NO;
    }

    if (![access stageIPv4:before.ipv4 dns:before.dns service:before.serviceID error:NULL]) {
        return NO;
    }

    if (![access commit:NULL] || ![access apply:NULL]) {
        return NO;
    }

    return [[access readBack:before.serviceID] sameConfiguration:before];
}

@end
