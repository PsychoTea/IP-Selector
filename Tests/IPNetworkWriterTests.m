#import "IPTestSupport.h"

@interface IPNetworkWriterTests : XCTestCase
@end

@implementation IPNetworkWriterTests

- (IPApplyRequest *)request:(IPFakeAccess *)access
{
    IPApplyRequest *request = [IPApplyRequest new];
    request.expected = IPCopyTestAdapter(access.saved);
    request.preset = IPTestPreset();

    return request;
}

- (IPNetworkWriter *)writer:(IPFakeAccess *)access
{
    return [[IPNetworkWriter alloc] initWithAccessFactory:^id<IPNetworkAccess> {
        return access;
    }];
}

- (void)testDisconnectedServiceCannotApplySettings
{
    IPFakeAccess *access = [IPFakeAccess new];
    access.saved.registryID = @0;
    IPApplyResult *result = [[self writer:access] apply:[self request:access]];

    XCTAssertFalse(result.success);
    XCTAssertEqual(access.commitCount, 0);
}

- (void)testApplyAndUndoWithoutCableLink
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPAdapterSnapshot *original = IPCopyTestAdapter(access.saved);
    IPNetworkWriter *writer = [self writer:access];
    IPApplyResult *result = [writer apply:[self request:access]];

    XCTAssertTrue(result.success);
    XCTAssertNotNil(result.undoToken);
    XCTAssertTrue([access.saved matchesPreset:IPTestPreset()]);
    XCTAssertTrue(access.unlocked);

    IPApplyResult *undo = [writer undo:result.undoToken];

    XCTAssertTrue(undo.success);
    XCTAssertNil(undo.undoToken);
    XCTAssertTrue([access.saved sameConfiguration:original]);
}

- (void)testExternalChangeBlocksUndo
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPNetworkWriter *writer = [self writer:access];
    IPApplyResult *result = [writer apply:[self request:access]];
    access.saved.dns = @{ @"ServerAddresses": @[@"8.8.8.8"] };

    XCTAssertFalse([writer undo:result.undoToken].success);
    XCTAssertEqual(access.commitCount, 1);
}

- (void)testStaleRequestCannotChangeSettings
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPApplyRequest *request = [self request:access];
    access.saved.registryID = @999;

    XCTAssertFalse([[self writer:access] apply:request].success);
    XCTAssertEqual(access.commitCount, 0);
    XCTAssertTrue(access.unlocked);
}

- (void)testChangedConfigurationCannotBeOverwritten
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPApplyRequest *request = [self request:access];
    access.saved.dns = @{};

    XCTAssertFalse([[self writer:access] apply:request].success);
    XCTAssertEqual(access.commitCount, 0);
}

- (void)testDisconnectBeforeCommitDoesNotSave
{
    IPFakeAccess *access = [IPFakeAccess new];
    access.detachBeforeCommit = YES;
    IPApplyResult *result = [[self writer:access] apply:[self request:access]];

    XCTAssertFalse(result.success);
    XCTAssertEqual(access.commitCount, 0);
    XCTAssertTrue(access.unlocked);
}

- (void)testApplyFailureRestoresPreviousSettings
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPAdapterSnapshot *before = IPCopyTestAdapter(access.saved);
    access.failApplyAt = 1;
    IPApplyResult *result = [[self writer:access] apply:[self request:access]];

    XCTAssertFalse(result.success);
    XCTAssertTrue([result.message containsString:@"Previous settings were restored"]);
    XCTAssertTrue([access.saved sameConfiguration:before]);
    XCTAssertEqual(access.commitCount, 2);
    XCTAssertTrue(access.unlocked);
}

- (void)testRestorationFailureIsReported
{
    IPFakeAccess *access = [IPFakeAccess new];
    access.failApplyAt = 1;
    access.failCommitAt = 2;
    IPApplyResult *result = [[self writer:access] apply:[self request:access]];

    XCTAssertFalse(result.success);
    XCTAssertTrue([result.message containsString:@"could not be restored"]);
    XCTAssertNil(result.undoToken);
}

- (void)testVerificationFailureRestoresPreviousSettings
{
    IPFakeAccess *access = [IPFakeAccess new];
    access.corruptReadBack = YES;
    IPAdapterSnapshot *before = IPCopyTestAdapter(access.saved);
    IPApplyResult *result = [[self writer:access] apply:[self request:access]];

    XCTAssertFalse(result.success);
    XCTAssertTrue([access.saved sameConfiguration:before]);
}

- (void)testLockStageAndCommitFailures
{
    for (NSString *flag in @[@"failLock", @"failStage", @"failCommitAt"]) {
        IPFakeAccess *access = [IPFakeAccess new];
        [access setValue:@1 forKey:flag];
        IPApplyResult *result = [[self writer:access] apply:[self request:access]];

        XCTAssertFalse(result.success);
        XCTAssertEqual(access.applyCount, 0);
    }
}

- (void)testUnknownUndoTokenIsRejected
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPNetworkWriter *writer = [self writer:access];
    [writer apply:[self request:access]];

    XCTAssertFalse([writer undo:@"unknown"].success);
    XCTAssertEqual(access.commitCount, 1);
}

- (void)testInvalidRequestCannotReachNetworkWriter
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPApplyRequest *request = [self request:access];
    request.preset.address = @"bad";

    XCTAssertFalse([[self writer:access] apply:request].success);
    XCTAssertEqual(access.commitCount, 0);
}

- (void)testNoOpDoesNotWrite
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPNetworkWriter *writer = [self writer:access];
    IPApplyResult *first = [writer apply:[self request:access]];
    IPApplyResult *second = [writer apply:[self request:access]];

    XCTAssertTrue(second.success);
    XCTAssertEqualObjects(second.undoToken, first.undoToken);
    XCTAssertEqual(access.commitCount, 1);
}

- (void)testDHCPDoesNotRequireALeaseAndClearsManualDNS
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPApplyRequest *request = [self request:access];
    request.preset = nil;
    request.useDHCP = YES;
    IPApplyResult *result = [[self writer:access] apply:request];

    XCTAssertTrue(result.success);
    XCTAssertTrue(result.current.isAutomatic);
    XCTAssertEqual(result.current.activeAddresses.count, 0u);
    XCTAssertNil(access.saved.dns[@"ServerAddresses"]);
    XCTAssertTrue(access.unlocked);
}

- (void)testRequestMustSpecifyExactlyOneOperation
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPNetworkWriter *writer = [self writer:access];
    IPApplyRequest *request = [self request:access];
    request.useDHCP = YES;

    XCTAssertFalse([writer apply:request].success);

    request.useDHCP = NO;
    request.preset = nil;

    XCTAssertFalse([writer apply:request].success);
    XCTAssertEqual(access.commitCount, 0);
}

- (void)testDifferentServiceCannotReceiveTheChange
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPAdapterSnapshot *before = IPCopyTestAdapter(access.saved);
    IPApplyRequest *request = [self request:access];
    request.expected.serviceID = @"service-B";

    XCTAssertFalse([[self writer:access] apply:request].success);
    XCTAssertTrue([access.saved sameConfiguration:before]);
    XCTAssertEqual(access.commitCount, 0);
    XCTAssertTrue(access.unlocked);
}

- (void)testNoOpOnAnotherServicePreservesTheOriginalUndo
{
    IPFakeAccess *access = [IPFakeAccess new];
    IPAdapterSnapshot *before = IPCopyTestAdapter(access.saved);
    IPNetworkWriter *writer = [self writer:access];
    IPApplyResult *first = [writer apply:[self request:access]];
    IPAdapterSnapshot *after = IPCopyTestAdapter(access.saved);

    access.saved.serviceID = @"service-B";
    access.saved.registryID = @456;
    IPApplyResult *second = [writer apply:[self request:access]];

    XCTAssertTrue(second.success);
    XCTAssertEqualObjects(second.undoToken, first.undoToken);
    XCTAssertEqual(access.commitCount, 1);

    access.saved = after;

    XCTAssertTrue([writer undo:second.undoToken].success);
    XCTAssertTrue([access.saved sameConfiguration:before]);
}

- (void)testRestorationDoesNotWriteToAReplacementAdapter
{
    IPFakeAccess *access = [IPFakeAccess new];
    access.failApplyAt = 1;
    access.replaceBeforeRestore = YES;
    IPApplyResult *result = [[self writer:access] apply:[self request:access]];

    XCTAssertFalse(result.success);
    XCTAssertTrue([result.message containsString:@"could not be restored"]);
    XCTAssertEqual(access.commitCount, 1);
    XCTAssertTrue(access.unlocked);
}

- (void)testAnExceptionStillReleasesThePreferencesLock
{
    IPFakeAccess *access = [IPFakeAccess new];
    access.throwOnStage = YES;

    XCTAssertThrowsSpecificNamed([[self writer:access] apply:[self request:access]],
        NSException,
        NSInternalInconsistencyException);
    XCTAssertTrue(access.unlocked);
    XCTAssertEqual(access.commitCount, 0);
}

@end
