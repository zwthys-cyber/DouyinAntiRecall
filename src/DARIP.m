// Adapted from DYYY.xm/DYYYUtils.m in ac54u-mobile/Aweme (MIT).
#import "DARFeatures.h"
#import "DARRuntime.h"
#import "DAROptions.h"
#import "DARCityData.h"
static IMP DAROriginalTimestamp, DAROriginalTimestampActive;
static char DARIPBaseText, DARIPLastText;
static NSHashTable *DARIPElements;
NSString *DARLocationForModel(id model) {
    id attribution = DARGet(model,@"ipAttribution");
    NSString *fallback = [attribution isKindOfClass:NSString.class] ?
        [attribution stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    for(NSString *prefix in @[@"IP属地：",@"IP属地:",@"IP 属地：",@"IP 属地:"])
        if([fallback hasPrefix:prefix]) { fallback=[fallback substringFromIndex:prefix.length]; break; }
    id code=DARGet(model,@"cityCode");
    if([code isKindOfClass:NSString.class] && [code length]==6) {
        NSDictionary *cities=DARCityData(); NSString *city=cities[code];
        NSString *province=cities[[[code substringToIndex:2] stringByAppendingString:@"0000"]];
        if(city.length) return province.length && ![city isEqual:province] ? [NSString stringWithFormat:@"%@ %@",province,city] : city;
    }
    return [fallback stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static id DARTimestamp(id self, SEL selector) {
    id result=((id(*)(id,SEL))DAROriginalTimestamp)(self,selector);
    if(!NSThread.isMainThread || ![result isKindOfClass:UILabel.class])return result;
    [DARIPElements addObject:self]; UILabel *label=result;
    NSString *last=objc_getAssociatedObject(label,&DARIPLastText);
    NSString *base=objc_getAssociatedObject(label,&DARIPBaseText);
    if(!last || ![label.text isEqual:last])base=label.text ?: @"";
    objc_setAssociatedObject(label,&DARIPBaseText,base,OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSString *location=DAROptionEnabled(DAROptionIP)?DARLocationForModel(DARGet(self,@"model")):nil;
    NSString *text=base;
    if(location.length) {
        NSRange nativeIP=[base rangeOfString:@"IP属地"];
        if(nativeIP.location!=NSNotFound)base=[[base substringToIndex:nativeIP.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        text=base.length?[NSString stringWithFormat:@"%@  IP属地：%@",base,location]:[NSString stringWithFormat:@"IP属地：%@",location];
    }
    if(![label.text isEqual:text]) { label.text=text; [label invalidateIntrinsicContentSize]; [label.superview setNeedsLayout]; }
    objc_setAssociatedObject(label,&DARIPLastText,text,OBJC_ASSOCIATION_COPY_NONATOMIC);
    return label;
}
static BOOL DARTimestampActive(id self,SEL selector,id data,id context) {
    return DAROptionEnabled(DAROptionIP) || ((BOOL(*)(id,SEL,id,id))DAROriginalTimestampActive)(self,selector,data,context);
}
BOOL DARInstallIPHooks(void) {
    static dispatch_once_t once; dispatch_once(&once,^{
        DARIPElements=[NSHashTable weakObjectsHashTable];
        [[NSNotificationCenter defaultCenter] addObserverForName:DAROptionsDidChange object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
            for(id element in DARIPElements.allObjects)DARTimestamp(element,NSSelectorFromString(@"timestampLabel"));
        }];
    });
    Class cls=NSClassFromString(@"AWEPlayInteractionTimestampElement");
    BOOL a=DARHook(cls,@"timestampLabel",(IMP)DARTimestamp,&DAROriginalTimestamp,"@",2);
    BOOL b=DARHook(object_getClass(cls),@"shouldActiveWithData:context:",(IMP)DARTimestampActive,&DAROriginalTimestampActive,"B",4);
    return a&&b;
}
