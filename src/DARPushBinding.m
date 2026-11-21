#import "DARPushBinding.h"
#import "DARRuntime.h"
#import <objc/message.h>
#include <string.h>

static IMP DARPushHostRegisteredOriginal,DARPushRegisteredOriginal,DARPushFailedOriginal,DARPushUploadStartOriginal,DARPushUploadResultOriginal;
static NSUInteger DARPushHostRegisteredCount,DARPushRegisteredCount,DARPushFailureCount,DARPushUploadStartCount,DARPushUploadResultCount;
static NSInteger DARPushFailureCode;
static BOOL DARPushHasFailureCode;
static NSString *DARPushLastStage;
static NSObject *DARPushLock(void) {static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[NSObject new];});return lock;}
static void DARPushRegistered(id self,SEL command,id application,id token) {
    @synchronized(DARPushLock()){DARPushRegisteredCount++;DARPushLastStage=@"宿主收到系统注册成功回调";}
    ((void(*)(id,SEL,id,id))DARPushRegisteredOriginal)(self,command,application,token);
}
static void DARPushHostRegistered(id self,SEL command,id application,id token) {
    @synchronized(DARPushLock()){DARPushHostRegisteredCount++;DARPushLastStage=@"宿主 AppDelegate 收到系统注册成功回调";}
    ((void(*)(id,SEL,id,id))DARPushHostRegisteredOriginal)(self,command,application,token);
}
static void DARPushFailed(id self,SEL command,id application,id error) {
    @synchronized(DARPushLock()) {
        DARPushFailureCount++;DARPushHasFailureCode=[error isKindOfClass:NSError.class];
        DARPushFailureCode=DARPushHasFailureCode?[(NSError *)error code]:0;DARPushLastStage=@"宿主收到系统注册失败回调";
    }
    ((void(*)(id,SEL,id,id))DARPushFailedOriginal)(self,command,application,error);
}
static void DARPushUploadStart(id self,SEL command,id payload) {
    @synchronized(DARPushLock()){DARPushUploadStartCount++;DARPushLastStage=@"宿主开始上传推送绑定";}
    ((void(*)(id,SEL,id))DARPushUploadStartOriginal)(self,command,payload);
}
static void DARPushUploadResult(id self,SEL command,id payload) {
    // The callback payload may contain a token or account information. Never inspect it.
    @synchronized(DARPushLock()){DARPushUploadResultCount++;DARPushLastStage=@"宿主上传结果回调已到达（不代表投递成功）";}
    ((void(*)(id,SEL,id))DARPushUploadResultOriginal)(self,command,payload);
}
static BOOL DARPushHostCompatible(void) {
#ifdef DAR_TESTING
    return YES;
#else
    NSBundle *bundle=NSBundle.mainBundle;
    return [bundle.bundleIdentifier isEqual:@"com.ss.iphone.ugc.Aweme"] &&
        [[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"41.2.0"] &&
        [[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"412021"];
#endif
}
BOOL DARInstallPushBindingObservers(void) {
    if(!DARPushHostCompatible())return NO;
    Class injection=NSClassFromString(@"BDUGPushDelegateInjection"),module=NSClassFromString(@"AWEPushModule");
    BOOL a=DARHook(injection,@"application:didRegisterForRemoteNotificationsWithDeviceToken:",(IMP)DARPushRegistered,&DARPushRegisteredOriginal,"v",4);
    BOOL b=DARHook(injection,@"application:didFailToRegisterForRemoteNotificationsWithError:",(IMP)DARPushFailed,&DARPushFailedOriginal,"v",4);
    BOOL c=DARHook(module,@"bdug_pushDeviceTokenUploadStart:",(IMP)DARPushUploadStart,&DARPushUploadStartOriginal,"v",3);
    BOOL d=DARHook(module,@"bdug_pushDeviceTokenUploadResult:",(IMP)DARPushUploadResult,&DARPushUploadResultOriginal,"v",3);
    BOOL e=DARHook(NSClassFromString(@"HTSBootAppDelegate"),@"application:didRegisterForRemoteNotificationsWithDeviceToken:",(IMP)DARPushHostRegistered,&DARPushHostRegisteredOriginal,"v",4);
    return a&&b&&c&&d&&e;
}
static BOOL DARPushCanCall(id receiver,NSString *name) {
    Method method=class_getInstanceMethod(object_getClass(receiver),NSSelectorFromString(name));
    if(!method || method_getNumberOfArguments(method)!=2)return NO;
    char result[32];method_getReturnType(method,result,sizeof(result));return !strcmp(result,"v");
}
BOOL DARRetryHostPushBinding(void) {
    if(!NSThread.isMainThread || !DARPushHostCompatible())return NO;
    Class service=NSClassFromString(@"BDUGPushService");
    if(!DARPushCanCall(service,@"requestDeviceToken") || !DARPushCanCall(service,@"uploadDeviceTokenIfNeeded"))return NO;
    (void)DARInstallPushBindingObservers();
    @synchronized(DARPushLock()){DARPushLastStage=@"已请求宿主重试注册及按需绑定，等待回调";}
    // Use the host's normal service. Retain its deduplication, disable switch and rate limits.
    ((void(*)(id,SEL))objc_msgSend)(service,NSSelectorFromString(@"requestDeviceToken"));
    ((void(*)(id,SEL))objc_msgSend)(service,NSSelectorFromString(@"uploadDeviceTokenIfNeeded"));
    return YES;
}
NSString *DARPushBindingReport(void) {
    NSUInteger observers=(DARPushRegisteredOriginal!=NULL)+(DARPushFailedOriginal!=NULL)+(DARPushUploadStartOriginal!=NULL)+(DARPushUploadResultOriginal!=NULL)+(DARPushHostRegisteredOriginal!=NULL);
    @synchronized(DARPushLock()) {
        return [NSString stringWithFormat:@"宿主绑定观察点：%lu/5\n本次进程 SDK 注册成功回调：%lu · 失败：%lu%@\n宿主 AppDelegate 注册成功回调：%lu\n绑定上传开始：%lu · 结果回调：%lu\n最近阶段：%@\n计数从本次加载开始；0 不代表此前从未绑定或注册失败。两条成功路径可能属于同一次注册，不能相加作为注册次数。结果回调不等于服务端接受或推送送达。",(unsigned long)observers,(unsigned long)DARPushRegisteredCount,(unsigned long)DARPushFailureCount,
            DARPushHasFailureCode?[NSString stringWithFormat:@"（系统错误码 %ld）",(long)DARPushFailureCode]:@"",(unsigned long)DARPushHostRegisteredCount,(unsigned long)DARPushUploadStartCount,(unsigned long)DARPushUploadResultCount,DARPushLastStage?:@"尚未观察到宿主回调"];
    }
}
