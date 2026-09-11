#import "IPPresetStore.h"
NSNotificationName const IPPresetsChanged = @"IPPresetsChanged";
@implementation IPPresetStore {
    NSURL *_url;
}

- (instancetype)initWithURL:(NSURL *)url
{
    if ((self = [super init])) {
        _url = url;
        _presets = @[];
        _aliases = @{};

        if ([NSFileManager.defaultManager fileExistsAtPath:url.path]) {
            NSError *error = nil;
            NSDictionary *document = [self readURL:url error:&error];

            NSArray *presets = document ? [self parsePresets:document error:&error] : nil;

            NSDictionary *aliases = document ? [self parseAliases:document error:&error] : nil;
            if (error || !presets || !aliases) {
                _loadError = error ?: IPError(@"The saved preset list could not be read.");
            } else {
                _presets = presets;
                _aliases = [aliases copy];
            }
        }
    }

    return self;
}

- (NSDictionary<NSString *, NSString *> *)parseAliases:(NSDictionary *)document
                                                 error:(NSError **)error
{
    NSDictionary *aliases = document[@"aliases"] ?: @{};
    if (![aliases isKindOfClass:NSDictionary.class]) {
        IPValidationFailure(error, @"The saved adapter names are invalid.");
        return nil;
    }

    for (id key in aliases) {
        NSString *normalized = IPNormalizedMAC(key);
        id name = aliases[key];
        if (!normalized || ![key isEqual:normalized] || ![name isKindOfClass:NSString.class] ||
            [name length] > 100) {
            IPValidationFailure(error, @"A saved adapter name is invalid.");
            return nil;
        }
    }

    return aliases;
}

- (NSDictionary *)readURL:(NSURL *)url error:(NSError **)error
{
    NSNumber *size;
    if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:error]) {
        return nil;
    }

    if (size.unsignedLongLongValue > 2 * 1024 * 1024) {
        if (error) {
            *error = IPError(@"The preset file exceeds 2 MB.");
        }

        return nil;
    }

    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) {
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!object) {
        return nil;
    }

    if (![object isKindOfClass:NSDictionary.class]
        || ![object[@"version"] isKindOfClass:NSNumber.class] || ![object[@"version"] isEqual:@1]
        || CFGetTypeID((__bridge CFTypeRef)object[@"version"]) == CFBooleanGetTypeID()) {
        if (error) {
            *error = IPError(@"This file is not a supported version 1 preset file.");
        }

        return nil;
    }

    return object;
}

- (NSArray<IPPreset *> *)parsePresets:(NSDictionary *)document error:(NSError **)error
{
    NSArray *objects = document[@"presets"];
    if (![objects isKindOfClass:NSArray.class] || objects.count > 1000) {
        if (error) {
            *error = IPError(@"The file must contain a list of no more than 1000 presets.");
        }

        return nil;
    }

    NSMutableArray *presets = [NSMutableArray array];
    NSMutableSet *identifiers = [NSMutableSet set];
    for (id object in objects) {
        IPPreset *preset = [IPPreset fromJSON:object error:error];
        if (!preset) {
            return nil;
        }

        if ([identifiers containsObject:preset.identifier]) {
            if (error) {
                *error = IPError(@"The file contains duplicate preset IDs.");
            }

            return nil;
        }

        [identifiers addObject:preset.identifier];
        [presets addObject:preset];
    }

    return presets;
}

- (BOOL)writePresets:(NSArray<IPPreset *> *)presets
             aliases:(NSDictionary *)aliases
               error:(NSError **)error
{
    if (self.loadError) {
        if (error) {
            *error = IPError(@"The saved file could not be read. Move it aside, then restart the "
                             @"app. The app will not overwrite it.");
        }

        return NO;
    }

    NSMutableArray *objects = [NSMutableArray array];
    for (IPPreset *preset in presets) {
        [objects addObject:preset.JSON];
    }

    NSDictionary *document = @{ @"version": @1, @"presets": objects, @"aliases": aliases };
    NSArray *validated = [self parsePresets:document error:error];
    if (!validated) {
        return NO;
    }

    NSData *data =
        [NSJSONSerialization dataWithJSONObject:document
                                        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                          error:error];
    if (!data) {
        return NO;
    }

    if (![NSFileManager.defaultManager createDirectoryAtURL:_url.URLByDeletingLastPathComponent
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:error]
        || ![data writeToURL:_url options:NSDataWritingAtomic error:error]) {
        return NO;
    }

    _presets = validated;
    _aliases = [aliases copy];
    [NSNotificationCenter.defaultCenter postNotificationName:IPPresetsChanged object:self];

    return YES;
}

- (BOOL)replacePresets:(NSArray<IPPreset *> *)presets error:(NSError **)error
{
    return [self writePresets:presets aliases:self.aliases error:error];
}

- (BOOL)setAlias:(NSString *)alias forMAC:(NSString *)mac error:(NSError **)error
{
    NSString *key = IPNormalizedMAC(mac);
    if (!key || alias.length > 100) {
        if (error) {
            *error = IPError(
                @"Use a valid adapter MAC address and a name of no more than 100 characters.");
        }

        return NO;
    }

    NSMutableDictionary *aliases = [self.aliases mutableCopy];
    NSString *name =
        [alias stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length) {
        aliases[key] = name;
    } else {
        [aliases removeObjectForKey:key];
    }

    return [self writePresets:self.presets aliases:aliases error:error];
}

- (BOOL)importURL:(NSURL *)url error:(NSError **)error
{
    NSDictionary *document = [self readURL:url error:error];
    if (!document) {
        return NO;
    }

    NSArray *incoming = [self parsePresets:document error:error];
    if (!incoming) {
        return NO;
    }

    NSMutableArray *merged = [self.presets mutableCopy];
    for (IPPreset *preset in incoming) {
        preset.identifier = NSUUID.UUID.UUIDString;
        [merged addObject:preset];
    }

    return [self replacePresets:merged error:error];
}

- (BOOL)exportURL:(NSURL *)url error:(NSError **)error
{
    NSMutableArray *objects = [NSMutableArray array];
    for (IPPreset *preset in self.presets) {
        [objects addObject:preset.JSON];
    }

    NSData *data =
        [NSJSONSerialization dataWithJSONObject:@{ @"version": @1, @"presets": objects }
                                        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                          error:error];

    return data && [data writeToURL:url options:NSDataWritingAtomic error:error];
}

@end
