#import "DARPushBinding.h"
extern void DARFeatureAssert(BOOL,NSString *);
static NSInteger RegisteredOriginalCalls,FailedOriginalCalls,UploadStartOriginalCalls,UploadResultOriginalCalls;
static id ObservedApplication,ObservedToken,ObservedError,ObservedStartPayload,ObservedResultPayload;
static NSMutableArray *ServiceCalls;
@interface BDUGPushDelegateInjection : NSObject
- (void)application:(id)application didRegisterForRemoteNotificationsWithDeviceToken:(id)token;
- (void)application:(id)application didFailToRegisterForRemoteNotificationsWithError:(id)error;
@end
@implementation BDUGPushDelegateInjection
- (void)application:(id)application didRegisterForRemoteNotificationsWithDeviceToken:(id)token {RegisteredOriginalCalls++;ObservedApplication=application;ObservedToken=token;}
- (void)application:(id)application didFailToRegisterForRemoteNotificationsWithError:(id)error {FailedOriginalCalls++;ObservedApplication=application;ObservedError=error;}
@end
@interface AWEPushModule : NSObject
- (void)bdug_pushDeviceTokenUploadStart:(id)payload;
- (void)bdug_pushDeviceTokenUploadResult:(id)payload;
@end
@implementation AWEPushModule
- (void)bdug_pushDeviceTokenUploadStart:(id)payload {UploadStartOriginalCalls++;ObservedStartPayload=payload;}
- (void)bdug_pushDeviceTokenUploadResult:(id)payload {UploadResultOriginalCalls++;ObservedResultPayload=payload;}
@end
@interface BDUGPushService : NSObject
+ (void)requestDeviceToken;
+ (void)uploadDeviceTokenIfNeeded;
@end
@implementation BDUGPushService
+ (void)requestDeviceToken {[ServiceCalls addObject:@"request"];}
+ (void)uploadDeviceTokenIfNeeded {[ServiceCalls addObject:@"upload"];}
@end
void DARRunPushBindingTests(void) {
    DARFeatureAssert(DARInstallPushBindingObservers() && DARInstallPushBindingObservers(),@"push observers install idempotently using the host ABI");
    BDUGPushDelegateInjection *injection=[BDUGPushDelegateInjection new];AWEPushModule *module=[AWEPushModule new];
    id application=[NSObject new];NSData *token=[@"PRIVATE-DEVICE-TOKEN" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error=[NSError errorWithDomain:@"System.Test" code:3000 userInfo:@{NSLocalizedDescriptionKey:@"PRIVATE-ERROR-PHONE"}];
    NSDictionary *payload=@{@"token":@"PRIVATE-TOKEN",@"uid":@"PRIVATE-UID",@"success":@YES};
    [injection application:application didRegisterForRemoteNotificationsWithDeviceToken:token];
    DARFeatureAssert(RegisteredOriginalCalls==1 && ObservedApplication==application && ObservedToken==token,@"registration observer forwards the original application and token exactly once");
    [injection application:application didFailToRegisterForRemoteNotificationsWithError:error];
    DARFeatureAssert(FailedOriginalCalls==1 && ObservedError==error,@"registration failure preserves the native error object");
    [module bdug_pushDeviceTokenUploadStart:payload];[module bdug_pushDeviceTokenUploadResult:payload];
    DARFeatureAssert(UploadStartOriginalCalls==1 && UploadResultOriginalCalls==1 && ObservedStartPayload==payload && ObservedResultPayload==payload,@"upload observers preserve payloads and invoke original methods exactly once");
    NSString *report=DARPushBindingReport();
    DARFeatureAssert([report containsString:@"4/4"] && [report containsString:@"3000"] && [report containsString:@"结果回调：1"],@"binding report distinguishes callback stages and numeric registration failure");
    DARFeatureAssert(![report containsString:@"PRIVATE"] && ![report containsString:@"success"] && [report containsString:@"不等于服务端接受"],@"report excludes tokens, account data and callback payload fields and does not imply delivery");
    ServiceCalls=[NSMutableArray new];
    DARFeatureAssert(DARRetryHostPushBinding() && [ServiceCalls isEqual:@[@"request",@"upload"]],@"explicit retry requests a native token then invokes host upload-if-needed, without changing rate limits");
    DARFeatureAssert([DARPushBindingReport() containsString:@"等待回调"],@"requesting a retry is recorded as pending rather than successful delivery");
}
