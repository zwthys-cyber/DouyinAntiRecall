#import <Foundation/Foundation.h>
#import <objc/runtime.h>
FOUNDATION_EXPORT id DARGet(id object, NSString *selector);
FOUNDATION_EXPORT long long DARNumber(id object, NSString *selector);
FOUNDATION_EXPORT BOOL DARPut(id object, NSString *selector, id value);
FOUNDATION_EXPORT BOOL DARPutNumber(id object, NSString *selector, double value);
FOUNDATION_EXPORT BOOL DARHook(Class cls, NSString *selector, IMP replacement, IMP *original,
                               const char *returnType, NSUInteger arguments);
