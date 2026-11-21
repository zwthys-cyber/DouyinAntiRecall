#import "DARNotifications.h"
#import "DARFeatures.h"
#import "DARLoginDiagnostics.h"
#import "DARPushBinding.h"

static void DARNotificationMain(void (^block)(void)) {
    if(NSThread.isMainThread)block();else dispatch_async(dispatch_get_main_queue(),block);
}
NSString *DARPushEnvironment(id value) {
    if(!value)return @"未声明";
    if(![value isKindOfClass:NSString.class])return @"类型异常";
    return [value isEqual:@"development"] || [value isEqual:@"production"]?value:@"值异常";
}
static BOOL DARPushEnvironmentValid(id value) {
    return [value isKindOfClass:NSString.class] && ([value isEqual:@"development"] || [value isEqual:@"production"]);
}
static BOOL DARNotificationAllowed(NSInteger status) {
    return status==UNAuthorizationStatusAuthorized || status==UNAuthorizationStatusProvisional || status==UNAuthorizationStatusEphemeral;
}
static NSString *DARNotificationError(NSError *error) {
    // Do not copy localizedDescription/userInfo, which may contain host data.
    return [NSString stringWithFormat:@"系统错误码 %ld",(long)error.code];
}
NSString *DARNotificationReport(NSDictionary *state,id environment) {
    NSInteger status=[state[@"authorization"] integerValue];
    NSString *authorization=@"未知";
    switch(status) {
        case UNAuthorizationStatusNotDetermined:authorization=@"尚未请求";break;
        case UNAuthorizationStatusDenied:authorization=@"已拒绝，请到系统设置开启";break;
        case UNAuthorizationStatusAuthorized:authorization=@"已允许";break;
        case UNAuthorizationStatusProvisional:authorization=@"临时授权（可能安静投递）";break;
        case UNAuthorizationStatusEphemeral:authorization=@"短期授权";break;
    }
    return [NSString stringWithFormat:@"通知权限：%@\n横幅：%@ · 声音：%@ · 角标：%@\nAPNs 环境：%@\n系统远程注册：%@\n\n本地测试只验证提醒权限，不证明私信远程推送已恢复。远程送达还需要抖音服务器接受当前签名身份。",authorization,
        [state[@"alert"] integerValue]==UNNotificationSettingEnabled?@"开":@"关",
        [state[@"sound"] integerValue]==UNNotificationSettingEnabled?@"开":@"关",
        [state[@"badge"] integerValue]==UNNotificationSettingEnabled?@"开":@"关",DARPushEnvironment(environment),
        [state[@"registered"] boolValue]?@"已注册（不等于已送达）":@"未注册"];
}
void DARRepairNotificationAccess(id<DARNotificationService> service,id environment,void (^completion)(NSString *)) {
    [service readState:^(NSDictionary *state){DARNotificationMain(^{
        NSInteger status=[state[@"authorization"] integerValue];
        void (^finishPermission)(BOOL,NSError *)=^(BOOL granted,NSError *error){DARNotificationMain(^{
            if(error){completion([@"通知授权失败：" stringByAppendingString:DARNotificationError(error)]);return;}
            if(!granted){completion(@"通知权限未开启。请点“系统通知设置”允许通知、横幅和声音，再回来重试。");return;}
            if(!DARPushEnvironmentValid(environment)) {
                completion(@"通知权限已允许，但签名缺少有效的 aps-environment。插件不能补写签名授权；需要在签名工具中使用支持推送的有效配置重新签名。");return;
            }
            [service registerRemote];
            completion(@"已发起注册重试，并尝试通过宿主推送服务按需绑定。等待数秒后点“刷新状态”查看；这一步尚不能确认远程私信已送达。");
        });};
        if(status==UNAuthorizationStatusNotDetermined || status==UNAuthorizationStatusProvisional)[service requestPermission:finishPermission];
        else finishPermission(DARNotificationAllowed(status),nil);
    });}];
}
void DARTestNotificationAccess(id<DARNotificationService> service,void (^completion)(NSString *)) {
    [service readState:^(NSDictionary *state){DARNotificationMain(^{
        if(!DARNotificationAllowed([state[@"authorization"] integerValue])) {
            completion(@"请先开启通知权限，再测试本地提醒。");return;
        }
        [service scheduleLocalTest:^(NSError *error){DARNotificationMain(^{
            completion(error?[@"本地测试创建失败：" stringByAppendingString:DARNotificationError(error)]:@"已安排 5 秒后的本地提醒，请立即回到手机桌面。收到它只表示本地通知正常，不表示私信推送已恢复。");
        });}];
    });}];
}
@interface DARSystemNotificationService : NSObject <DARNotificationService>
@end
@implementation DARSystemNotificationService
- (void)readState:(void (^)(NSDictionary *))completion {
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){
        DARNotificationMain(^{completion(@{@"authorization":@(settings.authorizationStatus),@"alert":@(settings.alertSetting),@"sound":@(settings.soundSetting),@"badge":@(settings.badgeSetting),@"registered":@(UIApplication.sharedApplication.isRegisteredForRemoteNotifications)});});
    }];
}
- (void)requestPermission:(void (^)(BOOL,NSError *))completion {
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionSound|UNAuthorizationOptionBadge completionHandler:completion];
}
- (void)registerRemote {
    if(!DARRetryHostPushBinding())[UIApplication.sharedApplication registerForRemoteNotifications];
}
- (void)scheduleLocalTest:(void (^)(NSError *))completion {
    UNMutableNotificationContent *content=[UNMutableNotificationContent new];
    content.title=@"抖音增强 · 本地通知测试";content.body=@"本地提醒正常。这不是私信，也不代表远程推送已恢复。";content.sound=UNNotificationSound.defaultSound;
    UNNotificationRequest *request=[UNNotificationRequest requestWithIdentifier:@"DAR.local.notification-test" content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:5 repeats:NO]];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:completion];
}
@end
@interface DARNotificationController : UITableViewController
@property(nonatomic,strong) id<DARNotificationService> service;
@property(nonatomic,strong) id environment;
@property(nonatomic,copy) NSString *report;
@property(nonatomic,copy) NSString *result;
@end
@implementation DARNotificationController
- (instancetype)init {return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"消息通知修复";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=50;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.service=[DARSystemNotificationService new];
    (void)DARInstallPushBindingObservers();
    NSBundle *bundle=NSBundle.mainBundle;NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:bundle.executablePath error:NULL];
    NSData *data=[attributes[NSFileSize] unsignedLongLongValue]<=16*1024*1024?[NSData dataWithContentsOfFile:bundle.executablePath]:nil;
    self.environment=DARDiagnosticEntitlements(data)[@"aps-environment"];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(didBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self refresh];
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)didBecomeActive:(__unused NSNotification *)notice {[self refresh];}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)refresh {
    __weak typeof(self) weak=self;
    [self.service readState:^(NSDictionary *state){DARNotificationMain(^{
        typeof(self) strong=weak;if(!strong)return;
        strong.report=[NSString stringWithFormat:@"%@\n\n%@",DARNotificationReport(state,strong.environment),DARPushBindingReport()];[strong.tableView reloadData];
    });}];
}
- (void)showResult:(NSString *)result {self.result=result;[self refresh];}
- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView{return 2;}
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?1:5;}
- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return section==0?@"当前状态":@"修复与检查";}
- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section{return section==1?self.result:nil;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"notification"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"notification"];
    cell.textLabel.numberOfLines=0;
    cell.textLabel.text=path.section==0?(self.report?:@"正在读取通知状态…"):@[@"开启权限并重新注册",@"刷新状态",@"5 秒后测试本地通知",@"系统通知设置",@"复制通知状态"][path.row];
    cell.selectionStyle=path.section==0?UITableViewCellSelectionStyleNone:UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor=path.section==0?UIColor.labelColor:UIColor.systemBlueColor;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];if(path.section!=1)return;
    __weak typeof(self) weak=self;
    switch(path.row) {
        case 0:{DARRepairNotificationAccess(self.service,self.environment,^(NSString *result){[weak showResult:result];});break;}
        case 1:[self refresh];break;
        case 2:{DARTestNotificationAccess(self.service,^(NSString *result){[weak showResult:result];});break;}
        case 3:{
            NSString *url=UIApplicationOpenSettingsURLString;
            if(@available(iOS 15.4,*))url=UIApplicationOpenNotificationSettingsURLString;
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];break;
        }
        case 4:UIPasteboard.generalPasteboard.string=[NSString stringWithFormat:@"%@\n%@",self.report?:@"",self.result?:@""];DARToast(@"已复制通知状态");break;
    }
}
@end
void DAROpenNotificationRepair(UIViewController *presenter) {
    if(!presenter)presenter=DARTopController();if(!presenter)return;
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:[DARNotificationController new]];
    navigation.modalPresentationStyle=UIModalPresentationPageSheet;[presenter presentViewController:navigation animated:YES completion:nil];
}
