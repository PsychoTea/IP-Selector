#import "IPAddressUtilities.h"
#import "IPError.h"

NS_ASSUME_NONNULL_BEGIN
@interface IPPreset : NSObject <NSSecureCoding, NSCopying>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *address;
@property (nonatomic, copy) NSString *mask;
@property (nonatomic, copy) NSString *gateway;
@property (nonatomic, copy) NSArray<NSString *> *dns;
- (BOOL)validate:(NSError **)error;
- (NSDictionary *)JSON;
+ (nullable instancetype)fromJSON:(id)object error:(NSError **)error;
@end

typedef NS_ENUM(NSInteger, IPConnectionStatus) {
    IPConnectionStatusNotConnected,
    IPConnectionStatusSelfAssigned,
    IPConnectionStatusConnected
};

@interface IPAdapterSnapshot : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *serviceID;
@property (nonatomic, copy) NSString *serviceName;
@property (nonatomic, copy) NSString *bsdName;
@property (nonatomic, copy) NSString *mac;
@property (nonatomic, copy) NSNumber *registryID;
@property (nonatomic, getter=isWiFi) BOOL wiFi;
@property (nonatomic) BOOL linkActive;
@property (nonatomic, readonly) IPConnectionStatus connectionStatus;
@property (nonatomic, copy) NSArray<NSString *> *activeAddresses;
@property (nonatomic, copy) NSDictionary *ipv4;
@property (nonatomic, copy) NSDictionary *dns;
- (BOOL)sameAttachment:(nullable IPAdapterSnapshot *)other;
- (BOOL)sameConfiguration:(nullable IPAdapterSnapshot *)other;
- (BOOL)matchesPreset:(IPPreset *)preset;
- (BOOL)isAutomatic;
@end

@interface IPApplyRequest : NSObject <NSSecureCoding>
@property (nonatomic, strong) IPAdapterSnapshot *expected;
@property (nonatomic, nullable, strong) IPPreset *preset;
@property (nonatomic) BOOL useDHCP;
@end

@interface IPApplyResult : NSObject <NSSecureCoding>
@property (nonatomic) BOOL success;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, nullable, strong) IPAdapterSnapshot *current;
@property (nonatomic, nullable, copy) NSString *undoToken;
+ (instancetype)failure:(NSString *)message;
+ (instancetype)success:(NSString *)message
                current:(IPAdapterSnapshot *)current
              undoToken:(nullable NSString *)undoToken;
@end

// Pure configuration functions, shared by the helper and tests.
FOUNDATION_EXPORT NSDictionary *IPDesiredIPv4(
    NSDictionary *existing, IPPreset *_Nullable preset, BOOL dhcp);
FOUNDATION_EXPORT NSDictionary *IPDesiredDNS(
    NSDictionary *existing, IPPreset *_Nullable preset, BOOL dhcp);
NS_ASSUME_NONNULL_END
