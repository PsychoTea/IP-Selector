#import <Cocoa/Cocoa.h>
#import "IPModels.h"

NS_ASSUME_NONNULL_BEGIN
@protocol IPAdapterMenuActions <NSObject>
- (void)apply:(NSMenuItem *)sender;
- (void)quickChange:(NSMenuItem *)sender;
@end

@interface IPAdapterMenu : NSMenu
@property (nonatomic, readonly) IPAdapterSnapshot *adapter;
- (instancetype)initWithAdapter:(IPAdapterSnapshot *)adapter
                        presets:(NSArray<IPPreset *> *)presets
                         target:(id<IPAdapterMenuActions>)target;
- (void)refreshWithAdapter:(nullable IPAdapterSnapshot *)adapter busy:(BOOL)busy;
@end
NS_ASSUME_NONNULL_END
