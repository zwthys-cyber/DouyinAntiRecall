#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>
#import "DARCache.h"
#import "DARBadge.h"
#include <string.h>

// Deliberately scoped to the metadata in AwemeCore 41.2.0 / 412021.
// No Substrate, libhooker, writable code pages, network requests, or database patches.
static void (*DAROriginalApply)(id, SEL, id);
static os_log_t DARLog;

static BOOL DARSignature(id object, SEL selector, const char *result, NSUInteger count) {
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != count) return NO;
    char type[128];
    method_getReturnType(method, type, sizeof(type));
    return strcmp(type, result) == 0;
}
static id DARObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!DARSignature(object, selector, "@", 2)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static long long DARInteger(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!DARSignature(object, selector, "q", 2)) return 0;
    return ((long long (*)(id, SEL))objc_msgSend)(object, selector);
}
static BOOL DARObjectSetter(id object, NSString *name, id value) {
    SEL selector = NSSelectorFromString(name);
    if (!DARSignature(object, selector, "v", 3)) return NO;
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    char arg[128];
    method_getArgumentType(method, 2, arg, sizeof(arg));
    if (strcmp(arg, "@") != 0) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
    return YES;
}
static long long DARAccountID(id message) {
    id value = DARObject(DARObject(message, @"db"), @"userID");
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class])
        return [value longLongValue];
    return 0;
}
static BOOL DARRecalled(NSDictionary *ext) {
    id value = ext[@"s:is_recalled"];
    return ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) && [value boolValue];
}
NSString *const DARRecallStatusKey = @"dar_retained_recall_v2";
BOOL DARHasRecallBadge(id message) {
    id ext = DARObject(message, @"syncedExt");
    if (![ext isKindOfClass:NSDictionary.class]) return NO;
    id value = ext[DARRecallStatusKey];
    return ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) && [value boolValue];
}
static NSString *DARKey(long long account, id model) {
    id conversation = DARObject(model, @"belongingConversationIdentifier");
    id identifier = DARObject(model, @"identifier");
    if (![conversation isKindOfClass:NSString.class] || ![conversation length] ||
        ![identifier isKindOfClass:NSString.class] || ![identifier length]) return nil;
    // JSON array avoids delimiter collisions and isolates accounts and conversations.
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[@(account), conversation, identifier]
                                                  options:0 error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
static id DARPrepareModel(id message, id model) {
    long long account = DARAccountID(message);
    long long sender = DARInteger(model, @"sender");
    // Fail open for unknown account/sender and preserve the normal outgoing path.
    if (account <= 0 || sender <= 0 || sender == account) return model;
    id ext = DARObject(model, @"extDictionary");
    id content = DARObject(model, @"contentDictionary");
    if (![ext isKindOfClass:NSDictionary.class]) return model;
    NSString *key = DARKey(account, model);
    if (!key) return model;
    if (!DARRecalled(ext)) {
        if ([content isKindOfClass:NSDictionary.class]) [[DARCache shared] storeContent:content forKey:key];
        return model;
    }
    id recaller = ext[@"s:recall_uid"];
    if (([recaller isKindOfClass:NSString.class] || [recaller isKindOfClass:NSNumber.class]) &&
        [recaller longLongValue] == account) return model;
    NSDictionary *saved = [[DARCache shared] contentForKey:key];
    // Without a prior snapshot, only retain content still present in the incoming model.
    NSDictionary *original = saved ?: ([content isKindOfClass:NSDictionary.class] ? content : nil);
    if (!original.count) return model;
    if (![model conformsToProtocol:@protocol(NSCopying)]) return model;
    id copy = [model copy];
    if (!copy || copy == model) return model;
    NSMutableDictionary *clean = [ext mutableCopy];
    [clean removeObjectsForKeys:@[@"s:is_recalled", @"s:recall_role", @"s:recall_uid"]];
    clean[DARRecallStatusKey] = @"1";
    if (!DARObjectSetter(copy, @"setExtDictionary:", clean) ||
        !DARObjectSetter(copy, @"setContentDictionary:", original)) return model;
    os_log_info(DARLog, "Retained incoming recalled message locally");
    return copy;
}
static void DARApply(id self, SEL command, id model) {
    id prepared = model;
    @try { prepared = DARPrepareModel(self, model); }
    @catch (__unused NSException *exception) {
        os_log_error(DARLog, "Message preparation failed; forwarding original model");
    }
    // Never catch and retry the original: it may already have emitted notifications.
    DAROriginalApply(self, command, prepared);
}
static BOOL DARInstall(void) {
    if (DAROriginalApply) return YES;
    Class cls = objc_getClass("TIMXOMessage");
    SEL selector = NSSelectorFromString(@"applyLogicWithModel_DouYin:");
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char type[128], arg[128];
    method_getReturnType(method, type, sizeof(type));
    method_getArgumentType(method, 2, arg, sizeof(arg));
    if (strcmp(type, "v") || strcmp(arg, "@")) return NO;
    // Add a local method when inherited, avoiding any modification of a superclass.
    IMP previous = method_getImplementation(method);
    DAROriginalApply = (void (*)(id, SEL, id))previous;
    if (!class_addMethod(cls, selector, (IMP)DARApply, method_getTypeEncoding(method)))
        method_setImplementation(method, (IMP)DARApply);
    os_log_info(DARLog, "Installed Douyin 41.2.0 message conversion hook");
    return YES;
}
#ifdef DAR_TESTING
BOOL DARInstallForTesting(void) {
    DARLog = os_log_create("local.douyin.antirecall", "test");
    return DARInstall();
}
#else
__attribute__((constructor)) static void DARInitialize(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        if (![bundle.bundleIdentifier isEqualToString:@"com.ss.iphone.ugc.Aweme"]) return;
        DARLog = os_log_create("local.douyin.antirecall", "plugin");
        if (![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqualToString:@"41.2.0"] ||
            ![[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqualToString:@"412021"]) {
            os_log_error(DARLog, "Unsupported Douyin build; hook disabled");
            return;
        }
        // Constructors can run before all ObjC classes have registered. Retry on main queue.
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL messageReady = DARInstall();
            BOOL badgeReady = DARInstallBadgeHooks();
            if (messageReady && badgeReady) return;
            for (int seconds = 1; seconds <= 10; seconds++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, seconds * NSEC_PER_SEC),
                               dispatch_get_main_queue(), ^{
                                   (void)DARInstall();
                                   (void)DARInstallBadgeHooks();
                               });
            }
        });
    }
}
#endif
