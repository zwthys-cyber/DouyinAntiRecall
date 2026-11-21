#import "DARCache.h"
#import <TargetConditionals.h>
#include <float.h>

static const NSUInteger DARMaxEntries = 1000;
static const NSUInteger DARMaxBytes = 8 * 1024 * 1024;
static const NSUInteger DARMaxEntryBytes = 64 * 1024;

@implementation DARCache {
    NSURL *_url;
    NSLock *_lock;
    NSMutableDictionary *_entries;
    NSUInteger _bytes;
    BOOL _scheduled;
    dispatch_queue_t _writer;
}
+ (instancetype)shared {
    static DARCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *base = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                            inDomains:NSUserDomainMask] firstObject];
        cache = [[self alloc] initWithURL:[[base URLByAppendingPathComponent:@"DouyinAntiRecall" isDirectory:YES]
                                           URLByAppendingPathComponent:@"messages.json"]];
    });
    return cache;
}
- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        _url = url;
        _lock = [NSLock new];
        _writer = dispatch_queue_create("local.douyin.antirecall.cache", DISPATCH_QUEUE_SERIAL);
        _entries = [NSMutableDictionary new];
        NSNumber *fileSize;
        [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL];
        if (fileSize.unsignedLongLongValue <= 12 * 1024 * 1024) {
            NSData *data = [NSData dataWithContentsOfURL:url];
            id records = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if ([records isKindOfClass:NSDictionary.class]) {
                for (NSString *key in records) {
                    id entry = records[key];
                    if (![entry isKindOfClass:NSDictionary.class] ||
                        ![entry[@"content"] isKindOfClass:NSDictionary.class] ||
                        ![entry[@"time"] isKindOfClass:NSNumber.class]) continue;
                    [self storeContent:entry[@"content"] forKey:key];
                }
            }
        }
    }
    return self;
}
- (NSDictionary *)contentForKey:(NSString *)key {
    [_lock lock];
    NSDictionary *value = _entries[key][@"content"];
    [_lock unlock];
    return value;
}
- (void)storeContent:(NSDictionary *)content forKey:(NSString *)key {
    if (!key.length || !content.count || ![NSJSONSerialization isValidJSONObject:content]) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:content options:0 error:NULL];
    if (!data.length || data.length > DARMaxEntryBytes || key.length > 4096) return;
    // JSON round trip also detaches nested mutable app objects from our cache.
    NSDictionary *frozen = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    [_lock lock];
    if ([_entries[key][@"content"] isEqual:frozen]) { [_lock unlock]; return; }
    _bytes -= [_entries[key][@"bytes"] unsignedIntegerValue];
    _entries[key] = @{@"content": frozen, @"time": @([NSDate timeIntervalSinceReferenceDate]),
                      @"bytes": @(data.length)};
    _bytes += data.length;
    while (_entries.count > DARMaxEntries || _bytes > DARMaxBytes) {
        NSString *oldest;
        double time = DBL_MAX;
        for (NSString *candidate in _entries) {
            double t = [_entries[candidate][@"time"] doubleValue];
            if (t < time) { time = t; oldest = candidate; }
        }
        if (!oldest) break;
        _bytes -= [_entries[oldest][@"bytes"] unsignedIntegerValue];
        [_entries removeObjectForKey:oldest];
    }
    if (!_scheduled) {
        _scheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), _writer, ^{ [self flush]; });
    }
    [_lock unlock];
}
- (void)flush {
    // Serialize writes even when tests explicitly flush from another thread.
    @synchronized (self) {
        [_lock lock];
        NSDictionary *snapshot = [_entries copy];
        _scheduled = NO;
        [_lock unlock];
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
        NSURL *directory = [_url URLByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES
                                                  attributes:nil error:NULL];
        [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
        if (data) {
            NSDataWritingOptions options = NSDataWritingAtomic;
#if TARGET_OS_IPHONE
            options |= NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
            [data writeToURL:_url options:options error:NULL];
        }
    }
}
@end
