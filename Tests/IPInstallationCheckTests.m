#import "IPTestSupport.h"
#import "IPInstallationCheck.h"

@interface IPInstallationCheckTests : IPTemporaryDirectoryTestCase
@end

@implementation IPInstallationCheckTests

- (void)testApplicationsAndItsSubfoldersAreAccepted
{
    NSURL *applications = [NSURL fileURLWithPath:@"/Applications"];
    XCTAssertTrue(IPAppIsInApplications(
        [applications URLByAppendingPathComponent:@"IP Selector.app"], applications));
    XCTAssertTrue(IPAppIsInApplications(
        [applications URLByAppendingPathComponent:@"Utilities/IP Selector.app"], applications));
    XCTAssertFalse(IPAppIsInApplications(applications, applications));
}

- (void)testOtherLocationsAreRejected
{
    NSURL *applications = [NSURL fileURLWithPath:@"/Applications"];
    for (NSString *path in @[
             @"/Volumes/IP Selector/IP Selector.app",
             @"/Users/test/Downloads/IP Selector.app",
             @"/Users/test/Applications/IP Selector.app",
             @"/Applications Backup/IP Selector.app",
             @"/Applications/../Users/test/IP Selector.app",
             @"/private/var/folders/test/AppTranslocation/random/d/IP Selector.app"
         ]) {
        XCTAssertFalse(IPAppIsInApplications([NSURL fileURLWithPath:path], applications));
    }
    XCTAssertFalse(
        IPAppIsInApplications([NSURL URLWithString:@"https://example.com/IP.app"], applications));
}

- (void)testSymbolicLinksUseTheActualAppLocation
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *applications = [self.directory URLByAppendingPathComponent:@"Applications"];
    NSURL *installed = [applications URLByAppendingPathComponent:@"Installed.app"];
    NSURL *external = [self.directory URLByAppendingPathComponent:@"External.app"];
    for (NSURL *directory in @[installed, external]) {
        XCTAssertTrue([manager createDirectoryAtURL:directory withIntermediateDirectories:YES
                                         attributes:nil
                                              error:nil]);
    }

    NSURL *outsideLink = [applications URLByAppendingPathComponent:@"Outside.app"];
    XCTAssertTrue([manager createSymbolicLinkAtURL:outsideLink withDestinationURL:external
                                             error:nil]);
    XCTAssertFalse(IPAppIsInApplications(outsideLink, applications));

    NSURL *installedLink = [self.directory URLByAppendingPathComponent:@"Installed Link.app"];
    XCTAssertTrue([manager createSymbolicLinkAtURL:installedLink withDestinationURL:installed
                                             error:nil]);
    XCTAssertTrue(IPAppIsInApplications(installedLink, applications));
}

@end
