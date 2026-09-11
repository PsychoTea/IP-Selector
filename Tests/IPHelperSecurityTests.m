#import "IPTestSupport.h"
#import "IPHelperProtocol.h"
#import <Security/Security.h>

@interface IPHelperSecurityTests : XCTestCase
@end

@implementation IPHelperSecurityTests

- (void)testBuildIdentifiersAreSeparated
{
#if IP_LOCAL_TEST
    XCTAssertEqualObjects(IPAppIdentifier, @"org.ipselector.IPSelector.LocalTest");
    XCTAssertEqualObjects(IPMachService, @"org.ipselector.IPSelector.LocalTest.Helper");
#else
    XCTAssertEqualObjects(IPAppIdentifier, @"org.ipselector.IPSelector");
    XCTAssertEqualObjects(IPMachService, @"org.ipselector.IPSelector.Helper");
#endif
    XCTAssertEqualObjects(IPDaemonPlist, [IPMachService stringByAppendingString:@".plist"]);
}

- (void)testUnknownPeerIdentifierIsRejected
{
    XCTAssertNil(IPPeerRequirement(@"org.example.unrelated"));
}

#if IP_LOCAL_TEST
- (void)testLocalSigningRejectsMissingOrMalformedCertificates
{
    XCTAssertNil(IPLocalCertificateRequirement(IPAppIdentifier, [NSData data]));
    XCTAssertNil(IPLocalCertificateRequirement(
        IPMachService, [@"invalid certificate" dataUsingEncoding:NSUTF8StringEncoding]));
}
#endif

#if IP_LOCAL_TEST
- (void)testLocalRequirementPinsAnExactCertificate
{
    CFArrayRef anchors = NULL;

    XCTAssertEqual(SecTrustCopyAnchorCertificates(&anchors), errSecSuccess);

    NSArray *certificates = CFBridgingRelease(anchors);

    XCTAssertGreaterThan(certificates.count, 1u);

    if (certificates.count < 2) {
        return;
    }

    NSData *first
        = CFBridgingRelease(SecCertificateCopyData((__bridge SecCertificateRef)certificates[0]));
    NSData *second
        = CFBridgingRelease(SecCertificateCopyData((__bridge SecCertificateRef)certificates[1]));
    NSString *requirement = IPLocalCertificateRequirement(IPAppIdentifier, first);

    XCTAssertNotNil(requirement);
    XCTAssertNotEqualObjects(requirement, IPLocalCertificateRequirement(IPAppIdentifier, second));
    XCTAssertNotEqualObjects(requirement, IPLocalCertificateRequirement(IPMachService, first));
    XCTAssertNil(IPLocalCertificateRequirement(@"org.ipselector.IPSelector", first));

    SecRequirementRef compiled = NULL;

    XCTAssertEqual(SecRequirementCreateWithString(
                       (__bridge CFStringRef)requirement, kSecCSDefaultFlags, &compiled),
        errSecSuccess);

    if (compiled) {
        CFRelease(compiled);
    }
}
#endif

@end
