#import "IPHelperProtocol.h"
#import <Security/Security.h>
#if IP_LOCAL_TEST
#import <CommonCrypto/CommonDigest.h>
NSString *const IPAppIdentifier = @"org.ipselector.IPSelector.LocalTest";
NSString *const IPMachService = @"org.ipselector.IPSelector.LocalTest.Helper";
NSString *const IPDaemonPlist = @"org.ipselector.IPSelector.LocalTest.Helper.plist";
#else
NSString *const IPAppIdentifier = @"org.ipselector.IPSelector";
NSString *const IPMachService = @"org.ipselector.IPSelector.Helper";
NSString *const IPDaemonPlist = @"org.ipselector.IPSelector.Helper.plist";
#endif
NSXPCInterface *IPHelperInterface(void)
{
    NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:@protocol(IPHelperProtocol)];
    NSSet *classes = [NSSet setWithObjects:IPApplyRequest.class,
        IPApplyResult.class,
        IPAdapterSnapshot.class,
        IPPreset.class,
        NSDictionary.class,
        NSArray.class,
        NSString.class,
        NSNumber.class,
        NSData.class,
        NSDate.class,
        nil];

    [interface setClasses:classes forSelector:@selector(checkConnection:) argumentIndex:0
                  ofReply:YES];
    [interface setClasses:classes forSelector:@selector(apply:reply:) argumentIndex:0 ofReply:NO];
    [interface setClasses:classes forSelector:@selector(apply:reply:) argumentIndex:0 ofReply:YES];
    [interface setClasses:[NSSet setWithObject:NSString.class] forSelector:@selector(undo:reply:)
            argumentIndex:0
                  ofReply:NO];
    [interface setClasses:classes forSelector:@selector(undo:reply:) argumentIndex:0 ofReply:YES];

    return interface;
}
#if IP_LOCAL_TEST
NSString *IPLocalCertificateRequirement(NSString *identifier, NSData *certificateDER)
{
    if (![identifier isEqual:IPAppIdentifier] && ![identifier isEqual:IPMachService]) {
        return nil;
    }

    if (!certificateDER.length || certificateDER.length > 1024 * 1024) {
        return nil;
    }

    SecCertificateRef certificate
        = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateDER);
    if (!certificate) {
        return nil;
    }

    CFRelease(certificate);

    unsigned char digest[CC_SHA1_DIGEST_LENGTH];

    // Apple's requirement language uses SHA-1 for whole-certificate identifiers.

    // This identifies the certificate; it does not select the signature algorithm.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_SHA1(certificateDER.bytes, (CC_LONG)certificateDER.length, digest);
#pragma clang diagnostic pop

    NSMutableString *fingerprint = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); index++) {
        [fingerprint appendFormat:@"%02x", digest[index]];
    }

    return [NSString stringWithFormat:@"identifier \"%@\" and certificate leaf = H\"%@\"",
        identifier,
        fingerprint];
}
#endif
NSString *IPPeerRequirement(NSString *identifier)
{
    if (![identifier isEqual:IPAppIdentifier] && ![identifier isEqual:IPMachService]) {
        return nil;
    }

    SecCodeRef code = NULL;
    CFDictionaryRef info = NULL;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess) {
        return nil;
    }

    OSStatus status = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info);
    CFRelease(code);
    if (status != errSecSuccess || !info) {
        return nil;
    }

    NSDictionary *signingInformation = CFBridgingRelease(info);
#if IP_LOCAL_TEST
    NSArray *certificates = signingInformation[(__bridge NSString *)kSecCodeInfoCertificates];
    if (!certificates.count) {
        return nil;
    }

    SecCertificateRef certificate = (__bridge SecCertificateRef)certificates.firstObject;
    NSData *der = CFBridgingRelease(SecCertificateCopyData(certificate));

    return IPLocalCertificateRequirement(identifier, der);
#else
    NSString *team = signingInformation[(__bridge NSString *)kSecCodeInfoTeamIdentifier];
    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"];
    if (!team.length || [team rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
        return nil;
    }

    return [NSString stringWithFormat:
            @"anchor apple generic and identifier \"%@\" and certificate leaf[subject.OU] = \"%@\"",
        identifier,
        team];
#endif
}
