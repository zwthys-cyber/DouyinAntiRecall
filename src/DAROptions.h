#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *const DAROptionAntiRecall;
FOUNDATION_EXPORT NSString *const DAROptionBadge;
FOUNDATION_EXPORT NSString *const DAROptionIP;
FOUNDATION_EXPORT NSString *const DAROptionAudioLibrary;
FOUNDATION_EXPORT NSString *const DAROptionCommentAudio;
FOUNDATION_EXPORT NSString *const DAROptionImages;
FOUNDATION_EXPORT NSString *const DAROptionCommentImages;
FOUNDATION_EXPORT NSString *const DAROptionManualAudioDuration;
FOUNDATION_EXPORT NSNotificationName const DAROptionsDidChange;
FOUNDATION_EXPORT BOOL DAROptionEnabled(NSString *key);
FOUNDATION_EXPORT void DARSetOption(NSString *key, BOOL enabled);
