#import "DARNotifications.h"
extern void DARFeatureAssert(BOOL,NSString *);
@interface DARFakeNotificationService : NSObject <DARNotificationService>
@property(nonatomic) NSInteger authorization,requests,registrations,localTests;
@property(nonatomic) BOOL granted;
@property(nonatomic,strong) NSError *error;
@end
@implementation DARFakeNotificationService
- (void)readState:(void (^)(NSDictionary *))completion {completion(@{@"authorization":@(self.authorization)});}
- (void)requestPermission:(void (^)(BOOL,NSError *))completion {self.requests++;completion(self.granted,self.error);}
- (void)registerRemote {DARFeatureAssert(NSThread.isMainThread,@"APNs registration stays on the main thread");self.registrations++;}
- (void)scheduleLocalTest:(void (^)(NSError *))completion {self.localTests++;completion(self.error);}
@end
void DARRunNotificationTests(void) {
    DARFakeNotificationService *service=[DARFakeNotificationService new];service.granted=YES;
    __block NSInteger completions=0;__block NSString *message;
    void (^finish)(NSString *)=^(NSString *result){completions++;message=result;};
    DARRepairNotificationAccess(service,@"production",finish);
    DARFeatureAssert(service.requests==1 && service.registrations==1 && completions==1 && [message containsString:@"尚不能确认"],@"first-use permission grant requests APNs once without claiming delivery");
    service.authorization=UNAuthorizationStatusAuthorized;
    DARRepairNotificationAccess(service,@"development",finish);
    DARFeatureAssert(service.requests==1 && service.registrations==2 && completions==2,@"existing permission is preserved and development APNs registration can be retried");
    DARRepairNotificationAccess(service,nil,finish);
    DARRepairNotificationAccess(service,@[@"development",@"production"],finish);
    DARRepairNotificationAccess(service,@"invalid",finish);
    DARFeatureAssert(service.registrations==2 && completions==5 && [message containsString:@"签名"],@"missing, array and unsupported push entitlements do not trigger a misleading registration attempt");
    service.authorization=UNAuthorizationStatusDenied;
    DARRepairNotificationAccess(service,@"production",finish);
    DARFeatureAssert(service.registrations==2 && service.requests==1 && [message containsString:@"系统设置"],@"denied permission directs to Settings without repeated prompts");
    DARTestNotificationAccess(service,finish);
    DARFeatureAssert(service.localTests==0,@"local test is not scheduled without notification permission");
    service.authorization=UNAuthorizationStatusNotDetermined;service.granted=NO;
    DARRepairNotificationAccess(service,@"production",finish);
    DARFeatureAssert(service.registrations==2 && service.requests==2,@"declined permission never registers for remote notifications");
    service.error=[NSError errorWithDomain:@"UNErrorDomain" code:42 userInfo:@{NSLocalizedDescriptionKey:@"SECRET-TOKEN-PHONE"}];
    DARRepairNotificationAccess(service,@"production",finish);
    DARFeatureAssert([message containsString:@"42"] && ![message containsString:@"SECRET"] && service.registrations==2,@"permission failures expose only numeric codes and preserve errors without leaking descriptions");
    service.error=nil;service.authorization=UNAuthorizationStatusProvisional;service.granted=YES;
    DARRepairNotificationAccess(service,@"production",finish);
    DARFeatureAssert(service.requests==4 && service.registrations==3,@"provisional access requests full alert permission instead of silently retaining quiet delivery");
    DARTestNotificationAccess(service,finish);
    DARFeatureAssert(service.localTests==1 && [message containsString:@"不表示私信推送已恢复"],@"local notification test is explicit and does not claim remote push success");
    service.error=[NSError errorWithDomain:@"UNErrorDomain" code:43 userInfo:@{NSLocalizedDescriptionKey:@"SECRET"}];
    DARTestNotificationAccess(service,finish);
    DARFeatureAssert(service.localTests==2 && [message containsString:@"43"] && ![message containsString:@"SECRET"],@"local scheduling failures are shown without host data");
    NSString *report=DARNotificationReport(@{@"authorization":@(UNAuthorizationStatusAuthorized),@"registered":@YES,@"alert":@(UNNotificationSettingDisabled)},@[@"production"]);
    DARFeatureAssert([report containsString:@"类型异常"] && [report containsString:@"不等于已送达"] && [report containsString:@"横幅：关"],@"report distinguishes malformed signing, remote registration, alert controls and delivery");
    DARFeatureAssert([DARPushEnvironment(nil) isEqual:@"未声明"] && [DARPushEnvironment(@"unexpected") isEqual:@"值异常"],@"environment reporting rejects unknown values");
}
