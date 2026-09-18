#import "IPTestSupport.h"

@interface IPPresetStoreTests : IPTemporaryDirectoryTestCase
@end

@implementation IPPresetStoreTests

- (void)testStoreAndAliasRoundTrip
{
    IPPresetStore *store = self.store;

    XCTAssertTrue([store replacePresets:@[IPTestPreset()] error:NULL]);
    XCTAssertTrue([store setAlias:@"Audio" forMAC:@"00-11-22-33-44-55" error:NULL]);

    IPPresetStore *loaded = self.store;

    XCTAssertNil(loaded.loadError);
    XCTAssertEqualObjects(loaded.presets.firstObject.JSON, store.presets.firstObject.JSON);
    XCTAssertEqualObjects(loaded.aliases[@"00:11:22:33:44:55"], @"Audio");
}

- (void)testImportCreatesNewIDsAndExcludesAliases
{
    IPPresetStore *store = self.store;
    [store replacePresets:@[IPTestPreset()] error:NULL];
    [store setAlias:@"Audio" forMAC:@"00:11:22:33:44:55" error:NULL];
    NSURL *file = [self.directory URLByAppendingPathComponent:@"export.json"];

    XCTAssertTrue([store exportURL:file error:NULL]);

    NSDictionary *document =
        [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:file] options:0
                                          error:NULL];

    XCTAssertNil(document[@"aliases"]);

    NSString *original = store.presets.firstObject.identifier;

    XCTAssertTrue([store importURL:file error:NULL]);
    XCTAssertEqual(store.presets.count, 2u);
    XCTAssertNotEqualObjects(original, store.presets.lastObject.identifier);
}

- (void)testImportIsAllOrNothing
{
    IPPresetStore *store = self.store;
    [store replacePresets:@[IPTestPreset()] error:NULL];
    NSURL *file = [self.directory URLByAppendingPathComponent:@"invalid.json"];
    NSDictionary *document =
        @{ @"version": @1, @"presets": @[IPTestPreset().JSON, @{ @"name": @"bad" }] };
    [[NSJSONSerialization dataWithJSONObject:document options:0
                                       error:NULL] writeToURL:file atomically:YES];

    XCTAssertFalse([store importURL:file error:NULL]);
    XCTAssertEqual(store.presets.count, 1u);
}

- (void)testCorruptStoreIsNotOverwritten
{
    NSURL *url = [self.directory URLByAppendingPathComponent:@"store.json"];
    [@"broken" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    IPPresetStore *store = self.store;

    XCTAssertNotNil(store.loadError);
    XCTAssertFalse([store replacePresets:@[IPTestPreset()] error:NULL]);
    XCTAssertEqualObjects(
        [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL], @"broken");
}

- (void)testUnsupportedVersionIsRejected
{
    NSURL *url = [self.directory URLByAppendingPathComponent:@"new.json"];
    [@"{\"version\":2,\"presets\":[]}" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding
                                            error:NULL];

    XCTAssertFalse([self.store importURL:url error:NULL]);
}

- (void)testInvalidAliasesDoNotPublishOrOverwritePresets
{
    NSURL *url = [self.directory URLByAppendingPathComponent:@"store.json"];
    for (id aliases in @[@42, @{ @"invalid-mac": @"Audio" }, @{ @"00:11:22:33:44:55": @42 }]) {
        NSDictionary *document =
            @{ @"version": @1, @"presets": @[IPTestPreset().JSON], @"aliases": aliases };
        NSData *original = [NSJSONSerialization dataWithJSONObject:document options:0 error:NULL];

        XCTAssertTrue([original writeToURL:url options:NSDataWritingAtomic error:NULL]);

        IPPresetStore *store = self.store;

        XCTAssertNotNil(store.loadError);
        XCTAssertEqual(store.presets.count, 0u);
        XCTAssertEqual(store.aliases.count, 0u);
        XCTAssertFalse([store replacePresets:@[IPTestPreset()] error:NULL]);
        XCTAssertEqualObjects([NSData dataWithContentsOfURL:url], original);
    }
}

- (void)testSaveUpdatesByIdentifierAndPreservesOrder
{
    IPPresetStore *store = self.store;
    IPPreset *first = IPTestPreset();
    IPPreset *second = IPTestPreset();
    XCTAssertTrue([store savePreset:first error:nil]);
    XCTAssertTrue([store savePreset:second error:nil]);
    first.name = @"Updated";
    XCTAssertTrue([store savePreset:first error:nil]);
    XCTAssertEqual(store.presets.count, 2u);
    XCTAssertEqualObjects(store.presets.firstObject.name, @"Updated");
    XCTAssertEqualObjects(store.presets.lastObject.identifier, second.identifier);
    XCTAssertEqualObjects(self.store.presets.firstObject.name, @"Updated");
}

- (void)testDeleteKeepsTheIntendedTargetAfterReordering
{
    IPPresetStore *store = self.store;
    IPPreset *first = IPTestPreset();
    IPPreset *second = IPTestPreset();
    XCTAssertTrue(([store replacePresets:@[first, second] error:nil]));
    NSString *deleteID = first.identifier;
    XCTAssertTrue([store movePresetWithIdentifier:deleteID by:1 error:nil]);
    XCTAssertTrue([store removePresetWithIdentifier:deleteID error:nil]);
    XCTAssertEqual(store.presets.count, 1u);
    XCTAssertEqualObjects(store.presets.firstObject.identifier, second.identifier);
    XCTAssertTrue([store removePresetWithIdentifier:deleteID error:nil]);
    XCTAssertEqual(store.presets.count, 1u);
}

- (void)testInvalidMoveDoesNotChangeTheStore
{
    IPPresetStore *store = self.store;
    IPPreset *preset = IPTestPreset();
    XCTAssertTrue([store savePreset:preset error:nil]);
    for (NSNumber *offset in @[@(-1), @0, @1, @(NSIntegerMax)]) {
        NSError *error = nil;
        XCTAssertFalse([store movePresetWithIdentifier:preset.identifier by:offset.integerValue
                                                 error:&error]);
        XCTAssertNotNil(error);
    }
    XCTAssertEqualObjects(store.presets.firstObject.JSON, preset.JSON);
    XCTAssertEqualObjects(self.store.presets.firstObject.JSON, preset.JSON);
}

@end
