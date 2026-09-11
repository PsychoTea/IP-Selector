#import <XCTest/XCTest.h>
#import "IPHelperSetup.h"

@interface IPFakeRegistration : NSObject <IPHelperRegistration>
@property (nonatomic) SMAppServiceStatus status;
@property (nonatomic) SMAppServiceStatus registeredStatus;
@property (nonatomic) NSUInteger registerCount;
@property (nonatomic, strong) NSError *failure;
@property (nonatomic) BOOL registersDespiteError;
@end
@implementation IPFakeRegistration

- (BOOL)registerAndReturnError:(NSError **)error
{
    self.registerCount++;
    if (self.failure) {
        if (self.registersDespiteError) {
            self.status = self.registeredStatus;
        }

        if (error) {
            *error = self.failure;
        }

        return NO;
    }

    self.status = self.registeredStatus;

    return YES;
}

@end

@interface IPHelperSetupTests : XCTestCase
@property (nonatomic, copy) NSString *suite;
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) IPFakeRegistration *service;
@property (nonatomic) BOOL signedBuild;
@end
@implementation IPHelperSetupTests

- (void)setUp
{
    self.suite = [@"org.ipselector.setup-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suite];
    self.service = [IPFakeRegistration new];
    self.service.status = SMAppServiceStatusNotRegistered;
    self.service.registeredStatus = SMAppServiceStatusRequiresApproval;
    self.signedBuild = YES;
}

- (void)tearDown
{
    [self.defaults removePersistentDomainForName:self.suite];
}

- (IPHelperSetup *)setup
{
    return [[IPHelperSetup alloc] initWithService:self.service defaults:self.defaults
                                     signingReady:^BOOL {
                                         return self.signedBuild;
                                     }];
}

- (void)testFirstLaunchRegistersOnceAndWaitsForApproval
{
    NSError *error = nil;

    XCTAssertTrue([[self setup] prepareOnFirstLaunch:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(self.service.status, SMAppServiceStatusRequiresApproval);

    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suite];

    XCTAssertFalse([[self setup] prepareOnFirstLaunch:&error]);
    XCTAssertEqual(self.service.registerCount, 1u);
}

- (void)testUnsignedLaunchDoesNotConsumeFirstSignedLaunch
{
    self.signedBuild = NO;

    XCTAssertFalse([[self setup] prepareOnFirstLaunch:NULL]);

    NSError *error = nil;

    XCTAssertFalse([[self setup] registerHelper:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(self.service.registerCount, 0u);

    self.signedBuild = YES;

    XCTAssertTrue([[self setup] prepareOnFirstLaunch:NULL]);
    XCTAssertEqual(self.service.registerCount, 1u);
}

- (void)testApprovedHelperIsLeftAloneEvenAfterApprovalIsRevoked
{
    self.service.status = SMAppServiceStatusEnabled;

    XCTAssertFalse([[self setup] prepareOnFirstLaunch:NULL]);

    self.service.status = SMAppServiceStatusRequiresApproval;

    XCTAssertFalse([[self setup] prepareOnFirstLaunch:NULL]);
    XCTAssertEqual(self.service.registerCount, 0u);
}

- (void)testExistingPendingApprovalIsShownOnceWithoutRegistration
{
    self.service.status = SMAppServiceStatusRequiresApproval;

    XCTAssertTrue([[self setup] prepareOnFirstLaunch:NULL]);
    XCTAssertFalse([[self setup] prepareOnFirstLaunch:NULL]);
    XCTAssertTrue([[self setup] registerHelper:NULL]);
    XCTAssertEqual(self.service.registerCount, 0u);
}

- (void)testFailureIsReportedOnceAndAllowsManualRetry
{
    self.service.failure = [NSError errorWithDomain:@"test" code:7 userInfo:nil];
    NSError *error = nil;

    XCTAssertTrue([[self setup] prepareOnFirstLaunch:&error]);
    XCTAssertEqualObjects(error, self.service.failure);
    XCTAssertFalse([[self setup] prepareOnFirstLaunch:NULL]);
    XCTAssertEqual(self.service.registerCount, 1u);

    self.service.failure = nil;

    XCTAssertTrue([[self setup] registerHelper:NULL]);
    XCTAssertEqual(self.service.registerCount, 2u);
}

- (void)testRemovalBeforeSetupPreventsAutomaticRegistration
{
    [[self setup] suppressAutomaticSetup];

    XCTAssertFalse([[self setup] prepareOnFirstLaunch:NULL]);
    XCTAssertEqual(self.service.registerCount, 0u);
    XCTAssertTrue([[self setup] registerHelper:NULL]);
    XCTAssertEqual(self.service.registerCount, 1u);
}

- (void)testLaunchDeniedWhileAwaitingApprovalIsNotASetupFailure
{
    self.service.failure = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
    self.service.registersDespiteError = YES;
    NSError *error = nil;

    XCTAssertTrue([[self setup] registerHelper:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(self.service.status, SMAppServiceStatusRequiresApproval);
    XCTAssertEqual(self.service.registerCount, 1u);
}

- (void)testEnabledStatusAfterRegistrationErrorIsNotASetupFailure
{
    self.service.failure = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
    self.service.registersDespiteError = YES;
    self.service.registeredStatus = SMAppServiceStatusEnabled;
    NSError *error = nil;

    XCTAssertTrue([[self setup] registerHelper:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(self.service.status, SMAppServiceStatusEnabled);
}

- (void)testRemovalAfterSetupPreventsReinstallation
{
    XCTAssertTrue([[self setup] prepareOnFirstLaunch:NULL]);

    [[self setup] suppressAutomaticSetup];
    self.service.status = SMAppServiceStatusNotRegistered;

    XCTAssertFalse([[self setup] prepareOnFirstLaunch:NULL]);
    XCTAssertEqual(self.service.registerCount, 1u);
}

- (void)testRegistrationCanEnablePreviouslyApprovedHelper
{
    self.service.registeredStatus = SMAppServiceStatusEnabled;

    XCTAssertTrue([[self setup] prepareOnFirstLaunch:NULL]);
    XCTAssertEqual(self.service.status, SMAppServiceStatusEnabled);
    XCTAssertTrue([[self setup] registerHelper:NULL]);
    XCTAssertEqual(self.service.registerCount, 1u);
}

- (void)testResetAllowsFirstLaunchAgainWithoutChangingOtherPreferences
{
    [self.defaults setObject:@"kept" forKey:@"unrelated"];

    XCTAssertTrue([[self setup] prepareOnFirstLaunch:NULL]);

    self.service.status = SMAppServiceStatusNotRegistered;
    [[self setup] resetAutomaticSetupAfterRemoval];

    XCTAssertTrue([[self setup] prepareOnFirstLaunch:NULL]);
    XCTAssertEqual(self.service.registerCount, 2u);
    XCTAssertEqualObjects([self.defaults stringForKey:@"unrelated"], @"kept");
}

@end
