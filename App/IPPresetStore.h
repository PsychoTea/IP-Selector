#import "IPModels.h"
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const IPPresetsChanged;
@interface IPPresetStore : NSObject
@property (nonatomic, readonly, copy) NSArray<IPPreset *> *presets;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *aliases;
@property (nonatomic, readonly, nullable) NSError *loadError;
- (instancetype)initWithURL:(NSURL *)url;
- (BOOL)replacePresets:(NSArray<IPPreset *> *)presets error:(NSError **)error;
- (BOOL)setAlias:(NSString *)alias forMAC:(NSString *)mac error:(NSError **)error;
- (BOOL)importURL:(NSURL *)url error:(NSError **)error;
- (BOOL)exportURL:(NSURL *)url error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
