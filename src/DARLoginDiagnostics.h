#import <UIKit/UIKit.h>
FOUNDATION_EXPORT BOOL DARInstallLoginDiagnostics(void);
FOUNDATION_EXPORT void DARStartLoginDiagnostics(BOOL allowObservation);
FOUNDATION_EXPORT NSString *DARLoginDiagnosticReport(void);
FOUNDATION_EXPORT NSDictionary *DARDiagnosticEntitlements(NSData *executable);
FOUNDATION_EXPORT void DAROpenLoginDiagnostics(UIViewController *presenter);
