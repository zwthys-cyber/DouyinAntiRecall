#import "DAROptions.h"
NSString *const DAROptionAntiRecall = @"DAR.antiRecall";
NSString *const DAROptionBadge = @"DAR.badge";
NSString *const DAROptionIP = @"DAR.ipLocation";
NSString *const DAROptionAudioLibrary = @"DAR.audioLibrary";
NSString *const DAROptionCommentAudio = @"DAR.commentAudio";
NSString *const DAROptionImages = @"DAR.originalImages";
NSNotificationName const DAROptionsDidChange = @"local.douyin.antirecall.options-changed";
BOOL DAROptionEnabled(NSString *key) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    if ([value isKindOfClass:NSNumber.class]) return [value boolValue];
    return [key isEqual:DAROptionAntiRecall] || [key isEqual:DAROptionBadge];
}
void DARSetOption(NSString *key, BOOL enabled) {
    if (![@[DAROptionAntiRecall, DAROptionBadge, DAROptionIP, DAROptionAudioLibrary,
            DAROptionCommentAudio, DAROptionImages] containsObject:key]) return;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:DAROptionsDidChange
                                                      object:nil userInfo:@{@"key": key}];
}
