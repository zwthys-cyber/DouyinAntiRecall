#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "DARCache.h"
#import "DARBadge.h"
extern BOOL DARInstallForTesting(void);

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
@interface TestStore : NSObject
@property(nonatomic, copy) NSString *userID;
@end
@implementation TestStore
@end
@interface TestModel : NSObject <NSCopying>
@property(nonatomic) long long sender;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *belongingConversationIdentifier;
@property(nonatomic, copy) NSDictionary *extDictionary;
@property(nonatomic, copy) NSDictionary *contentDictionary;
@end
@implementation TestModel
- (id)copyWithZone:(NSZone *)zone {
    TestModel *copy = [[[self class] allocWithZone:zone] init];
    copy.sender = self.sender;
    copy.identifier = self.identifier;
    copy.belongingConversationIdentifier = self.belongingConversationIdentifier;
    copy.extDictionary = self.extDictionary;
    copy.contentDictionary = self.contentDictionary;
    return copy;
}
@end
// Match the target's observed method ABI; simulate the disassembled recall conversion.
@interface TIMXOMessage : NSObject
@property(nonatomic, strong) TestStore *db;
@property(nonatomic, strong) TestModel *lastModel;
@property(nonatomic, strong) NSDictionary *content;
@property(nonatomic) BOOL recalled;
@property(nonatomic) NSUInteger calls;
- (void)applyLogicWithModel_DouYin:(id)model;
- (NSDictionary *)syncedExt;
@end
@implementation TIMXOMessage
- (NSDictionary *)syncedExt { return self.lastModel.extDictionary; }
- (void)applyLogicWithModel_DouYin:(id)model {
    self.calls++;
    self.lastModel = model;
    id flag = [model extDictionary][@"s:is_recalled"];
    self.recalled = [flag respondsToSelector:@selector(boolValue)] && [flag boolValue];
    self.content = self.recalled ? @{} : [model contentDictionary];
}
@end
static TestModel *Model(NSString *identifier, long long sender, NSDictionary *ext, NSDictionary *content) {
    TestModel *m = [TestModel new];
    m.identifier = identifier; m.sender = sender; m.belongingConversationIdentifier = @"conversation-A";
    m.extDictionary = ext; m.contentDictionary = content;
    return m;
}
int main(void) {
    @autoreleasepool {
        Check(DARInstallForTesting(), @"hook installs");
        Check(DARInstallForTesting(), @"repeated installation is idempotent");
        TIMXOMessage *message = [TIMXOMessage new];
        message.db = [TestStore new]; message.db.userID = @"1001";
        NSString *identifier = NSUUID.UUID.UUIDString;
        NSDictionary *body = @{@"text": @"retained text", @"nullable": NSNull.null};
        TestModel *normal = Model(identifier, 2002, @{@"business": @"unchanged"}, body);
        [message applyLogicWithModel_DouYin:normal];
        Check(message.lastModel == normal && !message.recalled, @"normal messages forwarded unchanged");
        NSDictionary *recallExt = @{@"s:is_recalled": @"true", @"s:recall_uid": @"2002",
                                     @"s:recall_role": @1, @"business": @"unchanged"};
        TestModel *recall = Model(identifier, 2002, recallExt, @{});
        [message applyLogicWithModel_DouYin:recall];
        NSDictionary *markedBody = body;
        Check(!message.recalled && [message.content isEqual:markedBody], @"incoming recall retains unmodified content");
        Check([normal.contentDictionary isEqual:body], @"badge never mutates the original content");
        [message applyLogicWithModel_DouYin:recall];
        Check([message.content isEqual:markedBody], @"repeated recall never adds text");
        Check(DARHasRecallBadge(message), @"retained messages carry a separate display status");
        Check(message.lastModel != recall && [recall.extDictionary isEqual:recallExt], @"upstream model never mutated");
        Check([message.lastModel.extDictionary[@"business"] isEqual:@"unchanged"], @"unrelated metadata preserved");
        Check(message.calls == 3, @"one original call per update");
        [message applyLogicWithModel_DouYin:Model(NSUUID.UUID.UUIDString, 2002, recallExt, @{@"text": @"present"})];
        Check(!message.recalled && [message.content[@"text"] isEqual:@"present"], @"retains original content without a text marker");
        NSDictionary *mention = @{@"text": @"@friend hello", @"mentions": @[@{@"offset": @0, @"length": @7}]};
        [message applyLogicWithModel_DouYin:Model(NSUUID.UUID.UUIDString, 2002, recallExt, mention)];
        Check([message.content[@"text"] hasPrefix:mention[@"text"]] &&
              [message.content[@"mentions"] isEqual:mention[@"mentions"]], @"original text and mention offsets preserved");
        NSDictionary *media = @{@"resource": @{@"uri": @"example"}, @"text": NSNull.null};
        [message applyLogicWithModel_DouYin:Model(NSUUID.UUID.UUIDString, 2002, recallExt, media)];
        Check(!message.recalled && [message.content isEqual:media], @"media and non-string text payloads stay intact");
        Check(DARHasRecallBadge(message), @"retained media also carries display status");
        [message applyLogicWithModel_DouYin:Model(NSUUID.UUID.UUIDString, 2002, recallExt, @{})];
        Check(message.recalled, @"missing original content leaves recall unchanged");
        [message applyLogicWithModel_DouYin:Model(identifier, 1001, recallExt, body)];
        Check(message.recalled, @"outgoing recalls remain enabled");
        Check(!DARHasRecallBadge(message), @"outgoing messages never carry a recall badge");
        Check([message.lastModel.contentDictionary isEqual:body], @"outgoing recalls never gain the marker");
        NSMutableDictionary *selfRecall = [recallExt mutableCopy]; selfRecall[@"s:recall_uid"] = @"1001";
        [message applyLogicWithModel_DouYin:Model(identifier, 2002, selfRecall, body)];
        Check(message.recalled, @"current account recalling another message remains enabled");
        message.db.userID = @"3003";
        [message applyLogicWithModel_DouYin:recall];
        Check(message.recalled, @"cache does not cross accounts");
        message.db.userID = @"1001";
        recall.belongingConversationIdentifier = @"conversation-B";
        [message applyLogicWithModel_DouYin:recall];
        Check(message.recalled, @"cache does not cross conversations");
        message.db.userID = nil;
        [message applyLogicWithModel_DouYin:Model(identifier, 2002, recallExt, body)];
        Check(message.recalled, @"unknown account fails open");
        message.db.userID = @"1001";
        [message applyLogicWithModel_DouYin:Model(identifier, 0, recallExt, body)];
        Check(message.recalled, @"unknown sender fails open");
        [message applyLogicWithModel_DouYin:Model(identifier, 2002, @{@"s:is_recalled": NSNull.null}, body)];
        Check(!message.recalled, @"malformed flag does not enter recall path");
        Check([message.content isEqual:body], @"ordinary messages remain unmarked");
        Check(!DARHasRecallBadge(message), @"ordinary updates clear the previous display status");
        NSURL *file = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                       URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".json"]];
        DARCache *cache = [[DARCache alloc] initWithURL:file];
        [cache storeContent:body forKey:@"key"];
        [cache flush];
        DARCache *reloaded = [[DARCache alloc] initWithURL:file];
        Check([[reloaded contentForKey:@"key"] isEqual:body], @"cache survives process restart including JSON null");
        NSString *large = [@"x" stringByPaddingToLength:70000 withString:@"x" startingAtIndex:0];
        [cache storeContent:@{@"text": large} forKey:@"oversize"];
        Check(![cache contentForKey:@"oversize"], @"oversized content rejected");
        for (int i=0; i<1001; i++) [cache storeContent:@{@"text": @(i)} forKey:[NSString stringWithFormat:@"entry-%d",i]];
        Check(![cache contentForKey:@"entry-0"], @"cache evicts oldest entries");
        [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
        puts("PASS: message conversion, ownership, isolation, immutability, persistence, cache limits");
    }
    return 0;
}
