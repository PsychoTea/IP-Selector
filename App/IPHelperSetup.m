#import "IPHelperSetup.h"
#import "IPModels.h"

static NSString *const IPHelperSetupAttempted = @"IPHelperSetupAttempted";

@implementation IPHelperSetup {
    id<IPHelperRegistration> _service;
    NSUserDefaults *_defaults;
    BOOL (^_signingReady)(void);
}

- (instancetype)initWithService:(id<IPHelperRegistration>)service
                       defaults:(NSUserDefaults *)defaults
                   signingReady:(BOOL (^)(void))signingReady
{
    if ((self = [super init])) {
        _service = service;
        _defaults = defaults;
        _signingReady = [signingReady copy];
    }

    return self;
}

- (BOOL)prepareOnFirstLaunch:(NSError **)error
{
    if ([_defaults boolForKey:IPHelperSetupAttempted] || !_signingReady()) {
        return NO;
    }

    [self suppressAutomaticSetup];
    if (_service.status == SMAppServiceStatusEnabled) {
        return NO;
    }

    [self registerHelper:error];

    return YES;
}

- (BOOL)registerHelper:(NSError **)error
{
    if (!_signingReady()) {
        if (error) {
            *error = IPError(@"Sign this build with a supported certificate before helper setup. "
                             @"See the project README.");
        }

        return NO;
    }

    // Save the attempt before calling macOS. A failure or denied approval must

    // not cause a new setup prompt on each launch. The user can retry in Settings.
    [self suppressAutomaticSetup];
    SMAppServiceStatus status = _service.status;
    if (status == SMAppServiceStatusEnabled || status == SMAppServiceStatusRequiresApproval) {
        return YES;
    }

    NSError *registrationError = nil;
    BOOL registered = [_service registerAndReturnError:&registrationError];

    // macOS can report denied launch while registration succeeds and awaits approval.
    if (!registered
        && (_service.status == SMAppServiceStatusRequiresApproval
            || _service.status == SMAppServiceStatusEnabled)) {
        return YES;
    }

    if (!registered && error) {
        *error = registrationError
            ?: IPError(@"Helper setup failed. Install the complete signed app in Applications, "
                       @"then select Approve Helper in the menu to retry.");
    }

    return registered;
}

- (void)suppressAutomaticSetup
{
    [_defaults setBool:YES forKey:IPHelperSetupAttempted];
}

- (void)resetAutomaticSetupAfterRemoval
{
    [_defaults removeObjectForKey:IPHelperSetupAttempted];
}

@end
