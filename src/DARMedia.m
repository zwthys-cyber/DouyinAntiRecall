#import "DARFeatures.h"
#import "DARAudio.h"
#import "DAROptions.h"
#import "DARRuntime.h"
#import <Photos/Photos.h>
#import <objc/message.h>
static NSURL *DARHTTPURL(id value) {
    NSURL *url=[value isKindOfClass:NSURL.class]?value:([value isKindOfClass:NSString.class]?[NSURL URLWithString:value]:nil);
    return [@[@"http",@"https"] containsObject:url.scheme.lowercaseString]?url:nil;
}
static NSURL *DARFirstURL(id values) {
    if([values isKindOfClass:NSArray.class]) {
        for(id value in values){NSURL *url=DARHTTPURL(value);if(url)return url;}
        return nil;
    }
    NSURL *url=DARHTTPURL(values); if(url)return url;
    id list=DARGet(values,@"originURLList");
    return [list isKindOfClass:NSArray.class]?DARFirstURL(list):nil;
}
NSURL *DAROriginalImageURL(id imageModel) {
    NSURL *url=DARFirstURL(DARGet(imageModel,@"watermarkFreeUrlList"));
    return url?:DARFirstURL(DARGet(imageModel,@"urlList"));
}
@interface DARImageSaveTask : NSObject
@property(nonatomic,strong) NSArray<NSURL *> *urls;
@property(nonatomic) NSUInteger index;
@property(nonatomic) NSUInteger successes;
- (void)next;
@end
@implementation DARImageSaveTask
- (void)next {
    if(self.index>=self.urls.count){DARToast([NSString stringWithFormat:@"已保存 %lu/%lu 张图片",(unsigned long)self.successes,(unsigned long)self.urls.count]);return;}
    NSURL *url=self.urls[self.index++]; NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];request.timeoutInterval=45;
    [[NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *file,NSURLResponse *response,NSError *error){
        NSNumber *size;[file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        NSData *data=(!error && [(NSHTTPURLResponse *)response statusCode]==200 && size.unsignedLongLongValue<=50*1024*1024)?[NSData dataWithContentsOfURL:file]:nil;
        if(!data.length || ![UIImage imageWithData:data]){dispatch_async(dispatch_get_main_queue(),^{[self next];});return;}
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *creation=[PHAssetCreationRequest creationRequestForAsset];
            [creation addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];
        } completionHandler:^(BOOL success,__unused NSError *saveError){
            dispatch_async(dispatch_get_main_queue(),^{if(success)self.successes++;[self next];});
        }];
    }] resume];
}
@end
void DARSaveImages(id model,BOOL all) {
    if(!DAROptionEnabled(DAROptionImages)){DARToast(@"请先开启无水印保存图片");return;}
    id images=DARGet(model,@"albumImages"); if(![images isKindOfClass:NSArray.class] || ![images count]){DARToast(@"当前内容没有可保存的图片");return;}
    NSArray *selected=images;
    if(!all) {long long index=DARNumber(model,@"currentImageIndex"); if(index<1 || index>(long long)[images count])index=1;selected=@[images[(NSUInteger)index-1]];}
    NSMutableArray *urls=[NSMutableArray new]; for(id image in selected){NSURL *url=DAROriginalImageURL(image);if(url)[urls addObject:url];}
    if(!urls.count){DARToast(@"没有可用的原图地址");return;}
    if(![NSBundle.mainBundle objectForInfoDictionaryKey:@"NSPhotoLibraryAddUsageDescription"]){DARToast(@"当前安装包缺少保存相册的权限说明");return;}
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status){
        dispatch_async(dispatch_get_main_queue(),^{
            if(status!=PHAuthorizationStatusAuthorized && status!=PHAuthorizationStatusLimited){DARToast(@"请在系统设置中允许添加照片");return;}
            DARToast(@"正在保存原图…");DARImageSaveTask *task=[DARImageSaveTask new];task.urls=urls;[task next];
        });
    }];
}
void DARSaveAudioFromModel(id model) {
    if(!DAROptionEnabled(DAROptionAudioLibrary)){DARToast(@"请先开启视频音频入库");return;}
    NSURL *url=DARFirstURL(DARGet(DARGet(model,@"music"),@"playURL"));
    if(!url)url=DARFirstURL(DARGet(DARGet(model,@"video"),@"playURL"));
    if(!url)url=DARFirstURL(DARGet(DARGet(model,@"video"),@"downloadURL"));
    if(!url){DARToast(@"当前视频没有可用的声音地址");return;}
    id description=DARGet(model,@"descriptionString");
    NSString *name=[description isKindOfClass:NSString.class] && [description length]?description:@"视频音频";
    DARToast(@"正在将音频入库…");
    [DARAudioLibrary.shared download:url name:name completion:^(NSError *error){DARToast(error?error.localizedDescription:@"音频已入库，可在音频库中试听或选择发送");}];
}
static IMP DAROriginalModernMenu,DAROriginalClassicMenu;
static char DARMenuGroup;
static void DARAfterMenuDismiss(void(^action)(void)) {
    id manager=DARGet(NSClassFromString(@"AWELongPressPanelManager"),@"shareInstance");
    SEL selector=NSSelectorFromString(@"dismissWithAnimation:completion:");
    if([manager respondsToSelector:selector])((void(*)(id,SEL,BOOL,id))objc_msgSend)(manager,selector,YES,action);
    else action();
}
static id DARMenuItem(id model,NSString *title,NSString *icon,NSUInteger identifier,void(^action)(void)) {
    id item=[[NSClassFromString(@"AWELongPressPanelBaseViewModel") alloc] init];if(!item)return nil;
    DARPut(item,@"setAwemeModel:",model);DARPutNumber(item,@"setActionType:",identifier);
    DARPut(item,@"setDescribeString:",title);DARPut(item,@"setDuxIconName:",icon);
    DARPut(item,@"setAction:",^{DARAfterMenuDismiss(action);});return item;
}
NSArray *DARAugmentLongPressGroups(NSArray *groups,id model,BOOL modern) {
    if(![groups isKindOfClass:NSArray.class])return groups;
    NSMutableArray *original=[NSMutableArray new];for(id group in groups)if(!objc_getAssociatedObject(group,&DARMenuGroup))[original addObject:group];
    NSMutableArray *items=[NSMutableArray new];id item;
    if(DAROptionEnabled(DAROptionAudioLibrary)){
        item=DARMenuItem(model,@"音频入库",@"ic_star_outlined_20",61001,^{DARSaveAudioFromModel(model);});if(item)[items addObject:item];
        item=DARMenuItem(model,@"音频库",@"ic_phonearrowup_outlined_20",61002,^{DAROpenAudioLibrary(nil);});if(item)[items addObject:item];
    }
    id images=DARGet(model,@"albumImages");
    if(DAROptionEnabled(DAROptionImages) && [images isKindOfClass:NSArray.class] && [images count]){
        item=DARMenuItem(model,@"保存当前原图",@"ic_boxarrowdown_outlined",61003,^{DARSaveImages(model,NO);});if(item)[items addObject:item];
        if([images count]>1){item=DARMenuItem(model,@"保存整组原图",@"ic_boxarrowdown_outlined",61004,^{DARSaveImages(model,YES);});if(item)[items addObject:item];}
    }
    if(!items.count)return original;
    id group=[[NSClassFromString(@"AWELongPressPanelViewGroupModel") alloc] init];if(!group)return original;
    DARPutNumber(group,@"setGroupType:",modern?(items.count<=3?11:12):0);DARPutNumber(group,@"setIsModern:",modern);
    if(!DARPut(group,@"setGroupArr:",items))return original;
    objc_setAssociatedObject(group,&DARMenuGroup,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [original insertObject:group atIndex:0];return original;
}
static id DARModernMenu(id self,SEL selector){id array=((id(*)(id,SEL))DAROriginalModernMenu)(self,selector);return DARAugmentLongPressGroups(array,DARGet(self,@"awemeModel"),YES);}
static id DARClassicMenu(id self,SEL selector){id array=((id(*)(id,SEL))DAROriginalClassicMenu)(self,selector);return DARAugmentLongPressGroups(array,DARGet(self,@"awemeModel"),NO);}
BOOL DARInstallMenuHooks(void){
    BOOL a=DARHook(NSClassFromString(@"AWEModernLongPressPanelTableViewController"),@"dataArray",(IMP)DARModernMenu,&DAROriginalModernMenu,"@",2);
    BOOL b=DARHook(NSClassFromString(@"AWELongPressPanelTableViewController"),@"dataArray",(IMP)DARClassicMenu,&DAROriginalClassicMenu,"@",2);
    return a&&b;
}
