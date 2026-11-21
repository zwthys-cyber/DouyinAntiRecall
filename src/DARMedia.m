#import "DARFeatures.h"
#import "DARImageSave.h"
#import "DARAudio.h"
#import "DAROptions.h"
#import "DARRuntime.h"
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>
static NSURL *DARHTTPURL(id value) {
    NSURL *url=[value isKindOfClass:NSURL.class]?value:([value isKindOfClass:NSString.class]?[NSURL URLWithString:value]:nil);
    return url.scheme.length && [@[@"http",@"https"] containsObject:url.scheme.lowercaseString]?url:nil;
}
static NSURL *DARFirstURL(id values) {
    if(!values)return nil;
    if([values isKindOfClass:NSArray.class]) {
        for(id value in values){NSURL *url=DARHTTPURL(value);if(url)return url;}
        return nil;
    }
    NSURL *url=DARHTTPURL(values); if(url)return url;
    id list=DARGet(values,@"originURLList");
    return [list isKindOfClass:NSArray.class]?DARFirstURL(list):nil;
}
static void DARCollectImageURLs(id values,NSMutableArray<NSURL *> *urls,NSUInteger depth) {
    if(!values || depth>4 || urls.count>=16)return;
    if([values isKindOfClass:NSArray.class]) {
        for(id value in values)DARCollectImageURLs(value,urls,depth+1);
    } else {
        if([values isKindOfClass:NSString.class] && [values hasPrefix:@"//"])values=[@"https:" stringByAppendingString:values];
        NSURL *url=DARHTTPURL(values);
        if(url.host.length){if(![urls containsObject:url])[urls addObject:url];}
        else if(!url)DARCollectImageURLs(DARGet(values,@"originURLList"),urls,depth+1);
    }
}
NSArray<NSURL *> *DAROriginalImageURLs(id imageModel) {
    NSMutableArray *urls=[NSMutableArray new];
    DARCollectImageURLs(DARGet(imageModel,@"watermarkFreeUrlList"),urls,0);
    DARCollectImageURLs(DARGet(imageModel,@"urlList"),urls,0);
    return urls;
}
NSURL *DAROriginalImageURL(id imageModel) { return DAROriginalImageURLs(imageModel).firstObject; }
static NSDictionary *DARPhotoExif(NSData *data) {
    if(!data.length)return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    if(!source)return nil;
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    CFRelease(source);
    id exif=properties[(__bridge NSString *)kCGImagePropertyExifDictionary];
    return [exif isKindOfClass:NSDictionary.class]?exif:nil;
}
static BOOL DARDateMatches(NSString *value,NSString *pattern) {
    if(![value isKindOfClass:NSString.class])return NO;
    NSRange match=[value rangeOfString:pattern options:NSRegularExpressionSearch];
    return match.location==0 && match.length==value.length;
}
static NSDate *DARDateFromExif(NSDictionary *exif) {
    NSString *original=exif[(__bridge NSString *)kCGImagePropertyExifDateTimeOriginal];
    if(!DARDateMatches(original,@"^[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$") || [original hasPrefix:@"0000"])return nil;
    // EXIF without an offset records local wall-clock time. Do not guess a
    // location or substitute publication, edit or download timestamps.
    NSTimeZone *zone=NSTimeZone.localTimeZone;
    NSString *offset=exif[(__bridge NSString *)kCGImagePropertyExifOffsetTimeOriginal];
    if(offset) {
        if(!DARDateMatches(offset,@"^[+-][0-9]{2}:[0-9]{2}$"))return nil;
        NSInteger hours=[[offset substringWithRange:NSMakeRange(1,2)] integerValue];
        NSInteger minutes=[[offset substringFromIndex:4] integerValue];
        if(hours>14 || minutes>59 || (hours==14 && minutes))return nil;
        NSInteger seconds=(hours*60+minutes)*60*([offset hasPrefix:@"-"]?-1:1);
        zone=[NSTimeZone timeZoneForSecondsFromGMT:seconds];
    }
    NSDateFormatter *formatter=[NSDateFormatter new];
    formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    formatter.timeZone=zone;formatter.dateFormat=@"yyyy:MM:dd HH:mm:ss";formatter.lenient=NO;
    NSDate *date=[formatter dateFromString:original];
    if(!date || ![[formatter stringFromDate:date] isEqual:original])return nil;
    NSString *subsecond=exif[(__bridge NSString *)kCGImagePropertyExifSubsecTimeOriginal];
    if(DARDateMatches(subsecond,@"^[0-9]{1,9}$"))date=[date dateByAddingTimeInterval:[[@"0." stringByAppendingString:subsecond] doubleValue]];
    return date;
}
static NSDictionary *DARExifFromISODate(NSString *value) {
    if(![value isKindOfClass:NSString.class])return nil;
    if(DARDateMatches(value,@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))value=[value stringByAppendingString:@"T00:00:00"];
    NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"^([0-9]{4})-([0-9]{2})-([0-9]{2})[T ]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:[.]([0-9]{1,9}))?(Z|[+-][0-9]{2}:?[0-9]{2})?$" options:0 error:NULL];
    NSTextCheckingResult *match=[regex firstMatchInString:value options:0 range:NSMakeRange(0,value.length)];
    if(!match || match.range.length!=value.length)return nil;
    NSMutableArray *parts=[NSMutableArray new];for(NSUInteger i=1;i<=6;i++)[parts addObject:[value substringWithRange:[match rangeAtIndex:i]]];
    NSMutableDictionary *fields=[NSMutableDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@:%@:%@ %@:%@:%@",parts[0],parts[1],parts[2],parts[3],parts[4],parts[5]] forKey:(__bridge NSString *)kCGImagePropertyExifDateTimeOriginal];
    NSRange sub=[match rangeAtIndex:7];if(sub.location!=NSNotFound)fields[(__bridge NSString *)kCGImagePropertyExifSubsecTimeOriginal]=[value substringWithRange:sub];
    NSRange zone=[match rangeAtIndex:8];
    if(zone.location!=NSNotFound) {
        NSString *offset=[value substringWithRange:zone];
        if([offset isEqual:@"Z"])offset=@"+00:00";
        else if(offset.length==5)offset=[NSString stringWithFormat:@"%@:%@",[offset substringToIndex:3],[offset substringFromIndex:3]];
        fields[(__bridge NSString *)kCGImagePropertyExifOffsetTimeOriginal]=offset;
    }
    return DARDateFromExif(fields)?fields:nil;
}
static NSDictionary *DARCaptureFields(NSData *data) {
    NSDictionary *exif=DARPhotoExif(data);if(DARDateFromExif(exif))return exif;
    if(!data.length)return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);if(!source)return nil;
    CGImageMetadataRef metadata=CGImageSourceCopyMetadataAtIndex(source,0,NULL);
    NSDictionary *fields;
    if(metadata) {
        for(NSString *path in @[@"exif:DateTimeOriginal",@"photoshop:DateCreated"]) {
            NSString *value=CFBridgingRelease(CGImageMetadataCopyStringValueWithPath(metadata,NULL,(__bridge CFStringRef)path));
            fields=DARExifFromISODate(value);if(fields)break;
        }
        CFRelease(metadata);
    }
    if(!fields) {
        NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
        id iptc=properties[(__bridge NSString *)kCGImagePropertyIPTCDictionary];
        if([iptc isKindOfClass:NSDictionary.class]) {
            id day=iptc[(__bridge NSString *)kCGImagePropertyIPTCDateCreated];
            id time=iptc[(__bridge NSString *)kCGImagePropertyIPTCTimeCreated];
            if([day isKindOfClass:NSString.class]) {
                day=[[day stringByReplacingOccurrencesOfString:@"-" withString:@""] stringByReplacingOccurrencesOfString:@":" withString:@""];
                NSString *clock=!time?@"000000":([time isKindOfClass:NSString.class]?[time stringByReplacingOccurrencesOfString:@":" withString:@""]:nil);
                if(DARDateMatches(day,@"^[0-9]{8}$") && DARDateMatches(clock,@"^[0-9]{6}([+-][0-9]{4})?$")) {
                    NSString *iso=[NSString stringWithFormat:@"%@-%@-%@T%@:%@:%@%@",[day substringToIndex:4],[day substringWithRange:NSMakeRange(4,2)],[day substringFromIndex:6],[clock substringToIndex:2],[clock substringWithRange:NSMakeRange(2,2)],[clock substringWithRange:NSMakeRange(4,2)],[clock substringFromIndex:6]];
                    fields=DARExifFromISODate(iso);
                }
            }
        }
    }
    CFRelease(source);return fields;
}
NSDate *DARPhotoCaptureDate(NSData *data) { return DARDateFromExif(DARCaptureFields(data)); }
NSData *DARPhotoCompatibleJPEG(NSData *data) {
    UIImage *image=[UIImage imageWithData:data];
    NSData *jpeg=image?UIImageJPEGRepresentation(image,0.98):nil;
    if(!jpeg || !DARPhotoCaptureDate(data))return jpeg;
    NSDictionary *exif=DARCaptureFields(data);
    NSMutableDictionary *dates=[NSMutableDictionary new];
    for(NSString *key in @[(__bridge NSString *)kCGImagePropertyExifDateTimeOriginal,
                          (__bridge NSString *)kCGImagePropertyExifOffsetTimeOriginal,
                          (__bridge NSString *)kCGImagePropertyExifSubsecTimeOriginal]) {
        if([exif[key] isKindOfClass:NSString.class])dates[key]=exif[key];
    }
    // Reattach capture date fields after UIKit's format conversion. Use the
    // converted JPEG as the source so its pixel orientation stays intact.
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)jpeg,NULL);
    NSMutableData *result=[NSMutableData new];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)result,CFSTR("public.jpeg"),1,NULL);
    BOOL saved=NO;
    if(source && destination) {
        NSDictionary *properties=@{(__bridge NSString *)kCGImagePropertyExifDictionary:dates};
        CGImageDestinationAddImageFromSource(destination,source,0,(__bridge CFDictionaryRef)properties);
        saved=CGImageDestinationFinalize(destination);
    }
    if(source)CFRelease(source);if(destination)CFRelease(destination);
    return saved?result:jpeg;
}
void DARConfigurePhotoRequest(PHAssetCreationRequest *creation,NSData *data,NSDate *captureDate) {
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    NSString *identifier=source?[(__bridge NSString *)CGImageSourceGetType(source) copy]:nil;
    if(source)CFRelease(source);
    PHAssetResourceCreationOptions *options=[PHAssetResourceCreationOptions new];
    if(identifier.length) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        options.uniformTypeIdentifier=identifier;
#pragma clang diagnostic pop
        NSString *extension=[UTType typeWithIdentifier:identifier].preferredFilenameExtension;
        if(extension.length)options.originalFilename=[[@"Douyin-" stringByAppendingString:NSUUID.UUID.UUIDString] stringByAppendingPathExtension:extension];
    }
    [creation addResourceWithType:PHAssetResourceTypePhoto data:data options:options];
    if(captureDate)creation.creationDate=captureDate;
}
static NSError *DARPhotoError(NSString *message) {
    return [NSError errorWithDomain:@"DouyinAntiRecall.Photo" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSError *DARPhotoStageError(NSString *stage,NSError *error) {
    return DARPhotoError(error?[NSString stringWithFormat:@"%@（%@ %ld）",stage,error.domain,(long)error.code]:stage);
}
NSData *DARReadPhotoDownload(NSURL *file,NSURLResponse *response,NSError *networkError,NSError **error) {
    NSError *failure;
    if(networkError)failure=DARPhotoStageError(@"图片下载失败",networkError);
    else if(![response isKindOfClass:NSHTTPURLResponse.class])failure=DARPhotoError(@"图片下载未返回 HTTP 响应");
    else if(((NSHTTPURLResponse *)response).statusCode!=200)failure=DARPhotoError([NSString stringWithFormat:@"图片下载 HTTP %ld",(long)((NSHTTPURLResponse *)response).statusCode]);
    NSNumber *size;NSError *readError;
    if(!failure && ![file getResourceValue:&size forKey:NSURLFileSizeKey error:&readError])failure=DARPhotoStageError(@"无法读取下载文件",readError);
    if(!failure && (!size.unsignedLongLongValue || size.unsignedLongLongValue>50*1024*1024))failure=DARPhotoError(@"图片为空或超过 50 MB");
    NSData *data;
    if(!failure) {
        data=[NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:&readError];
        if(!data)failure=DARPhotoStageError(@"无法读取图片数据",readError);
        else if(![UIImage imageWithData:data])failure=DARPhotoError(@"下载内容不是可解码图片");
    }
    if(error)*error=failure;
    return failure?nil:data;
}
static void DARFetchPhoto(NSURL *url,void(^completion)(NSData *,NSError *)) {
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];request.timeoutInterval=30;
    [request setValue:@"image/*,*/*;q=0.8" forHTTPHeaderField:@"Accept"];
    [[NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *file,NSURLResponse *response,NSError *networkError){
        NSError *error;NSData *data=DARReadPhotoDownload(file,response,networkError,&error);
        // downloadTask removes its temporary file after this callback. Materialize
        // bytes before the next asynchronous Photos transaction uses them.
        if(data)data=[NSData dataWithBytes:data.bytes length:data.length];
        completion(data,error);
    }] resume];
}
static void DARWritePhoto(NSData *data,NSDate *date,void(^completion)(BOOL,NSError *)) {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        DARConfigurePhotoRequest([PHAssetCreationRequest creationRequestForAsset],data,date);
    } completionHandler:^(BOOL success,NSError *error){
        completion(success,success?nil:DARPhotoStageError(@"相册写入失败",error));
    }];
}
@interface DARImageSaveTask : NSObject
@property(nonatomic,strong) NSArray<NSArray<NSURL *> *> *candidates;
@property(nonatomic,copy) DARPhotoFetch fetch;
@property(nonatomic,copy) DARPhotoWrite writer;
@property(nonatomic,copy) void(^completion)(NSUInteger,NSUInteger,NSUInteger,NSError *);
@property(nonatomic) NSUInteger index,attempt,successes,recognized,dated;
@property(nonatomic) BOOL currentRecognized;
@property(nonatomic,strong) NSError *lastError,*currentError;
@property(nonatomic,strong) NSDate *captureDate;
- (void)next;
- (void)tryCandidate;
@end
@implementation DARImageSaveTask
- (void)next {
    if(self.index>=self.candidates.count){self.completion(self.successes,self.recognized,self.dated,self.lastError);return;}
    self.attempt=0;self.currentRecognized=NO;self.currentError=nil;self.captureDate=nil;[self tryCandidate];
}
- (void)finishImage:(BOOL)saved date:(NSDate *)date error:(NSError *)error {
    if(saved){self.successes++;if(date)self.dated++;}
    else self.lastError=error?:DARPhotoError(@"图片保存失败");
    self.index++;[self next];
}
- (void)tryCandidate {
    NSArray *urls=self.candidates[self.index];
    if(self.attempt>=urls.count){[self finishImage:NO date:nil error:self.currentError?:DARPhotoError(@"当前图片没有可用的原图地址")];return;}
    NSURL *url=urls[self.attempt++];
    self.fetch(url,^(NSData *data,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(!data.length || error){self.currentError=error?:DARPhotoError(@"图片下载为空");[self tryCandidate];return;}
            NSDate *date=DARPhotoCaptureDate(data)?:self.captureDate;
            if(date)self.captureDate=date;
            if(date && !self.currentRecognized){self.recognized++;self.currentRecognized=YES;}
            self.writer(data,date,^(BOOL saved,NSError *saveError){
                dispatch_async(dispatch_get_main_queue(),^{
                    if(saved){[self finishImage:YES date:date error:nil];return;}
                    NSData *jpeg=DARPhotoCompatibleJPEG(data);
                    if(!jpeg){self.currentError=saveError?:DARPhotoError(@"图片格式无法转换");[self tryCandidate];return;}
                    self.writer(jpeg,date,^(BOOL retried,NSError *retryError){
                        dispatch_async(dispatch_get_main_queue(),^{
                            if(retried)[self finishImage:YES date:date error:nil];
                            else {self.currentError=retryError?:saveError?:DARPhotoError(@"相册写入失败");[self tryCandidate];}
                        });
                    });
                });
            });
        });
    });
}
@end
void DARSavePhotoCandidates(NSArray<NSArray<NSURL *> *> *candidates,DARPhotoFetch fetch,DARPhotoWrite writer,
    void(^completion)(NSUInteger,NSUInteger,NSUInteger,NSError *)) {
    dispatch_async(dispatch_get_main_queue(),^{
        DARImageSaveTask *task=[DARImageSaveTask new];task.candidates=candidates;
        task.fetch=fetch?:^(NSURL *url,void(^done)(NSData *,NSError *)){DARFetchPhoto(url,done);};
        task.writer=writer?:^(NSData *data,NSDate *date,void(^done)(BOOL,NSError *)){DARWritePhoto(data,date,done);};
        task.completion=completion;[task next];
    });
}
void DARSaveImages(id model,BOOL all) {
    if(!DAROptionEnabled(DAROptionImages)){DARToast(@"请先开启无水印保存图片");return;}
    id images=DARGet(model,@"albumImages"); if(![images isKindOfClass:NSArray.class] || ![images count]){DARToast(@"当前内容没有可保存的图片");return;}
    NSArray *selected=images;
    if(!all) {long long index=DARNumber(model,@"currentImageIndex"); if(index<1 || index>(long long)[images count])index=1;selected=@[images[(NSUInteger)index-1]];}
    NSMutableArray *candidates=[NSMutableArray new]; for(id image in selected)[candidates addObject:DAROriginalImageURLs(image)];
    BOOL any=NO;for(NSArray *urls in candidates)if(urls.count){any=YES;break;}
    if(!any){DARToast(@"没有可用的原图地址");return;}
    if(![NSBundle.mainBundle objectForInfoDictionaryKey:@"NSPhotoLibraryAddUsageDescription"]){DARToast(@"当前安装包缺少保存相册的权限说明");return;}
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status){
        dispatch_async(dispatch_get_main_queue(),^{
            if(status!=PHAuthorizationStatusAuthorized && status!=PHAuthorizationStatusLimited){DARToast(@"请在系统设置中允许添加照片");return;}
            DARToast(@"正在保存原图…");
            DARSavePhotoCandidates(candidates,nil,nil,^(NSUInteger saved,NSUInteger recognized,NSUInteger dated,NSError *error){
                NSString *summary=[NSString stringWithFormat:@"已保存 %lu/%lu 张；识别拍摄日期 %lu 张，成功按日期归档 %lu 张",(unsigned long)saved,(unsigned long)candidates.count,(unsigned long)recognized,(unsigned long)dated];
                if(saved && !recognized)summary=[summary stringByAppendingString:@"；原图未提供可用拍摄日期"];
                if(saved==candidates.count){DARToast(summary);return;}
                UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"图片未全部保存" message:[summary stringByAppendingFormat:@"\n%@",error.localizedDescription?:@"保存失败，请重试"] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                UIViewController *presenter=DARTopController();
                if(presenter)[presenter presentViewController:alert animated:YES completion:nil];else DARToast(alert.message);
            });
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
static IMP DAROriginalCommentImageDownload;
static id DARCommentImageDownload(id self,SEL selector) {
    if(DAROptionEnabled(DAROptionCommentImages)) {
        id originalImage=DARGet(self,@"originUrl");
        NSMutableArray *urls=[NSMutableArray new];DARCollectImageURLs(originalImage,urls,0);
        if(urls.count)return originalImage;
        // Fail visibly rather than silently falling back to the watermarked URL.
        DARToast(@"此评论图片没有可用的原图地址");return nil;
    }
    return ((id(*)(id,SEL))DAROriginalCommentImageDownload)(self,selector);
}
BOOL DARInstallCommentImageHooks(void) {
    return DARHook(NSClassFromString(@"AWECommentImageModel"),@"downloadUrl",(IMP)DARCommentImageDownload,&DAROriginalCommentImageDownload,"@",2);
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
