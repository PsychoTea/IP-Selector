#import <XCTest/XCTest.h>
#import "IPModels.h"
#import "IPNetworkWriter.h"
#import "IPPresetStore.h"

IPPreset *IPTestPreset(void);
IPAdapterSnapshot *IPTestAdapter(void);
IPAdapterSnapshot *IPCopyTestAdapter(IPAdapterSnapshot *adapter);

@interface IPTemporaryDirectoryTestCase : XCTestCase
@property (nonatomic, strong) NSURL *directory;
@property (nonatomic, readonly) IPPresetStore *store;
@end

@interface IPFakeAccess : NSObject <IPNetworkAccess>
@property (nonatomic) BOOL replaceBeforeRestore;
@property (nonatomic) BOOL throwOnStage;
@property (nonatomic, strong) IPAdapterSnapshot *saved;
@property (nonatomic, strong) IPAdapterSnapshot *staged;
@property (nonatomic) NSInteger commitCount, applyCount, snapshotCount;
@property (nonatomic) NSInteger failCommitAt, failApplyAt;
@property (nonatomic) BOOL failLock, failStage, detachBeforeCommit, corruptReadBack, unlocked;
@end
