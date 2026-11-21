#import <UIKit/UIKit.h>
#import "DARBadge.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
@interface BadgeMessage : NSObject
@property(nonatomic, copy) NSDictionary *syncedExt;
@end
@implementation BadgeMessage
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
static UILabel *Badge(UITableViewCell *cell) {
    for (UIView *view in cell.contentView.subviews)
        if ([view.accessibilityIdentifier isEqual:@"DouyinAntiRecall.status"]) return (UILabel *)view;
    return nil;
}
static void Layout(AWEIMMessageBaseTableViewCell *cell) { [cell setNeedsLayout]; [cell layoutIfNeeded]; }
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
    puts("PASS: UIKit badge placement, no overlap, reuse, configuration, view model path, dark mode");
    fflush(stdout);
}
@interface BadgeTestDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation BadgeTestDelegate
- (BOOL)application:(__unused UIApplication *)application didFinishLaunchingWithOptions:(__unused NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 393, 852)];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ RunTests(); exit(0); });
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(BadgeTestDelegate.class)); }
}
