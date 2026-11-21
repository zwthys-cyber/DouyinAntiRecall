#import <UIKit/UIKit.h>
#import "DARBadge.h"

static void Record(NSString *status) {
    NSString *folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [status writeToFile:[folder stringByAppendingPathComponent:@"badge-result.txt"]
            atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
static void Check(BOOL condition, NSString *message) {
    if (!condition) { Record([@"FAIL: " stringByAppendingString:message]); NSLog(@"FAIL: %@", message); exit(1); }
    Record([@"CHECK: " stringByAppendingString:message]);
}
@interface BadgeAccount : NSObject
@property(nonatomic, copy) NSString *userID;
@end
@implementation BadgeAccount
@end
@interface BadgeSDKMessage : NSObject
@property(nonatomic, strong) BadgeAccount *db;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *belongingConversationIdentifier;
@end
@implementation BadgeSDKMessage
@end
@interface BadgeMessage : NSObject
@property(nonatomic, copy) NSDictionary *syncedExt;
@property(nonatomic, strong) BadgeSDKMessage *sdk;
- (id)transToIESMessage;
@end
@implementation BadgeMessage
- (id)transToIESMessage { return self.sdk; }
@end
@interface BadgeViewModel : NSObject
@property(nonatomic, strong) BadgeMessage *message;
@end
@implementation BadgeViewModel
@end
@interface AWEIMMessageBaseTableViewCell : UITableViewCell
@property(nonatomic, strong) BadgeMessage *message;
@property(nonatomic, strong) BadgeViewModel *viewModel;
@property(nonatomic, strong) UIView *bubble;
@property(nonatomic) CGRect testBubbleFrame;
- (UIView *)visibleContentView;
- (UIView *)containerView;
- (void)configWithMessage:(id)message;
@end
@implementation AWEIMMessageBaseTableViewCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        _bubble = [UIView new];
        [self.contentView addSubview:_bubble];
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.bubble.frame = self.testBubbleFrame; }
- (void)configWithMessage:(id)message { self.message = message; }
- (UIView *)visibleContentView { return self.bubble; }
- (UIView *)containerView { return self.bubble; }
@end
@interface AWEIMMessageBubbleThemeView : UIView
@end
@implementation AWEIMMessageBubbleThemeView
@end
@interface AWEIMReusableCommonCell : UITableViewCell
@property(nonatomic, strong) BadgeViewModel *currentContext;
@property(nonatomic, strong) UIView *bubble;
- (void)renderWithHolder:(id)holder;
@end
@implementation AWEIMReusableCommonCell
- (void)renderWithHolder:(id)holder { self.currentContext = holder; }
@end
static UILabel *Badge(UITableViewCell *cell) {
    for (UIView *view in cell.contentView.subviews)
        if ([view.accessibilityIdentifier isEqual:@"DouyinAntiRecall.status"]) return (UILabel *)view;
    return nil;
}
static void Layout(AWEIMMessageBaseTableViewCell *cell) { [cell setNeedsLayout]; [cell layoutIfNeeded]; }
static BadgeMessage *Snapshot(NSString *account, NSString *conversation, NSString *identifier) {
    BadgeMessage *message = [BadgeMessage new]; message.syncedExt = @{};
    message.sdk = [BadgeSDKMessage new]; message.sdk.db = [BadgeAccount new];
    message.sdk.db.userID = account; message.sdk.identifier = identifier;
    message.sdk.belongingConversationIdentifier = conversation;
    return message;
}
static AWEIMMessageBaseTableViewCell *LiveCell(BadgeMessage *message) {
    AWEIMMessageBaseTableViewCell *cell = [[AWEIMMessageBaseTableViewCell alloc] initWithStyle:0 reuseIdentifier:@"live"];
    cell.frame = CGRectMake(0, 0, 320, 84); cell.testBubbleFrame = CGRectMake(54, 8, 120, 40);
    [cell configWithMessage:message]; Layout(cell);
    return cell;
}
static void RunTests(void) {
    Check(DARInstallBadgeHooks(), @"badge hooks install");
    Check(DARInstallBadgeHooks(), @"badge hooks install once");
    BadgeMessage *recalled = [BadgeMessage new]; recalled.syncedExt = @{DARRecallStatusKey: @"1"};
    BadgeMessage *normal = [BadgeMessage new]; normal.syncedExt = @{};
    AWEIMMessageBaseTableViewCell *cell = [[AWEIMMessageBaseTableViewCell alloc] initWithStyle:0 reuseIdentifier:@"test"];
    cell.frame = CGRectMake(0, 0, 320, 84);
    cell.testBubbleFrame = CGRectMake(54, 8, 120, 40);
    [cell configWithMessage:recalled]; Layout(cell);
    UILabel *label = Badge(cell);
    Check(label && !label.hidden && [label.text isEqual:@"已撤回"], @"subtle status label appears");
    Check(label.font.pointSize == 10 && !label.userInteractionEnabled, @"small non-interactive label");
    Check(CGRectGetMinY(label.frame) >= CGRectGetMaxY(cell.bubble.frame), @"badge sits below bubble when space permits");
    Check(!CGRectIntersectsRect(label.frame, cell.bubble.frame), @"label never overlaps message content");
    Check(CGRectContainsRect(cell.contentView.bounds, label.frame), @"label stays inside cell");
    Layout(cell); Check(Badge(cell) == label, @"layout reuses one label");
    cell.frame = CGRectMake(0, 0, 320, 54);
    cell.testBubbleFrame = CGRectMake(54, 8, 120, 40); Layout(cell);
    Check(!label.hidden && CGRectGetMinX(label.frame) > CGRectGetMaxX(cell.bubble.frame), @"compact rows place badge beside bubble");
    Check(!CGRectIntersectsRect(label.frame, cell.bubble.frame), @"side badge never covers message content");
    cell.testBubbleFrame = CGRectMake(54, 8, 260, 40); Layout(cell);
    Check(label.hidden, @"insufficient space hides label instead of covering text");
    cell.testBubbleFrame = CGRectMake(54, 8, 120, 40); Layout(cell);
    [cell prepareForReuse]; Check(label.hidden, @"reuse immediately hides old status");
    [cell configWithMessage:normal]; Layout(cell); Check(label.hidden, @"normal messages have no badge");
    [cell configWithMessage:recalled]; Layout(cell); Check(!label.hidden, @"recalled reused cell regains badge");
    [cell configWithMessage:normal]; Check(label.hidden, @"configuration clears stale badge before layout");
    [cell configWithMessage:nil];
    cell.viewModel = [BadgeViewModel new]; cell.viewModel.message = recalled; Layout(cell);
    Check(!label.hidden, @"view model message path supported");
    cell.bubble.hidden = YES; Layout(cell); Check(label.hidden, @"hidden bubble hides badge");
    cell.bubble.hidden = NO;
    cell.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; Layout(cell);
    Check(!label.hidden && [label.textColor isEqual:UIColor.secondaryLabelColor], @"dynamic secondary color supports dark mode");
    AWEIMReusableCommonCell *modern = [[AWEIMReusableCommonCell alloc] initWithStyle:0 reuseIdentifier:@"modern"];
    modern.frame = CGRectMake(0, 0, 320, 84);
    modern.bubble = [[AWEIMMessageBubbleThemeView alloc] initWithFrame:CGRectMake(54, 8, 120, 40)];
    [modern.contentView addSubview:modern.bubble];
    BadgeViewModel *context = [BadgeViewModel new]; context.message = recalled;
    [modern renderWithHolder:context]; [modern layoutIfNeeded];
    UILabel *modernLabel = Badge(modern);
    Check(modernLabel && !modernLabel.hidden, @"component cell reads currentContext and discovers known bubble view");
    Check(!CGRectIntersectsRect(modernLabel.frame, modern.bubble.frame), @"component badge never overlaps bubble");
    [modern prepareForReuse]; Check(modernLabel.hidden, @"component reuse hides status");
    context.message = normal; [modern renderWithHolder:context]; [modern layoutIfNeeded];
    Check(modernLabel.hidden, @"component normal render clears status");
    BadgeMessage *stale = Snapshot(@"1001", @"conversation-live", @"message-live");
    AWEIMMessageBaseTableViewCell *live = LiveCell(stale);
    AWEIMMessageBaseTableViewCell *otherAccount = LiveCell(Snapshot(@"3003", @"conversation-live", @"message-live"));
    AWEIMMessageBaseTableViewCell *otherConversation = LiveCell(Snapshot(@"1001", @"other", @"message-live"));
    AWEIMMessageBaseTableViewCell *otherMessage = LiveCell(Snapshot(@"1001", @"conversation-live", @"other"));
    Check(!Badge(live) || Badge(live).hidden, @"stale visible snapshot starts unmarked");
    AWEIMReusableCommonCell *liveModern = [[AWEIMReusableCommonCell alloc] initWithStyle:0 reuseIdentifier:@"live-modern"];
    liveModern.frame = CGRectMake(0, 0, 320, 84);
    liveModern.bubble = [[AWEIMMessageBubbleThemeView alloc] initWithFrame:CGRectMake(54, 8, 120, 40)];
    [liveModern.contentView addSubview:liveModern.bubble];
    BadgeViewModel *liveContext = [BadgeViewModel new]; liveContext.message = stale;
    [liveModern renderWithHolder:liveContext]; [liveModern layoutIfNeeded];
    NSString *liveKey = DARTrackingKeyForMessage(stale);
    Check(liveKey.length > 0, @"presentation snapshot resolves SDK account and identity");
    [[NSNotificationCenter defaultCenter] postNotificationName:DARRecallStatusDidChangeNotification
                                                      object:nil userInfo:@{@"key": liveKey}];
    // Do not relayout, reconfigure, scroll, or re-enter the conversation here.
    Check(Badge(live) && !Badge(live).hidden, @"legacy visible badge refreshes immediately with stale presentation data");
    Check(Badge(liveModern) && !Badge(liveModern).hidden, @"component visible badge refreshes immediately with stale context data");
    Check(stale.syncedExt.count == 0, @"live notification never mutates stale app snapshots");
    Check(!Badge(otherAccount) || Badge(otherAccount).hidden, @"live refresh isolates accounts");
    Check(!Badge(otherConversation) || Badge(otherConversation).hidden, @"live refresh isolates conversations");
    Check(!Badge(otherMessage) || Badge(otherMessage).hidden, @"live refresh isolates message IDs");
    Layout(live); Check(!Badge(live).hidden, @"later layouts retain live status despite stale metadata");
    [live prepareForReuse]; [live configWithMessage:Snapshot(@"1001", @"conversation-live", @"next")]; Layout(live);
    Check(Badge(live).hidden, @"reuse clears the live status override");
    [liveModern prepareForReuse];
    liveContext.message = Snapshot(@"1001", @"conversation-live", @"background");
    [liveModern renderWithHolder:liveContext]; [liveModern layoutIfNeeded];
    NSString *backgroundKey = DARTrackingKeyForMessage(liveContext.message);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:DARRecallStatusDidChangeNotification
                                                          object:nil userInfo:@{@"key": backgroundKey}];
        // Posting from this thread enqueues the UI refresh first. Enqueue the
        // assertion after it, and return from RunTests so the main queue can run.
        dispatch_async(dispatch_get_main_queue(), ^{
            Check(Badge(liveModern) && !Badge(liveModern).hidden, @"background notification refreshes UIKit on the main thread");
            Record(@"PASS: UIKit badge placement, no overlap, reuse, configuration, view model path, dark mode, immediate stale-model refresh and identity isolation");
            puts("PASS: UIKit badge placement, no overlap, reuse, configuration, view model path, dark mode, immediate stale-model refresh and identity isolation");
            fflush(stdout);
            exit(0);
        });
    });
}
@interface BadgeTestDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation BadgeTestDelegate
- (BOOL)application:(__unused UIApplication *)application didFinishLaunchingWithOptions:(__unused NSDictionary *)options {
    Record(@"DELEGATE: test app launched");
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 393, 852)];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ RunTests(); });
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { Record(@"START: entering UIApplicationMain"); return UIApplicationMain(argc, argv, nil, NSStringFromClass(BadgeTestDelegate.class)); }
}
