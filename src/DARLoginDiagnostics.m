#import "DARLoginDiagnostics.h"
#import "DARFeatures.h"
#import "DARRuntime.h"
#import <mach-o/loader.h>
#import <libkern/OSByteOrder.h>
#include <string.h>

static BOOL DARRead32(NSData *data,NSUInteger offset,BOOL big,uint32_t *value) {
    if(offset>data.length || data.length-offset<4)return NO;
    uint32_t raw;memcpy(&raw,(const uint8_t *)data.bytes+offset,4);
    *value=big?OSSwapBigToHostInt32(raw):OSSwapLittleToHostInt32(raw);return YES;
}
NSDictionary *DARDiagnosticEntitlements(NSData *data) {
    uint32_t magic,count,commands;
    if(!DARRead32(data,0,NO,&magic) || magic!=MH_MAGIC_64 ||
       !DARRead32(data,16,NO,&count) || !DARRead32(data,20,NO,&commands) ||
       data.length<32 || commands>data.length-32 || count>commands/8)return nil;
    NSUInteger offset=32,end=32+commands;
    for(uint32_t i=0;i<count;i++) {
        uint32_t command,size;
        if(!DARRead32(data,offset,NO,&command) || !DARRead32(data,offset+4,NO,&size) || size<8 || size>end-offset)return nil;
        if(command==LC_CODE_SIGNATURE) {
            uint32_t start,length,superMagic,total,slots;
            if(size<16 || !DARRead32(data,offset+8,NO,&start) || !DARRead32(data,offset+12,NO,&length) ||
               start>data.length || length>data.length-start || length<12)return nil;
            NSData *signature=[data subdataWithRange:NSMakeRange(start,length)];
            if(!DARRead32(signature,0,YES,&superMagic) || superMagic!=0xfade0cc0 ||
               !DARRead32(signature,4,YES,&total) || total>length || total<12 ||
               !DARRead32(signature,8,YES,&slots) || slots>(total-12)/8)return nil;
            for(uint32_t j=0;j<slots;j++) {
                uint32_t type,blob,blobMagic,blobLength;
                if(!DARRead32(signature,12+j*8,YES,&type) || !DARRead32(signature,16+j*8,YES,&blob))return nil;
                if(type!=5)continue;
                if(blob>total || total-blob<8 || !DARRead32(signature,blob,YES,&blobMagic) || blobMagic!=0xfade7171 ||
                   !DARRead32(signature,blob+4,YES,&blobLength) || blobLength<8 || blobLength>total-blob)return nil;
                id values=[NSPropertyListSerialization propertyListWithData:[signature subdataWithRange:NSMakeRange(blob+8,blobLength-8)] options:NSPropertyListImmutable format:NULL error:NULL];
                return [values isKindOfClass:NSDictionary.class]?values:nil;
            }
            return nil;
        }
        offset+=size;
    }
    return nil;
}
static NSMutableArray<NSString *> *DARLoginEvents(void) {
    static NSMutableArray *events;static dispatch_once_t once;
    dispatch_once(&once,^{events=[NSMutableArray new];});return events;
}
static NSString *DARSafeDiagnosticWord(id value) {
    if(![value isKindOfClass:NSString.class] || ![value length])return @"未提供";
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    if([value length]>100 || [value rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound)return @"不可显示";
    return value;
}
static __weak UIButton *DARLoginButton;
void DAROpenLoginDiagnostics(UIViewController *presenter) {
    if(!presenter)presenter=DARTopController();if(!presenter)return;
    NSString *report=DARLoginDiagnosticReport();
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"登录诊断" message:report preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制诊断" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){UIPasteboard.generalPasteboard.string=report;DARToast(@"已复制登录诊断");}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"收起入口" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[DARLoginButton removeFromSuperview];}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
static void DARShowLoginButton(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        UIWindow *window=DARTopController().view.window;if(!window)return;
        UIButton *button=DARLoginButton;
        if(button.superview!=window) {
            [button removeFromSuperview];button=[UIButton buttonWithType:UIButtonTypeSystem];
            [button setTitle:@"登录诊断" forState:UIControlStateNormal];button.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];button.backgroundColor=UIColor.systemBlueColor;
            button.layer.cornerRadius=18;button.accessibilityIdentifier=@"DAR.login.diagnostics";button.translatesAutoresizingMaskIntoConstraints=NO;
            [button addAction:[UIAction actionWithHandler:^(__unused UIAction *action){DAROpenLoginDiagnostics(nil);}] forControlEvents:UIControlEventTouchUpInside];
            [window addSubview:button];DARLoginButton=button;
            [NSLayoutConstraint activateConstraints:@[[button.trailingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-12],
                [button.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-12],
                [button.widthAnchor constraintEqualToConstant:104],[button.heightAnchor constraintEqualToConstant:36]]];
        }
        [window bringSubviewToFront:button];
    });
}
static void DARRecordLoginError(NSString *route,id error) {
    NSString *details=@"未提供 NSError，错误码未知";
    if([error isKindOfClass:NSError.class])details=[NSString stringWithFormat:@"domain=%@ code=%ld",DARSafeDiagnosticWord([(NSError *)error domain]),(long)[(NSError *)error code]];
    NSDateFormatter *format=[NSDateFormatter new];format.dateFormat=@"HH:mm:ss";
    NSString *event=[NSString stringWithFormat:@"%@ %@ %@",[format stringFromDate:NSDate.date],route,details];
    NSMutableArray *events=DARLoginEvents();@synchronized(events) {
        [events addObject:event];while(events.count>16)[events removeObjectAtIndex:0];
    }
    DARShowLoginButton();
}
NSString *DARLoginDiagnosticReport(void) {
    NSBundle *bundle=NSBundle.mainBundle;
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:bundle.executablePath error:NULL];
    NSData *data=[attributes[NSFileSize] unsignedLongLongValue]<=16*1024*1024?[NSData dataWithContentsOfFile:bundle.executablePath]:nil;
    NSDictionary *entitlements=DARDiagnosticEntitlements(data);
    id environment=entitlements[@"com.apple.developer.devicecheck.appattest-environment"];
    NSString *attest=[environment isKindOfClass:NSString.class]?DARSafeDiagnosticWord(environment):(environment?@"类型异常（非字符串）":@"未声明");
    NSMutableArray *events=DARLoginEvents();NSString *recent;
    @synchronized(events){recent=events.count?[events componentsJoinedByString:@"\n"]:@"尚未捕获登录错误";}
    return [NSString stringWithFormat:@"v0.2.5 只读诊断\niOS %@\n抖音 %@ (%@)\nBundle %@\nTeam %@\nApp ID %@\nApp Attest %@\n签名字段：%@\n\n%@\n\n仅记录错误域、错误码和处理路径，重启清空。不读取错误正文、手机号、验证码或令牌。",
        UIDevice.currentDevice.systemVersion,[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"未知",
        [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"未知",bundle.bundleIdentifier?:@"未知",
        DARSafeDiagnosticWord(entitlements[@"com.apple.developer.team-identifier"]),DARSafeDiagnosticWord(entitlements[@"application-identifier"]),
        attest,entitlements?@"已读取（非密码学验证）":@"无法读取 XML 权限",recent];
}
static IMP DAROriginalLoginError,DAROriginal1049,DAROriginalForceUpdate;
static void DARHandleLoginError(id self,SEL command,id error,id parameters,id response,id completion) {
    if(error)DARRecordLoginError(@"账户错误处理",error);
    ((void(*)(id,SEL,id,id,id,id))DAROriginalLoginError)(self,command,error,parameters,response,completion);
}
static void DARHandle1049(id self,SEL command,id error,id fullData,id completion) {
    DARRecordLoginError(@"进入1049处理路径",error);
    ((void(*)(id,SEL,id,id,id))DAROriginal1049)(self,command,error,fullData,completion);
}
static void DARHandleForceUpdate(id self,SEL command,id decision,id completion) {
    DARRecordLoginError(@"进入身份验证强制更新路径",nil);
    ((void(*)(id,SEL,id,id))DAROriginalForceUpdate)(self,command,decision,completion);
}
BOOL DARInstallLoginDiagnostics(void) {
    Class error=NSClassFromString(@"IESAccountErrorHandler");
    BOOL a=DARHook(error,@"handleError:extraParams:response:completion:",(IMP)DARHandleLoginError,&DAROriginalLoginError,"v",6);
    BOOL b=DARHook(error,@"process1049Error:fullData:completion:",(IMP)DARHandle1049,&DAROriginal1049,"v",5);
    BOOL c=DARHook(object_getClass(NSClassFromString(@"IESAccountIdentityVerificationDecisionDispatcher")),@"showForceUpdateDecision:completion:",(IMP)DARHandleForceUpdate,&DAROriginalForceUpdate,"v",4);
    return a&&b&&c;
}
