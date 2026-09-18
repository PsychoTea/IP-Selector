#import "IPAppDelegate.h"
#import "IPHelperClient.h"

static int IPCheckHelperConnection(void)
{
    IPHelperClient *client = [IPHelperClient new];
    __block BOOL finished = NO;
    __block int exitStatus = 1;
    [client checkConnection:^(IPApplyResult *result) {
        printf("%s\n", result.message.UTF8String);
        exitStatus = result.success ? 0 : 1;
        finished = YES;
    }];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:35];
    while (!finished && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    if (!finished) {
        fprintf(stderr, "Helper connection check timed out.\n");
    }

    [client invalidate];

    return exitStatus;
}

static BOOL IPRunMaintenanceCommand(NSArray<NSString *> *arguments, int *exitStatus)
{
    // Maintenance runs inside the signed app bundle so SMAppService targets

    // this app's helper. It does not write to the network configuration.
    if ([arguments containsObject:@"--check-helper"]) {
        *exitStatus = IPCheckHelperConnection();
        return YES;
    }

    BOOL remove = [arguments containsObject:@"--remove-helper"];
    BOOL reset = NO;
#if IP_LOCAL_TEST
    reset = [arguments containsObject:@"--reset-helper-setup"];
#endif
    if (remove || reset || [arguments containsObject:@"--helper-status"]) {
        IPHelperClient *client = [IPHelperClient new];
        if (remove || reset) {
            NSError *error = nil;
            if (client.service.status != SMAppServiceStatusNotRegistered
                && ![client.service unregisterAndReturnError:&error]) {
                fprintf(
                    stderr, "Helper removal failed: %s\n", error.localizedDescription.UTF8String);
                *exitStatus = 1;
                return YES;
            }

            if (reset) {
                [client.setup resetAutomaticSetupAfterRemoval];
            } else {
                [client.setup suppressAutomaticSetup];
            }

            [NSUserDefaults.standardUserDefaults synchronize];
        }

        printf("Helper status: %ld (0 = not registered, 1 = enabled, 2 = approval required, 3 "
               "= not found)\n",
            (long)client.service.status);
        *exitStatus = 0;
        return YES;
    }

    return NO;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        int exitStatus = 0;
        if (IPRunMaintenanceCommand(NSProcessInfo.processInfo.arguments, &exitStatus)) {
            return exitStatus;
        }

        NSApplication *app = NSApplication.sharedApplication;
        IPAppDelegate *delegate = [IPAppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }

    return 0;
}
