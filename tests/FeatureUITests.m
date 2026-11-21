#import "DARFeatures.h"
#import "DAROptions.h"
#import "DARAudio.h"
#import "DARRuntime.h"
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>
#import <Photos/Photos.h>
#import <objc/message.h>
#include <math.h>
extern void DARFeatureAssert(BOOL,NSString *);
#define FCheck(c,m) DARFeatureAssert((c),(m))
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@interface AWESettingItemModel : NSObject
@property(copy)NSString *identifier,*title,*subTitle,*svgIconImageName;
@property NSInteger cellType;
@property BOOL isEnable;
@property(copy)void(^cellTappedBlock)(void);
@end
@implementation AWESettingItemModel
@end
@interface AWESettingSectionModel : NSObject
@property(copy)NSString *identifier;
@property(strong)NSArray *itemArray;
@end
@implementation AWESettingSectionModel
@end
@interface AWESettingsViewModel : NSObject
@property(strong)NSArray *sectionDataArray;
@property(weak)id controllerDelegate;
@end
@implementation AWESettingsViewModel
@end
@interface AWELongPressPanelBaseViewModel : NSObject
@property(strong)id awemeModel;
@property NSUInteger actionType;
@property(copy)NSString *duxIconName,*describeString;
@property(copy)void(^action)(void);
@end
@implementation AWELongPressPanelBaseViewModel
@end
@interface AWELongPressPanelViewGroupModel : NSObject
@property NSUInteger groupType;
@property BOOL isModern;
@property(strong)NSArray *groupArr;
@end
@implementation AWELongPressPanelViewGroupModel
@end
@interface AWEModernLongPressPanelTableViewController : NSObject
@property(strong)NSArray *dataArray;
@property(strong)id awemeModel;
@end
@implementation AWEModernLongPressPanelTableViewController
@end
@interface AWELongPressPanelTableViewController : NSObject
@property(strong)NSArray *dataArray;
@property(strong)id awemeModel;
@end
@implementation AWELongPressPanelTableViewController
@end
@interface FeatureModel : NSObject
@property(copy)NSString *cityCode,*ipAttribution;
@property(strong)NSArray *albumImages,*watermarkFreeUrlList,*urlList;
@property NSInteger currentImageIndex;
@end
@implementation FeatureModel
@end
@interface AWEPlayInteractionTimestampElement : NSObject
@property(strong)UILabel *timestampLabel;
@property(strong)FeatureModel *model;
+ (BOOL)shouldActiveWithData:(id)data context:(id)context;
@end
@implementation AWEPlayInteractionTimestampElement
+ (BOOL)shouldActiveWithData:(__unused id)data context:(__unused id)context {return NO;}
@end
@interface FeatureRecorder : NSObject
@property(strong)NSURL *url;
@property double currentTime;
@property BOOL hasCancelled;
@end
@implementation FeatureRecorder
@end
@interface AWECommentAudioRecorderController : NSObject
@property NSInteger calls;
@property double observedDuration;
@property(strong)NSData *observedData;
- (void)audioRecorderDidFinishRecording:(id)recorder success:(BOOL)success error:(id)error;
@end
@implementation AWECommentAudioRecorderController
- (void)audioRecorderDidFinishRecording:(FeatureRecorder *)recorder success:(__unused BOOL)success error:(__unused id)error {
    self.calls++; self.observedDuration=recorder.currentTime;self.observedData=[NSData dataWithContentsOfURL:recorder.url];
}
@end
@interface AWECommentAudioUploadManager : NSObject
@property NSInteger calls;
@property(strong)NSData *observedData;
- (void)startUploadAudioWithFilePath:(NSString *)path;
@end
@implementation AWECommentAudioUploadManager
- (void)startUploadAudioWithFilePath:(NSString *)path {self.calls++;self.observedData=[NSData dataWithContentsOfFile:path];}
@end
@interface FeatureAudioInput : NSObject
@property(copy)NSString *audioFilePath;
@end
@implementation FeatureAudioInput
@end
static NSInteger ModernUploadCalls;
static NSData *ModernUploadData;
static void RegisterModernUploader(void) {
    Class cls=objc_allocateClassPair(NSObject.class,"_TtC31AWECommentMediaManagerSwiftImpl27CommentMediaUploaderManager",0);
    IMP method=imp_implementationWithBlock(^id(__unused id self,FeatureAudioInput *input){
        ModernUploadCalls++;ModernUploadData=[NSData dataWithContentsOfFile:input.audioFilePath];return input;
    });
    class_addMethod(cls,NSSelectorFromString(@"audioUploader:"),method,"@24@0:8@16");objc_registerClassPair(cls);
}
@interface FeaturePhotoRequest : NSObject
@property(nonatomic,strong) NSDate *creationDate;
@property(nonatomic,strong) NSData *resource;
@property(nonatomic) NSUInteger dateWrites;
@property(nonatomic) PHAssetResourceType resourceType;
- (void)addResourceWithType:(PHAssetResourceType)type data:(NSData *)data options:(PHAssetResourceCreationOptions *)options;
@end
@implementation FeaturePhotoRequest
- (void)setCreationDate:(NSDate *)date { _creationDate=date;_dateWrites++; }
- (void)addResourceWithType:(PHAssetResourceType)type data:(NSData *)data options:(__unused PHAssetResourceCreationOptions *)options {self.resourceType=type;self.resource=data;}
@end
static NSData *PhotoDateFixture(NSData *pixels,NSDictionary *exif,NSDictionary *tiff) {
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)pixels,NULL);
    NSMutableData *data=[NSMutableData new];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,CFSTR("public.jpeg"),1,NULL);
    NSMutableDictionary *properties=[NSMutableDictionary new];
    if(exif)properties[(__bridge NSString *)kCGImagePropertyExifDictionary]=exif;
    if(tiff)properties[(__bridge NSString *)kCGImagePropertyTIFFDictionary]=tiff;
    CGImageDestinationAddImageFromSource(destination,source,0,(__bridge CFDictionaryRef)properties);
    BOOL saved=CGImageDestinationFinalize(destination);CFRelease(source);CFRelease(destination);
    FCheck(saved,@"capture-date fixture embeds real image metadata");return data;
}
static NSDate *UTCDate(NSInteger year,NSInteger month,NSInteger day,NSInteger hour,NSInteger minute,NSInteger second) {
    NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDateComponents *parts=[NSDateComponents new];parts.year=year;parts.month=month;parts.day=day;
    parts.hour=hour;parts.minute=minute;parts.second=second;return [calendar dateFromComponents:parts];
}
static void TestPhotoCaptureDates(NSData *pixels) {
    NSString *dateKey=(__bridge NSString *)kCGImagePropertyExifDateTimeOriginal;
    NSString *offsetKey=(__bridge NSString *)kCGImagePropertyExifOffsetTimeOriginal;
    NSString *subKey=(__bridge NSString *)kCGImagePropertyExifSubsecTimeOriginal;
    NSData *original=PhotoDateFixture(pixels,@{dateKey:@"2020:02:29 12:34:56",offsetKey:@"+08:00",subKey:@"1234"},nil);
    NSDate *expected=[UTCDate(2020,2,29,4,34,56) dateByAddingTimeInterval:0.1234];
    NSDate *capture=DARPhotoCaptureDate(original);
    FCheck(capture && fabs([capture timeIntervalSinceDate:expected])<0.001,@"EXIF original capture date honors offset subsecond and leap day");
    NSData *converted=DARPhotoCompatibleJPEG(original);
    NSDate *convertedDate=DARPhotoCaptureDate(converted);
    FCheck(convertedDate && fabs([convertedDate timeIntervalSinceDate:expected])<0.001,@"JPEG compatibility conversion retains original capture date and timezone");
    FeaturePhotoRequest *request=[FeaturePhotoRequest new];
    DARConfigurePhotoRequest((PHAssetCreationRequest *)request,original,capture);
    FCheck([request.creationDate isEqual:capture] && request.dateWrites==1 && request.resource==original && request.resourceType==PHAssetResourceTypePhoto,@"original Photos request sets capture date and keeps original bytes");
    FeaturePhotoRequest *retry=[FeaturePhotoRequest new];
    DARConfigurePhotoRequest((PHAssetCreationRequest *)retry,converted,capture);
    FCheck([retry.creationDate isEqual:capture] && retry.resource==converted,@"JPEG retry uses the same capture date for the Photos asset");
    NSData *negative=PhotoDateFixture(pixels,@{dateKey:@"2024:01:01 00:15:00",offsetKey:@"-05:30"},nil);
    FCheck([DARPhotoCaptureDate(negative) isEqual:UTCDate(2024,1,1,5,45,0)],@"negative half-hour timezone offsets are interpreted correctly");
    NSTimeZone *previous=NSTimeZone.defaultTimeZone;
    NSTimeZone.defaultTimeZone=[NSTimeZone timeZoneForSecondsFromGMT:8*3600];
    NSData *local=PhotoDateFixture(pixels,@{dateKey:@"2024:06:01 12:00:00"},nil);
    NSCalendar *systemCalendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    systemCalendar.timeZone=NSTimeZone.localTimeZone;
    NSDateComponents *localParts=[NSDateComponents new];localParts.year=2024;localParts.month=6;localParts.day=1;localParts.hour=12;
    NSDate *expectedLocal=[systemCalendar dateFromComponents:localParts];
    NSDate *localDate=DARPhotoCaptureDate(local);NSTimeZone.defaultTimeZone=previous;
    FCheck([localDate isEqual:expectedLocal],@"EXIF without timezone follows the device system timezone rather than an app override");
    for(NSDictionary *invalid in @[@{dateKey:@"0000:00:00 00:00:00"},@{dateKey:@"2023:02:29 12:00:00"},
                                  @{dateKey:@"2024:01:01 25:00:00"},@{dateKey:@"invalid"},
                                  @{dateKey:@"2024:01:01 00:00:00",offsetKey:@"+15:00"},
                                  @{dateKey:@"2024:01:01 00:00:00",offsetKey:@"+08:90"}]) {
        FCheck(!DARPhotoCaptureDate(PhotoDateFixture(pixels,invalid,nil)),@"invalid or empty capture timestamps are not used as photo dates");
    }
    NSData *edited=PhotoDateFixture(pixels,@{(__bridge NSString *)kCGImagePropertyExifDateTimeDigitized:@"2024:01:01 12:00:00"},
                                   @{(__bridge NSString *)kCGImagePropertyTIFFDateTime:@"2025:01:01 12:00:00"});
    FCheck(!DARPhotoCaptureDate(edited) && !DARPhotoCaptureDate(pixels) && !DARPhotoCaptureDate([NSData data]),@"edit digitization and missing dates never substitute for capture time");
    FeaturePhotoRequest *undated=[FeaturePhotoRequest new];
    DARConfigurePhotoRequest((PHAssetCreationRequest *)undated,pixels,nil);
    FCheck(!undated.dateWrites && undated.resource==pixels,@"undated image saves normally without overriding the system date");
}
static void TestSettingsIPMenus(void) {
    for(NSString *key in @[DAROptionIP,DAROptionAudioLibrary,DAROptionCommentAudio,DAROptionImages])DARSetOption(key,NO);
    RegisterModernUploader();
    FCheck(DARInstallFeatures(),@"all new feature hooks match observed ABI and install");
    FCheck(DARInstallFeatures(),@"feature hook installation is idempotent");
    AWESettingsViewModel *settings=[AWESettingsViewModel new];settings.sectionDataArray=@[];
    NSArray *sections=settings.sectionDataArray;
    FCheck(sections.count==1,@"native settings receives plugin section");
    AWESettingItemModel *entry=[(AWESettingSectionModel *)sections.firstObject itemArray].firstObject;
    FCheck([entry.title isEqual:@"抖音增强"] && entry.cellTappedBlock!=nil,@"settings entry has a working tap action");
    FCheck(DARAugmentSettingsSections(sections,settings).count==1,@"settings entry is not duplicated");
    UITableViewController *plugin=[[NSClassFromString(@"DARSettingsController") alloc] init];[plugin loadViewIfNeeded];
    FCheck([plugin numberOfSectionsInTableView:plugin.tableView]==4,@"plugin settings groups cover messages IP audio and photos");
    NSArray *rowCounts=@[@2,@1,@3,@1];
    for(NSUInteger section=0;section<4;section++)FCheck([plugin tableView:plugin.tableView numberOfRowsInSection:section]==[rowCounts[section] integerValue],@"settings includes all individual switches and audio-library entry");
    UITableViewCell *option=[plugin tableView:plugin.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    UISwitch *toggle=(UISwitch *)option.accessoryView;toggle.on=YES;[toggle sendActionsForControlEvents:UIControlEventValueChanged];
    FCheck(DAROptionEnabled(DAROptionIP),@"settings switch persists option state");
    FeatureModel *model=[FeatureModel new];model.cityCode=@"330100";model.ipAttribution=@"IP属地：浙江";
    FCheck([DARLocationForModel(model) isEqual:@"浙江 杭州"],@"offline city code resolves province and city");
    AWEPlayInteractionTimestampElement *element=[AWEPlayInteractionTimestampElement new];element.model=model;
    element.timestampLabel=[UILabel new];element.timestampLabel.text=@"2 小时前";
    FCheck([element.timestampLabel.text containsString:@"IP属地：浙江 杭州"],@"IP appears beside native timestamp");
    NSString *once=element.timestampLabel.text;FCheck([element.timestampLabel.text isEqual:once],@"repeated IP label reads do not append duplicates");
    DARSetOption(DAROptionIP,NO);
    FCheck([element.timestampLabel.text isEqual:@"2 小时前"],@"IP switch restores original timestamp");
    model.cityCode=@"invalid";model.ipAttribution=@"IP 属地：日本";
    FCheck([DARLocationForModel(model) isEqual:@"日本"],@"international IP attribution uses platform data without network lookups");
    DARSetOption(DAROptionIP,YES);
    FCheck([AWEPlayInteractionTimestampElement shouldActiveWithData:nil context:nil],@"IP option activates timestamp element");
    FeatureModel *image=[FeatureModel new];image.watermarkFreeUrlList=@[@"https://example.test/original.jpg"];image.urlList=@[@"https://example.test/display.jpg"];
    FCheck([DAROriginalImageURL(image).absoluteString isEqual:@"https://example.test/original.jpg"],@"original-image selector prefers watermarkFreeUrlList");
    FCheck(!DAROriginalImageURL([FeatureModel new]),@"missing image URLs safely produce no download action target");
    image.watermarkFreeUrlList=@[@"file:///unwanted"];
    FCheck([DAROriginalImageURL(image).absoluteString isEqual:@"https://example.test/display.jpg"],@"image URL fallback accepts only HTTP and HTTPS");
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
    UIImage *small=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(12,7) format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
        CGContextSetFillColorWithColor(context.CGContext,UIColor.blueColor.CGColor);CGContextFillRect(context.CGContext,CGRectMake(0,0,12,7));
    }];
    TestPhotoCaptureDates(UIImagePNGRepresentation(small));
    NSData *jpeg=DARPhotoCompatibleJPEG(UIImagePNGRepresentation(small));UIImage *compatible=[UIImage imageWithData:jpeg];
    FCheck(jpeg.length && CGImageGetWidth(compatible.CGImage)==12 && CGImageGetHeight(compatible.CGImage)==7,@"photo format fallback retains full pixel dimensions");
    FCheck(!DARPhotoCompatibleJPEG([@"invalid" dataUsingEncoding:NSUTF8StringEncoding]),@"invalid image data never produces a fake saved photo");
    model.albumImages=@[image,image];model.currentImageIndex=2;
    AWELongPressPanelViewGroupModel *nativeGroup=[AWELongPressPanelViewGroupModel new];nativeGroup.groupArr=@[];
    NSArray *original=@[nativeGroup];
    FCheck([DARAugmentLongPressGroups(original,model,YES) isEqual:original],@"disabled media switches leave native menu intact");
    DARSetOption(DAROptionAudioLibrary,YES);DARSetOption(DAROptionImages,YES);
    NSArray *augmented=DARAugmentLongPressGroups(original,model,YES);
    AWELongPressPanelViewGroupModel *custom=augmented.firstObject;
    FCheck(augmented.count==2 && custom.groupArr.count==4 && custom.isModern,@"modern menu contains audio import library current image and full album actions");
    FCheck(original.count==1 && nativeGroup.groupArr.count==0,@"native menu model is never mutated");
    FCheck(DARAugmentLongPressGroups(augmented,model,YES).count==2,@"repeated menu reads cannot duplicate plugin groups");
    AWELongPressPanelTableViewController *classic=[AWELongPressPanelTableViewController new];classic.dataArray=original;classic.awemeModel=model;
    FCheck([(AWELongPressPanelViewGroupModel *)classic.dataArray.firstObject groupType]==0,@"classic menu hook uses native group type");
    AWEModernLongPressPanelTableViewController *modern=[AWEModernLongPressPanelTableViewController new];modern.dataArray=original;modern.awemeModel=model;
    FCheck([(AWELongPressPanelViewGroupModel *)modern.dataArray.firstObject groupArr].count==4,@"modern getter hook injects feature actions");
}
static NSURL *AudioFixture(NSURL *directory) {
    NSURL *url=[directory URLByAppendingPathComponent:@"fixture.wav"];
    AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
    NSError *error;AVAudioFile *file=[[AVAudioFile alloc] initForWriting:url settings:format.settings error:&error];
    AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:88200];buffer.frameLength=88200;
    for(AVAudioFrameCount i=0;i<buffer.frameLength;i++)buffer.floatChannelData[0][i]=0.1f*sinf(2.0f*(float)M_PI*440.0f*(float)i/44100.0f);
    BOOL wrote=[file writeFromBuffer:buffer error:&error];
    FCheck(file && wrote && !error,@"audio fixture encodes without microphone or network access");return url;
}
static void WaitForAudioRow(UITableViewController *controller, NSUInteger remaining, void(^completion)(NSError *)) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(DARAudioLibrary.shared.armed && !DARGet(controller,@"preparingFile")) {
            FCheck(controller.navigationItem.prompt==nil,@"row preparation clears its busy prompt");
            completion(nil);return;
        }
        FCheck(remaining>0,@"inline Send prepares audio within the simulator deadline");
        WaitForAudioRow(controller,remaining-1,completion);
    });
}
static void TestAudioRowControls(NSURL *imported, NSURL *fixture, void(^completion)(NSError *)) {
    UITableViewController *controller=[[NSClassFromString(@"DARLibraryController") alloc] init];
    [controller loadViewIfNeeded];
    DARPut(controller,@"setFiles:",@[imported]);
    NSIndexPath *index=[NSIndexPath indexPathForRow:0 inSection:0];
    UITableViewCell *cell=[controller.tableView.dataSource tableView:controller.tableView cellForRowAtIndexPath:index];
    cell.frame=CGRectMake(0,0,320,64);[cell layoutIfNeeded];
    FCheck([cell.accessoryView isKindOfClass:UIStackView.class],@"each audio row exposes inline controls");
    NSArray *buttons=((UIStackView *)cell.accessoryView).arrangedSubviews;
    FCheck(buttons.count==2,@"audio row contains preview and Send buttons");
    UIButton *play=buttons[0],*send=buttons[1];
    FCheck([play.accessibilityIdentifier isEqual:@"DAR.audio.play"] && [send.accessibilityIdentifier isEqual:@"DAR.audio.send"] && [send.configuration.title isEqual:@"发送"],@"inline controls have accessible preview and Send labels");
    FCheck(CGRectGetMaxX(cell.textLabel.frame)<=CGRectGetMinX(cell.accessoryView.frame),@"audio filename does not overlap inline controls at narrow width");
    [play sendActionsForControlEvents:UIControlEventTouchUpInside];
    FCheck([((AVAudioPlayer *)DARGet(controller,@"player")).url isEqual:imported],@"preview button targets its own audio file");
    NSURL *other=[DARAudioLibrary.shared importFile:fixture name:@"other.wav" error:NULL];
    FCheck(other!=nil,@"second audio fixture imports for row binding regression");
    DARPut(controller,@"setFiles:",@[other,imported]);
    [send sendActionsForControlEvents:UIControlEventTouchUpInside];
    FCheck([DARGet(controller,@"preparingFile") isEqual:imported],@"captured Send button keeps its file after list reordering");
    UITableViewCell *busy=[controller.tableView.dataSource tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    UIButton *busySend=((UIStackView *)busy.accessoryView).arrangedSubviews[1];
    FCheck(!busySend.enabled && busySend.configuration.showsActivityIndicator,@"preparing row shows a spinner and prevents duplicate taps");
    UIBarButtonItem *cancel=controller.toolbarItems.firstObject;
    [UIApplication.sharedApplication sendAction:cancel.action to:cancel.target from:cancel forEvent:nil];
    FCheck(!DARGet(controller,@"preparingFile") && !DARAudioLibrary.shared.armed,@"cancel clears row busy and pending audio states");
    [send sendActionsForControlEvents:UIControlEventTouchUpInside];
    FCheck([DARGet(controller,@"preparingFile") isEqual:imported],@"Send can restart immediately after cancellation");
    WaitForAudioRow(controller,300,^(NSError *error){
        [DARAudioLibrary.shared removeFile:other error:NULL];completion(error);
    });
}
void DARRunFeatureTests(void(^completion)(void)) {
    TestSettingsIPMenus();
    FCheck([DARAudioExtensionForDownload([NSURL URLWithString:@"https://example.test/a.MP3"],nil) isEqual:@"mp3"],@"missing Content-Type falls back to the source audio extension");
    FCheck([DARAudioExtensionForDownload([NSURL URLWithString:@"https://example.test/audio?token=123"],@"audio/mpeg") isEqual:@"mp3"],@"downloaded MP3 retains its format even when the URL has no extension");
    FCheck([DARAudioExtensionForDownload([NSURL URLWithString:@"https://example.test/a.WAV?token=123"],@"application/octet-stream") isEqual:@"wav"],@"audio extension fallback ignores query tokens and normalizes case");
    FCheck([DARAudioExtensionForDownload([NSURL URLWithString:@"https://example.test/a.bin"],@"video/mp4") isEqual:@"mp4"],@"video audio fallback keeps a compatible container extension");
    NSURL *temporary=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:temporary withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *fixture=AudioFixture(temporary);NSError *error;
    DARAudioLibrary *library=DARAudioLibrary.shared;
    NSURL *imported=[library importFile:fixture name:@"../声音.wav" error:&error];
    FCheck(imported && !error && [imported.path hasPrefix:[library.directory.path stringByAppendingString:@"/"]],@"audio import stays inside the library and sanitizes file names");
    FCheck([library.files containsObject:imported],@"imported audio is visible in the library");
    NSURL *invalid=[temporary URLByAppendingPathComponent:@"bad.txt"];[@"not audio" writeToURL:invalid atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    FCheck(![library importFile:invalid name:@"invalid" error:&error],@"invalid audio import is rejected");
    FCheck(![library removeFile:fixture error:&error],@"library delete refuses files outside its directory");
    DARSetOption(DAROptionCommentAudio,YES);
    TestAudioRowControls(imported,fixture,^(NSError *prepareError){
        FCheck(!prepareError && library.armed,@"audio is transcoded and armed only after explicit selection");
        FCheck(library.preparedDuration>1.9 && library.preparedDuration<2.1,@"prepared audio preserves actual duration");
        NSURL *recording=[temporary URLByAppendingPathComponent:@"comment.m4a"];
        // A new recording writes fresh data. copyItem preserves the fixture's old
        // modification time and correctly belongs to the delayed-upload case.
        NSData *before=[NSData dataWithContentsOfURL:fixture];
        [before writeToURL:recording atomically:YES];
        FeatureRecorder *recorder=[FeatureRecorder new];recorder.url=recording;recorder.currentTime=1;
        AWECommentAudioRecorderController *controller=[AWECommentAudioRecorderController new];
        [controller audioRecorderDidFinishRecording:recorder success:YES error:nil];
        FCheck(controller.calls==1 && ![controller.observedData isEqual:before],@"comment finish callback receives prepared audio before original processing");
        FCheck(controller.observedDuration>1.9,@"comment recorder duration is updated before original callback");
        FCheck(!library.armed,@"replacement consumes the pending audio once");
        [before writeToURL:recording atomically:YES];
        [controller audioRecorderDidFinishRecording:recorder success:YES error:nil];
        FCheck([controller.observedData isEqual:before],@"next ordinary recording stays unchanged after one-shot consumption");
        [library prepareFile:imported completion:^(NSError *secondError){
            FCheck(!secondError,@"audio can be rearmed for another explicit send");
            [controller audioRecorderDidFinishRecording:recorder success:NO error:nil];
            FCheck(library.armed,@"failed or cancelled recording does not consume pending audio");
            recorder.hasCancelled=YES;
            [controller audioRecorderDidFinishRecording:recorder success:YES error:nil];
            FCheck(library.armed,@"explicit recorder cancellation preserves pending audio even if success is true");
            recorder.hasCancelled=NO;
            AWECommentAudioUploadManager *uploader=[AWECommentAudioUploadManager new];
            [uploader startUploadAudioWithFilePath:recording.path];
            FCheck(library.armed && [uploader.observedData isEqual:before],@"an old delayed upload cannot consume a newly armed selection");
            [before writeToURL:recording atomically:YES];
            [uploader startUploadAudioWithFilePath:recording.path];
            FCheck(uploader.calls==2 && ![uploader.observedData isEqual:before] && !library.armed,@"comment-specific upload fallback replaces and consumes once");
            [library prepareFile:imported completion:^(NSError *modernError){
                FCheck(!modernError,@"modern comment upload can prepare audio");
                [before writeToURL:recording atomically:YES];
                FeatureAudioInput *input=[FeatureAudioInput new];input.audioFilePath=recording.path;
                id manager=[[NSClassFromString(@"_TtC31AWECommentMediaManagerSwiftImpl27CommentMediaUploaderManager") alloc] init];
                id result=((id(*)(id,SEL,id))objc_msgSend)(manager,NSSelectorFromString(@"audioUploader:"),input);
                FCheck(result==input && ModernUploadCalls==1 && ![ModernUploadData isEqual:before] && !library.armed,@"modern comment uploader replaces audio and preserves the native return object");
            [library prepareFile:imported completion:^(NSError *thirdError){
                FCheck(!thirdError && library.armed,@"pending state is observable before switching off");
                DARSetOption(DAROptionCommentAudio,NO);FCheck(!library.armed,@"turning comment audio off cancels pending replacement immediately");
                DARSetOption(DAROptionCommentAudio,YES);
                [library prepareFile:imported completion:^(NSError *cancelledError){
                    FCheck(cancelledError && !library.armed,@"disabling during transcoding cannot rearm audio later");
                    [library removeFile:imported error:NULL];[NSFileManager.defaultManager removeItemAtURL:temporary error:NULL];
                    for(NSString *key in @[DAROptionIP,DAROptionAudioLibrary,DAROptionCommentAudio,DAROptionImages])DARSetOption(key,NO);
                    completion();
                }];
                DARSetOption(DAROptionCommentAudio,NO);
            }];
            }];
        }];
    });
}
#pragma clang diagnostic pop
