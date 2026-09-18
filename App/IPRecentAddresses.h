#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface IPRecentAddresses : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property (nonatomic, readonly, copy) NSArray<NSString *> *addresses;
- (void)recordAddress:(NSString *)address;
@end
NS_ASSUME_NONNULL_END
