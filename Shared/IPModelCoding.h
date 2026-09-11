#import <Foundation/Foundation.h>

// Property-list classes allowed in archived network settings.
static inline NSSet *IPPropertyClasses(void)
{
    return [NSSet setWithObjects:NSDictionary.class,
        NSArray.class,
        NSString.class,
        NSNumber.class,
        NSData.class,
        NSDate.class,
        nil];
}
