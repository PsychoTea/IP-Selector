#import "IPModels.h"

NS_ASSUME_NONNULL_BEGIN
@interface IPQuickChangeRequestBuilder : NSObject
- (instancetype)initWithAdaptersProvider:(NSArray<IPAdapterSnapshot *> * (^)(void))adaptersProvider
                             DNSProvider:(NSDictionary * (^)(NSString *serviceID))DNSProvider;
- (nullable IPApplyRequest *)requestForPreset:(IPPreset *)preset
                                      adapter:(IPAdapterSnapshot *)expected
                                        error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
