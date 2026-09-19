#import "IPInstallationCheck.h"
#import <Cocoa/Cocoa.h>

BOOL IPAppIsInApplications(NSURL *bundleURL, NSURL *applicationsURL)
{
    if (!bundleURL.isFileURL || !applicationsURL.isFileURL) {
        return NO;
    }

    // Check the actual location, including apps reached through a symbolic link.
    NSURL *resolvedBundle = bundleURL.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSURL *resolvedApplications
        = applicationsURL.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSString *directory = [resolvedApplications.path stringByAppendingString:@"/"];

    return [resolvedBundle.path hasPrefix:directory];
}

BOOL IPCheckApplicationInstallation(void)
{
    NSURL *applications = [NSURL fileURLWithPath:@"/Applications" isDirectory:YES];
    if (IPAppIsInApplications(NSBundle.mainBundle.bundleURL, applications)) {
        return YES;
    }

    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Copy IP Selector to Applications";
    alert.informativeText = @"Copy IP Selector to the Applications folder (/Applications), then "
                            @"open it from there. If you opened a disk image, drag the app onto "
                            @"its Applications shortcut.\n\nThis copy of IP Selector will quit.";
    [alert addButtonWithTitle:@"Open Applications"];
    [alert addButtonWithTitle:@"Quit"];
    [NSApp activate];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [NSWorkspace.sharedWorkspace openURL:applications];
    }

    return NO;
}
