#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

// Injectable services keep simulator tests away from real permissions and APNs.
@protocol DARNotificationService <NSObject>
- (void)readState:(void (^)(NSDictionary *state))completion;
- (void)requestPermission:(void (^)(BOOL granted,NSError *error))completion;
- (void)registerRemote;
- (void)scheduleLocalTest:(void (^)(NSError *error))completion;
@end
FOUNDATION_EXPORT NSString *DARPushEnvironment(id value);
FOUNDATION_EXPORT NSString *DARNotificationReport(NSDictionary *state,id environment);
FOUNDATION_EXPORT void DARRepairNotificationAccess(id<DARNotificationService> service,id environment,void (^completion)(NSString *result));
FOUNDATION_EXPORT void DARTestNotificationAccess(id<DARNotificationService> service,void (^completion)(NSString *result));
FOUNDATION_EXPORT void DAROpenNotificationRepair(UIViewController *presenter);
