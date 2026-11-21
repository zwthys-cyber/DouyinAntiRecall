#import <Foundation/Foundation.h>

// A plugin-local display flag on a copied SDK model, never on the server model.
FOUNDATION_EXPORT NSString *const DARRecallStatusKey;
FOUNDATION_EXPORT BOOL DARHasRecallBadge(id message);
FOUNDATION_EXPORT BOOL DARInstallBadgeHooks(void);
