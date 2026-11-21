#import "DARRuntime.h"
#import <objc/message.h>
#include <string.h>
static Method DARMethod(id object, NSString *name, NSUInteger arguments) {
    Method method = class_getInstanceMethod(object_getClass(object), NSSelectorFromString(name));
    return method && method_getNumberOfArguments(method) == arguments ? method : NULL;
}
id DARGet(id object, NSString *name) {
    @try {
        Method m = DARMethod(object, name, 2); if (!m) return nil;
        char type[128]; method_getReturnType(m, type, sizeof(type));
        if (type[0] != '@') return nil;
        return ((id (*)(id,SEL))objc_msgSend)(object, NSSelectorFromString(name));
    } @catch (__unused NSException *e) { return nil; }
}
long long DARNumber(id object, NSString *name) {
    @try {
        Method m = DARMethod(object, name, 2); if (!m) return 0;
        char t[32]; method_getReturnType(m,t,sizeof(t)); SEL s=NSSelectorFromString(name);
        if (!strcmp(t,"q")) return ((long long(*)(id,SEL))objc_msgSend)(object,s);
        if (!strcmp(t,"Q")) return (long long)((unsigned long long(*)(id,SEL))objc_msgSend)(object,s);
        if (!strcmp(t,"B")) return ((BOOL(*)(id,SEL))objc_msgSend)(object,s);
        if (!strcmp(t,"i")) return ((int(*)(id,SEL))objc_msgSend)(object,s);
    } @catch (__unused NSException *e) {}
    return 0;
}
BOOL DARPut(id object, NSString *name, id value) {
    @try {
        Method m=DARMethod(object,name,3); if(!m)return NO;
        char r[16],t[128]; method_getReturnType(m,r,sizeof(r)); method_getArgumentType(m,2,t,sizeof(t));
        if(strcmp(r,"v") || t[0]!='@')return NO;
        ((void(*)(id,SEL,id))objc_msgSend)(object,NSSelectorFromString(name),value); return YES;
    } @catch (__unused NSException *e) { return NO; }
}
BOOL DARPutNumber(id object, NSString *name, double value) {
    @try {
        Method m=DARMethod(object,name,3); if(!m)return NO;
        char r[16],t[32]; method_getReturnType(m,r,sizeof(r)); method_getArgumentType(m,2,t,sizeof(t));
        if(strcmp(r,"v"))return NO; SEL s=NSSelectorFromString(name);
        if(!strcmp(t,"B"))((void(*)(id,SEL,BOOL))objc_msgSend)(object,s,value!=0);
        else if(!strcmp(t,"q"))((void(*)(id,SEL,long long))objc_msgSend)(object,s,(long long)value);
        else if(!strcmp(t,"Q"))((void(*)(id,SEL,unsigned long long))objc_msgSend)(object,s,(unsigned long long)value);
        else if(!strcmp(t,"d"))((void(*)(id,SEL,double))objc_msgSend)(object,s,value);
        else return NO;
        return YES;
    } @catch (__unused NSException *e) { return NO; }
}
BOOL DARHook(Class cls, NSString *name, IMP replacement, IMP *original, const char *result, NSUInteger count) {
    if (*original) return YES;
    SEL selector=NSSelectorFromString(name); Method m=class_getInstanceMethod(cls,selector);
    if(!m || method_getNumberOfArguments(m)!=count)return NO;
    char type[128]; method_getReturnType(m,type,sizeof(type)); if(strcmp(type,result))return NO;
    *original=method_getImplementation(m);
    if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(m)))method_setImplementation(m,replacement);
    return YES;
}
