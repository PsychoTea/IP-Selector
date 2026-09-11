#import "IPTestSupport.h"

IPPreset *IPTestPreset(void)
{
    IPPreset *preset = [IPPreset new];
    preset.name = @"Lighting";
    preset.address = @"192.168.10.20";
    preset.mask = @"255.255.255.0";
    preset.gateway = @"";
    preset.dns = @[];

    return preset;
}

IPAdapterSnapshot *IPTestAdapter(void)
{
    IPAdapterSnapshot *adapter = [IPAdapterSnapshot new];
    adapter.serviceID = @"service-A";
    adapter.serviceName = @"USB Ethernet";
    adapter.bsdName = @"en5";
    adapter.mac = @"00:11:22:33:44:55";
    adapter.registryID = @123;
    adapter.ipv4 = @{@"ConfigMethod": @"DHCP", @"DHCPClientID": @"desk", @"Unrelated": @YES};
    adapter.dns = @{@"ServerAddresses": @[@"1.1.1.1"], @"SearchDomains": @[@"studio.example"]};

    return adapter;
}

IPAdapterSnapshot *IPCopyTestAdapter(IPAdapterSnapshot *adapter)
{
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:adapter requiringSecureCoding:YES
                                                         error:NULL];

    return [NSKeyedUnarchiver unarchivedObjectOfClass:IPAdapterSnapshot.class fromData:data
                                                error:NULL];
}

@implementation IPFakeAccess

- (instancetype)init
{
    if ((self = [super init])) {
        _saved = IPTestAdapter();
    }

    return self;
}

- (BOOL)lock:(NSError **)error
{
    self.staged = IPCopyTestAdapter(self.saved);
    self.unlocked = NO;
    self.snapshotCount = 0;
    if (self.failLock && error) {
        *error = IPError(@"Lock failed.");
    }

    return !self.failLock;
}

- (void)unlock
{
    self.unlocked = YES;
}

- (IPAdapterSnapshot *)snapshot:(NSString *)serviceID
{
    self.snapshotCount++;
    if (self.replaceBeforeRestore && self.snapshotCount >= 3) {
        self.staged.registryID = @999;
    }

    if (self.detachBeforeCommit && self.snapshotCount >= 2) {
        return nil;
    }

    return [self.staged.serviceID isEqual:serviceID] ? IPCopyTestAdapter(self.staged) : nil;
}

- (BOOL)stageIPv4:(NSDictionary *)ipv4
              dns:(NSDictionary *)dns
          service:(NSString *)serviceID
            error:(NSError **)error
{
    if (self.throwOnStage) {
        [NSException raise:NSInternalInconsistencyException format:@"Injected stage failure."];
    }

    if (self.failStage) {
        if (error) {
            *error = IPError(@"Stage failed.");
        }

        return NO;
    }

    self.staged.ipv4 = ipv4;
    self.staged.dns = dns;

    return YES;
}

- (BOOL)commit:(NSError **)error
{
    self.commitCount++;
    if (self.commitCount == self.failCommitAt) {
        if (error) {
            *error = IPError(@"Commit failed.");
        }

        return NO;
    }

    self.saved = IPCopyTestAdapter(self.staged);

    return YES;
}

- (BOOL)apply:(NSError **)error
{
    self.applyCount++;
    if (self.applyCount == self.failApplyAt) {
        if (error) {
            *error = IPError(@"Apply failed.");
        }

        return NO;
    }

    return YES;
}

- (IPAdapterSnapshot *)readBack:(NSString *)serviceID
{
    IPAdapterSnapshot *adapter = IPCopyTestAdapter(self.saved);
    if (self.corruptReadBack && self.commitCount == 1) {
        adapter.dns = @{ @"ServerAddresses": @[@"9.9.9.9"] };
    }

    return adapter;
}

@end

@implementation IPTemporaryDirectoryTestCase

- (void)setUp
{
    self.directory =
        [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                   stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                   isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:self.directory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:NULL];
}

- (void)tearDown
{
    [NSFileManager.defaultManager removeItemAtURL:self.directory error:NULL];
}

- (IPPresetStore *)store
{
    return [[IPPresetStore alloc]
        initWithURL:[self.directory URLByAppendingPathComponent:@"store.json"]];
}

@end
