// The library/one-shot preparation flow is adapted from the MIT Aweme reference.
// Hooks are limited to comment recording/upload APIs observed in AwemeCore 41.2.0.
#import "DARAudio.h"
#import "DARFeatures.h"
#import "DARRuntime.h"
#import "DAROptions.h"
#import <CoreMedia/CoreMedia.h>
#include <math.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static NSError *DARError(NSString *message) { return [NSError errorWithDomain:@"DouyinAudio" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
NSString *DARAudioExtensionForDownload(NSURL *url,NSString *MIMEType) {
    NSDictionary *types=@{@"audio/mpeg":@"mp3",@"audio/mp3":@"mp3",@"audio/mp4":@"m4a",@"audio/x-m4a":@"m4a",@"audio/aac":@"aac",@"audio/wav":@"wav",@"audio/x-wav":@"wav",@"audio/flac":@"flac",@"audio/x-flac":@"flac",@"audio/ogg":@"ogg",@"video/mp4":@"mp4"};
    NSString *known=[MIMEType isKindOfClass:NSString.class]?types[MIMEType.lowercaseString]:nil;if(known)return known;
    NSString *ext=url.pathExtension.lowercaseString;
    return ext.length && [@[@"mp3",@"m4a",@"aac",@"wav",@"caf",@"aiff",@"aif",@"flac",@"ogg",@"mp4"] containsObject:ext]?ext:@"m4a";
}
@implementation DARAudioLibrary {
    NSURL *_directory, *_pending;
    NSDate *_expires, *_armedAt;
    NSURL *_pendingSource;
    NSMutableDictionary *_replacedFiles;
    NSTimeInterval _duration;
    NSUInteger _generation;
    id _optionObserver;
}
+ (instancetype)shared {
    static DARAudioLibrary *library; static dispatch_once_t once;
    dispatch_once(&once,^{
        NSURL *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        library=[[self alloc] initWithDirectory:[documents URLByAppendingPathComponent:@"DouyinAudioLibrary" isDirectory:YES]];
    }); return library;
}
- (instancetype)initWithDirectory:(NSURL *)directory {
    if((self=[super init])) {
        _directory=directory;
        _replacedFiles=[NSMutableDictionary new];
        [NSFileManager.defaultManager removeItemAtURL:[directory URLByAppendingPathComponent:@"Prepared" isDirectory:YES] error:NULL];
        [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        __weak typeof(self) weak=self;
        _optionObserver=[NSNotificationCenter.defaultCenter addObserverForName:DAROptionsDidChange object:nil queue:nil usingBlock:^(__unused NSNotification *n){
            if(!DAROptionEnabled(DAROptionCommentAudio))[weak cancelPending];
        }];
    } return self;
}
- (void)dealloc { if(_optionObserver)[NSNotificationCenter.defaultCenter removeObserver:_optionObserver]; }
- (NSURL *)directory { return _directory; }
- (BOOL)contains:(NSURL *)url {
    NSString *root=[_directory URLByResolvingSymlinksInPath].path;
    return url.isFileURL && [[url URLByResolvingSymlinksInPath].path hasPrefix:[root stringByAppendingString:@"/"]];
}
- (NSArray<NSURL *> *)files {
    NSArray *items=[NSFileManager.defaultManager contentsOfDirectoryAtURL:_directory includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    NSMutableArray *files=[NSMutableArray new];
    for(NSURL *url in items) { NSNumber *regular; [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:NULL]; if(regular.boolValue && [self contains:url])[files addObject:url]; }
    return [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){ return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent]; }];
}
- (NSURL *)importFile:(NSURL *)source name:(NSString *)name error:(NSError **)error {
    if(!source.isFileURL){if(error)*error=DARError(@"请选择本地音频文件");return nil;}
    NSNumber *size; [source getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:source options:nil];
    if(!source.isFileURL || !size || size.unsignedLongLongValue>50*1024*1024 || ![asset tracksWithMediaType:AVMediaTypeAudio].count) {
        if(error)*error=DARError(@"请选择小于 50 MB 的有效音频文件"); return nil;
    }
    NSString *base=[[name ?: source.lastPathComponent stringByDeletingPathExtension] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    base=[[base componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\:\n\r"]] componentsJoinedByString:@"_"];
    base=[base stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@". "]];
    if(!base.length)base=@"音频"; if(base.length>80)base=[base substringWithRange:[base rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,80)]];
    NSString *ext=source.pathExtension.lowercaseString;
    if(![@[@"mp3",@"m4a",@"aac",@"wav",@"caf",@"aiff",@"aif",@"flac",@"ogg",@"mp4"] containsObject:ext])ext=@"m4a";
    NSURL *destination=[_directory URLByAppendingPathComponent:[base stringByAppendingPathExtension:ext]];
    if([NSFileManager.defaultManager fileExistsAtPath:destination.path])
        destination=[_directory URLByAppendingPathComponent:[[base stringByAppendingFormat:@"-%@",[NSUUID.UUID.UUIDString substringToIndex:8]] stringByAppendingPathExtension:ext]];
    return [NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:error]?destination:nil;
}
- (BOOL)removeFile:(NSURL *)file error:(NSError **)error {
    if(![self contains:file]) { if(error)*error=DARError(@"文件不在音频库中"); return NO; }
    @synchronized(self) { if([file.URLByResolvingSymlinksInPath.path isEqual:_pendingSource.URLByResolvingSymlinksInPath.path])[self cancelPending]; }
    return [NSFileManager.defaultManager removeItemAtURL:file error:error];
}
- (void)download:(NSURL *)source name:(NSString *)name completion:(void(^)(NSError *))completion {
    if(![@[@"https",@"http"] containsObject:source.scheme.lowercaseString]) { completion(DARError(@"没有可用的音频地址")); return; }
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:source]; request.timeoutInterval=45;
    [[NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *file,NSURLResponse *response,NSError *error){
        if(!error && (![(NSHTTPURLResponse *)response isKindOfClass:NSHTTPURLResponse.class] || [(NSHTTPURLResponse *)response statusCode]!=200))error=DARError(@"音频下载失败");
        if(!error) {
            NSNumber *size;[file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
            if(!size || size.unsignedLongLongValue>50*1024*1024)error=DARError(@"音频超过 50 MB，未入库");
            else {
                NSString *ext=DARAudioExtensionForDownload(source,response.MIMEType);
                NSURL *staged=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:ext]];
                NSError *saveError;
                if([NSFileManager.defaultManager copyItemAtURL:file toURL:staged error:&saveError])
                    [self importFile:staged name:name error:&saveError];
                [NSFileManager.defaultManager removeItemAtURL:staged error:NULL];error=saveError;
            }
        }
        dispatch_async(dispatch_get_main_queue(),^{ completion(error); });
    }] resume];
}
- (BOOL)armed { @synchronized(self) { return _pending && _expires.timeIntervalSinceNow>0 && DAROptionEnabled(DAROptionCommentAudio); } }
- (NSTimeInterval)preparedDuration { @synchronized(self) { return _duration; } }
- (void)cancelPending {
    @synchronized(self) { _generation++; if(_pending)[NSFileManager.defaultManager removeItemAtURL:_pending error:NULL]; _pending=nil; _pendingSource=nil; _expires=nil; _armedAt=nil; _duration=0; }
}
- (void)prepareFile:(NSURL *)file completion:(void(^)(NSError *))completion {
    if(!DAROptionEnabled(DAROptionCommentAudio) || ![self contains:file]) { completion(DARError(@"请先开启评论音频发送，并选择音频库中的文件")); return; }
    [self cancelPending]; __block NSUInteger generation; @synchronized(self){generation=_generation;_pendingSource=file;}
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        AVURLAsset *asset=[AVURLAsset URLAssetWithURL:file options:nil];
        NSTimeInterval duration=CMTimeGetSeconds(asset.duration);
        if(!isfinite(duration)||duration<=0) { dispatch_async(dispatch_get_main_queue(),^{completion(DARError(@"无法读取音频时长"));}); return; }
        NSURL *preparedDir=[self.directory URLByAppendingPathComponent:@"Prepared" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:preparedDir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *output=[preparedDir URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"m4a"]];
        AVAssetExportSession *session=[[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
        if(!session) {dispatch_async(dispatch_get_main_queue(),^{completion(DARError(@"该音频无法转换"));});return;}
        session.outputURL=output; session.outputFileType=AVFileTypeAppleM4A;
        [session exportAsynchronouslyWithCompletionHandler:^{
            NSError *error=session.status==AVAssetExportSessionStatusCompleted?nil:(session.error?:DARError(@"音频转换失败"));
            @synchronized(self) {
                if(generation!=self->_generation || !DAROptionEnabled(DAROptionCommentAudio))error=DARError(@"已取消待发送音频");
                if(!error) { self->_pending=output; self->_duration=duration; self->_armedAt=[NSDate date]; self->_expires=[NSDate dateWithTimeIntervalSinceNow:300]; }
                else [NSFileManager.defaultManager removeItemAtURL:output error:NULL];
            }
            dispatch_async(dispatch_get_main_queue(),^{completion(error);});
        }];
    });
}
- (BOOL)replaceCommentRecording:(NSURL *)recording error:(NSError **)error {
    @synchronized(self) {
        if(!self.armed)return NO;
        NSString *path=recording.URLByResolvingSymlinksInPath.path;
        NSString *home=[NSURL fileURLWithPath:NSHomeDirectory()].URLByResolvingSymlinksInPath.path;
        NSNumber *regular; [recording getResourceValue:&regular forKey:NSURLIsRegularFileKey error:NULL];
        if(!recording.isFileURL || ![path hasPrefix:[home stringByAppendingString:@"/"]] ||
           [self contains:recording] || !regular.boolValue ||
           ![@[@"aac",@"m4a",@"caf",@"wav",@"mp3"] containsObject:path.pathExtension.lowercaseString])return NO;
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
        NSDate *modified=attributes[NSFileModificationDate];
        // A delayed upload of an older comment must not consume a newly armed sound.
        if(!modified || [modified compare:_armedAt]==NSOrderedAscending)return NO;
        NSDictionary *fingerprint=@{@"inode":attributes[NSFileSystemFileNumber]?:NSNull.null,
                                    @"modified":modified,@"size":attributes[NSFileSize]?:NSNull.null};
        if([_replacedFiles[path] isEqual:fingerprint])return NO;
        NSData *data=[NSData dataWithContentsOfURL:_pending options:NSDataReadingMappedIfSafe error:error];
        if(!data.length || ![data writeToURL:recording options:NSDataWritingAtomic error:error])return NO;
        NSDictionary *updated=[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
        _replacedFiles[path]=@{@"inode":updated[NSFileSystemFileNumber]?:NSNull.null,
                              @"modified":updated[NSFileModificationDate]?:NSNull.null,
                              @"size":updated[NSFileSize]?:NSNull.null};
        if(_replacedFiles.count>64)[_replacedFiles removeObjectForKey:_replacedFiles.allKeys.firstObject];
        [self cancelPending]; return YES;
    }
}
@end
static IMP DAROriginalCommentFinish, DAROriginalCommentUpload, DAROriginalModernCommentUploader;
static void DARCommentFinish(id self,SEL selector,id recorder,BOOL success,id error) {
    if(success && !error && !DARNumber(recorder,@"hasCancelled") && DAROptionEnabled(DAROptionCommentAudio)) {
        DARAudioLibrary *library=DARAudioLibrary.shared; NSTimeInterval duration=library.preparedDuration;
        NSURL *url=DARGet(recorder,@"url");
        if([url isKindOfClass:NSURL.class] && [library replaceCommentRecording:url error:NULL] && !DAROptionEnabled(DAROptionManualAudioDuration))DARPutNumber(recorder,@"setCurrentTime:",duration);
    }
    ((void(*)(id,SEL,id,BOOL,id))DAROriginalCommentFinish)(self,selector,recorder,success,error);
}
static void DARCommentUpload(id self,SEL selector,NSString *path) {
    if([path isKindOfClass:NSString.class] && DAROptionEnabled(DAROptionCommentAudio))
        [DARAudioLibrary.shared replaceCommentRecording:[NSURL fileURLWithPath:path] error:NULL];
    ((void(*)(id,SEL,id))DAROriginalCommentUpload)(self,selector,path);
}
static id DARModernCommentUploader(id self,SEL selector,id input) {
    if(DAROptionEnabled(DAROptionCommentAudio) && DARAudioLibrary.shared.armed) {
        NSMutableArray *models=[NSMutableArray arrayWithObject:input?:NSNull.null];
        for(NSString *key in @[@"audioModel",@"model",@"audioContent",@"content"]) {
            id nested=DARGet(input,key); if(nested)[models addObject:nested];
        }
        for(id model in models) {
            id value=DARGet(model,@"audioFilePath")?:DARGet(model,@"filePath")?:DARGet(model,@"fileURL");
            NSURL *url=[value isKindOfClass:NSURL.class]?value:([value isKindOfClass:NSString.class]?[NSURL fileURLWithPath:value]:nil);
            NSTimeInterval duration=DARAudioLibrary.shared.preparedDuration;
            if(url && [DARAudioLibrary.shared replaceCommentRecording:url error:NULL]) {
                Class audioClass=NSClassFromString(@"AWECommentAudioModel");
                if(!DAROptionEnabled(DAROptionManualAudioDuration) && audioClass && [model isKindOfClass:audioClass]) {
                    DARPutNumber(model,@"setDuration:",floor(duration));
                    DARPutNumber(model,@"setCurrentTime:",duration);
                }
                break;
            }
        }
    }
    return ((id(*)(id,SEL,id))DAROriginalModernCommentUploader)(self,selector,input);
}
BOOL DARInstallAudioHooks(void) {
    BOOL a=DARHook(NSClassFromString(@"AWECommentAudioRecorderController"),@"audioRecorderDidFinishRecording:success:error:",(IMP)DARCommentFinish,&DAROriginalCommentFinish,"v",5);
    BOOL b=DARHook(NSClassFromString(@"AWECommentAudioUploadManager"),@"startUploadAudioWithFilePath:",(IMP)DARCommentUpload,&DAROriginalCommentUpload,"v",3);
    BOOL c=DARHook(NSClassFromString(@"_TtC31AWECommentMediaManagerSwiftImpl27CommentMediaUploaderManager"),@"audioUploader:",(IMP)DARModernCommentUploader,&DAROriginalModernCommentUploader,"@",3);
    return a&&b&&c;
}
#pragma clang diagnostic pop
