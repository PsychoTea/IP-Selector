#import "IPModels.h"

NS_ASSUME_NONNULL_BEGIN

@protocol IPNetworkAccess <NSObject>
- (BOOL)lock:(NSError **)error;
- (void)unlock;
- (nullable IPAdapterSnapshot *)snapshot:(NSString *)serviceID;
- (BOOL)stageIPv4:(NSDictionary *)ipv4
              dns:(NSDictionary *)dns
          service:(NSString *)serviceID
            error:(NSError **)error;
- (BOOL)commit:(NSError **)error;
- (BOOL)apply:(NSError **)error;
- (nullable IPAdapterSnapshot *)readBack:(NSString *)serviceID;
@end

@interface IPSystemNetworkAccess : NSObject <IPNetworkAccess>
@end

NS_ASSUME_NONNULL_END
