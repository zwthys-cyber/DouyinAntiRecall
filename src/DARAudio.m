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
    BOOL _pendingUsesFileDuration;
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
    NSString *path=url.URLByResolvingSymlinksInPath.path;
    NSString *prepared=[root stringByAppendingPathComponent:@"Prepared"];
    return url.isFileURL && [path hasPrefix:[root stringByAppendingString:@"/"]] &&
        ![path isEqual:prepared] && ![path hasPrefix:[prepared stringByAppendingString:@"/"]];
}
- (BOOL)validDirectory:(NSURL *)directory {
    NSNumber *folder;
    [directory getResourceValue:&folder forKey:NSURLIsDirectoryKey error:NULL];
    return directory.isFileURL && folder.boolValue &&
        ([directory.URLByResolvingSymlinksInPath.path isEqual:_directory.URLByResolvingSymlinksInPath.path] || [self contains:directory]);
}
- (BOOL)validItemName:(NSString *)name {
    return [name isKindOfClass:NSString.class] && name.length && ![name hasPrefix:@"."] &&
        ![name isEqual:@"Prepared"] && [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\:\n\r"]].location==NSNotFound &&
        [[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] isEqual:name];
}
- (NSArray<NSURL *> *)itemsInDirectory:(NSURL *)directory {
    if(![self validDirectory:directory])return @[];
    NSArray *items=[NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    NSMutableArray *visible=[NSMutableArray new];
    for(NSURL *url in items) {
        NSNumber *folder,*regular;[url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:NULL];[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:NULL];
        if([self contains:url] && (folder.boolValue || regular.boolValue))[visible addObject:url];
    }
    return [visible sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){
        NSNumber *af,*bf;[a getResourceValue:&af forKey:NSURLIsDirectoryKey error:NULL];[b getResourceValue:&bf forKey:NSURLIsDirectoryKey error:NULL];
        if(af.boolValue!=bf.boolValue)return af.boolValue?NSOrderedAscending:NSOrderedDescending;
        return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }];
}
- (NSURL *)createFolder:(NSString *)name inDirectory:(NSURL *)directory error:(NSError **)error {
    if(![self validDirectory:directory] || ![self validItemName:name]){if(error)*error=DARError(@"文件夹名称或位置无效");return nil;}
    NSURL *target=[directory URLByAppendingPathComponent:name isDirectory:YES];
    if([NSFileManager.defaultManager fileExistsAtPath:target.path]){if(error)*error=DARError(@"同名文件或文件夹已存在");return nil;}
    return [NSFileManager.defaultManager createDirectoryAtURL:target withIntermediateDirectories:NO attributes:nil error:error]?target:nil;
}
- (void)cancelPendingForItem:(NSURL *)file {
    @synchronized(self) {
        NSString *path=file.URLByResolvingSymlinksInPath.path,*pending=_pendingSource.URLByResolvingSymlinksInPath.path;
        if([pending isEqual:path] || [pending hasPrefix:[path stringByAppendingString:@"/"]])[self cancelPending];
    }
}
- (NSURL *)renameItem:(NSURL *)file name:(NSString *)name error:(NSError **)error {
    if(![self contains:file] || ![self validItemName:name]){if(error)*error=DARError(@"名称或文件位置无效");return nil;}
    NSNumber *folder;[file getResourceValue:&folder forKey:NSURLIsDirectoryKey error:NULL];
    if(!folder.boolValue && file.pathExtension.length && ![name.pathExtension.lowercaseString isEqual:file.pathExtension.lowercaseString])name=[name stringByAppendingPathExtension:file.pathExtension];
    NSURL *target=[file.URLByDeletingLastPathComponent URLByAppendingPathComponent:name];
    if([file.path isEqual:target.path])return file;
    if(![NSFileManager.defaultManager moveItemAtURL:file toURL:target error:error])return nil;
    [self cancelPendingForItem:file];return target;
}
- (NSArray<NSURL *> *)files {
    NSArray *items=[NSFileManager.defaultManager contentsOfDirectoryAtURL:_directory includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    NSMutableArray *files=[NSMutableArray new];
    for(NSURL *url in items) { NSNumber *regular; [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:NULL]; if(regular.boolValue && [self contains:url])[files addObject:url]; }
    return [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){ return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent]; }];
}
- (NSURL *)importFile:(NSURL *)source name:(NSString *)name error:(NSError **)error {
    return [self importFile:source name:name intoDirectory:_directory error:error];
}
- (NSURL *)importFile:(NSURL *)source name:(NSString *)name intoDirectory:(NSURL *)directory error:(NSError **)error {
    if(![self validDirectory:directory]){if(error)*error=DARError(@"导入位置无效");return nil;}
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
    NSURL *destination=[directory URLByAppendingPathComponent:[base stringByAppendingPathExtension:ext]];
    if([NSFileManager.defaultManager fileExistsAtPath:destination.path])
        destination=[directory URLByAppendingPathComponent:[[base stringByAppendingFormat:@"-%@",[NSUUID.UUID.UUIDString substringToIndex:8]] stringByAppendingPathExtension:ext]];
    return [NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:error]?destination:nil;
}
- (BOOL)removeFile:(NSURL *)file error:(NSError **)error {
    if(![self contains:file]) { if(error)*error=DARError(@"文件不在音频库中"); return NO; }
    if(![NSFileManager.defaultManager removeItemAtURL:file error:error])return NO;
    [self cancelPendingForItem:file];return YES;
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
- (BOOL)preparedUsesFileDuration { @synchronized(self) { return _pendingUsesFileDuration; } }
- (void)cancelPending {
    @synchronized(self) { _generation++; if(_pending)[NSFileManager.defaultManager removeItemAtURL:_pending error:NULL]; _pending=nil; _pendingSource=nil; _expires=nil; _armedAt=nil; _duration=0; _pendingUsesFileDuration=NO; }
}
- (void)prepareFile:(NSURL *)file completion:(void(^)(NSError *))completion {
    [self prepareFile:file maxDuration:0 completion:completion];
}
- (void)prepareFile:(NSURL *)file maxDuration:(NSTimeInterval)maxDuration completion:(void(^)(NSError *))completion {
    if(!isfinite(maxDuration)||maxDuration<0){completion(DARError(@"无效的音频裁剪时长"));return;}
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
        if(maxDuration>0)session.timeRange=CMTimeRangeMake(kCMTimeZero,CMTimeMakeWithSeconds(MIN(duration,maxDuration),600));
        [session exportAsynchronouslyWithCompletionHandler:^{
            NSError *error=session.status==AVAssetExportSessionStatusCompleted?nil:(session.error?:DARError(@"音频转换失败"));
            NSTimeInterval actual=error?0:CMTimeGetSeconds([AVURLAsset URLAssetWithURL:output options:nil].duration);
            if(!error && (!isfinite(actual)||actual<=0))error=DARError(@"转换后的音频时长无效");
            @synchronized(self) {
                if(generation!=self->_generation || !DAROptionEnabled(DAROptionCommentAudio))error=DARError(@"已取消待发送音频");
                if(!error) { self->_pending=output; self->_duration=actual; self->_pendingUsesFileDuration=maxDuration>0; self->_armedAt=[NSDate date]; self->_expires=[NSDate dateWithTimeIntervalSinceNow:300]; }
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
        BOOL useFileDuration=library.preparedUsesFileDuration || !DAROptionEnabled(DAROptionManualAudioDuration);
        NSURL *url=DARGet(recorder,@"url");
        if([url isKindOfClass:NSURL.class] && [library replaceCommentRecording:url error:NULL] && useFileDuration)DARPutNumber(recorder,@"setCurrentTime:",duration);
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
            BOOL useFileDuration=DARAudioLibrary.shared.preparedUsesFileDuration || !DAROptionEnabled(DAROptionManualAudioDuration);
            if(url && [DARAudioLibrary.shared replaceCommentRecording:url error:NULL]) {
                Class audioClass=NSClassFromString(@"AWECommentAudioModel");
                if(useFileDuration && audioClass && [model isKindOfClass:audioClass]) {
                    // 41.2.0 sendRecordMessageOrNot (0xfea1060) multiplies
                    // recorder seconds by 1000 before writing this integer field.
                    DARPutNumber(model,@"setDuration:",floor(duration*1000.0));
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
