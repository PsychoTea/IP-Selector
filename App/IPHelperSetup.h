#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>

@protocol IPHelperRegistration <NSObject>
@property (nonatomic, readonly) SMAppServiceStatus status;
- (BOOL)registerAndReturnError:(NSError **)error;
@end

// All calls are made on the main thread. Registration does not grant OS approval.
@interface IPHelperSetup : NSObject
- (instancetype)initWithService:(id<IPHelperRegistration>)service
                       defaults:(NSUserDefaults *)defaults
                   signingReady:(BOOL (^)(void))signingReady;
// Returns YES only when this launch starts setup or needs to show its result.
- (BOOL)prepareOnFirstLaunch:(NSError **)error;
- (BOOL)registerHelper:(NSError **)error;
- (void)suppressAutomaticSetup;
- (void)resetAutomaticSetupAfterRemoval;
@end
