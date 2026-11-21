#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
FOUNDATION_EXPORT NSString *DARAudioExtensionForDownload(NSURL *url, NSString *MIMEType);
@interface DARAudioLibrary : NSObject
+ (instancetype)shared;
- (instancetype)initWithDirectory:(NSURL *)directory;
@property(nonatomic, readonly) NSURL *directory;
@property(nonatomic, readonly) BOOL armed;
@property(nonatomic, readonly) NSTimeInterval preparedDuration;
- (NSArray<NSURL *> *)files;
- (NSURL *)importFile:(NSURL *)source name:(NSString *)name error:(NSError **)error;
- (void)download:(NSURL *)source name:(NSString *)name completion:(void(^)(NSError *error))completion;
- (BOOL)removeFile:(NSURL *)file error:(NSError **)error;
- (void)prepareFile:(NSURL *)file completion:(void(^)(NSError *error))completion;
- (void)cancelPending;
- (BOOL)replaceCommentRecording:(NSURL *)recording error:(NSError **)error;
@end
