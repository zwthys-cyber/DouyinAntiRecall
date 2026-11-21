#import "DARBadge.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#include <math.h>

static char DARBadgeAssociation;
static void (*DAROriginalCellLayout)(id, SEL);
static void (*DAROriginalCellReuse)(id, SEL);
static void (*DAROriginalCellConfig)(id, SEL, id);

static id DARBadgeObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char type[128];
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, "@")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static BOOL DARCellHasBadge(id cell) {
    if (DARHasRecallBadge(DARBadgeObject(cell, @"message"))) return YES;
    id viewModel = DARBadgeObject(cell, @"viewModel");
    return DARHasRecallBadge(DARBadgeObject(viewModel, @"message")) ||
           DARHasRecallBadge(DARBadgeObject(viewModel, @"iesMessage"));
}
static void DARUpdateBadge(UITableViewCell *cell) {
    UILabel *label = objc_getAssociatedObject(cell, &DARBadgeAssociation);
    if (!DARCellHasBadge(cell)) { label.hidden = YES; return; }
    UIView *host = cell.contentView;
    id candidate = DARBadgeObject(cell, @"visibleContentView");
    if (![candidate isKindOfClass:UIView.class] || candidate == cell || candidate == host)
        candidate = DARBadgeObject(cell, @"containerView");
    if (![candidate isKindOfClass:UIView.class] || candidate == cell || candidate == host ||
        ![candidate isDescendantOfView:host] || [candidate isHidden]) {
        label.hidden = YES;
        return;
    }
    UIView *bubble = candidate;
    CGRect bounds = host.bounds;
    CGRect frame = [bubble convertRect:bubble.bounds toView:host];
    if (CGRectIsEmpty(frame) || CGRectIsEmpty(bounds) ||
        !isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
        !isfinite(frame.size.width) || !isfinite(frame.size.height)) {
        label.hidden = YES;
        return;
    }
    if (!label) {
        label = [UILabel new];
        label.text = @"已撤回";
        label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
        label.textColor = UIColor.secondaryLabelColor;
        label.backgroundColor = UIColor.clearColor;
        label.userInteractionEnabled = NO;
        label.accessibilityLabel = @"对方已撤回此消息，原文已保留";
        label.accessibilityIdentifier = @"DouyinAntiRecall.status";
        objc_setAssociatedObject(cell, &DARBadgeAssociation, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addSubview:label];
    }
    [label sizeToFit];
    CGSize size = label.bounds.size;
    CGFloat x = CGRectGetMinX(frame) + 8;
    CGFloat y = CGRectGetMaxY(frame) + 2;
    if (y + size.height > CGRectGetMaxY(bounds) - 2) {
        // Incoming bubbles usually leave horizontal room. Never overlap their text.
        x = CGRectGetMaxX(frame) + 5;
        y = CGRectGetMaxY(frame) - size.height - 1;
        if (x + size.width > CGRectGetMaxX(bounds) - 4) {
            label.hidden = YES;
            return;
        }
    }
    CGRect badge = CGRectMake(x, y, ceil(size.width), ceil(size.height));
    if (!CGRectContainsRect(bounds, badge)) { label.hidden = YES; return; }
    label.frame = badge;
    label.hidden = NO;
    [host bringSubviewToFront:label];
}
static void DARCellLayout(id self, SEL selector) {
    DAROriginalCellLayout(self, selector);
    @try { DARUpdateBadge(self); }
    @catch (__unused NSException *exception) {
        UILabel *label = objc_getAssociatedObject(self, &DARBadgeAssociation);
        label.hidden = YES;
    }
}
static void DARCellReuse(id self, SEL selector) {
    UILabel *label = objc_getAssociatedObject(self, &DARBadgeAssociation);
    label.hidden = YES;
    DAROriginalCellReuse(self, selector);
}
static void DARCellConfig(id self, SEL selector, id message) {
    // Hide before the next layout so a reused cell cannot briefly show stale status.
    UILabel *label = objc_getAssociatedObject(self, &DARBadgeAssociation);
    label.hidden = YES;
    DAROriginalCellConfig(self, selector, message);
    [self setNeedsLayout];
}
static Method DARCellMethod(Class cls, SEL selector, NSUInteger arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != arguments) return NULL;
    char type[128];
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, "v")) return NULL;
    if (arguments == 3) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (strcmp(type, "@")) return NULL;
    }
    return method;
}
static void DARReplaceCellMethod(Class cls, SEL selector, Method method, IMP replacement) {
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)))
        method_setImplementation(method, replacement);
}
BOOL DARInstallBadgeHooks(void) {
    if (DAROriginalCellLayout) return YES;
    Class cls = objc_getClass("AWEIMMessageBaseTableViewCell");
    if (!cls || ![cls isSubclassOfClass:UITableViewCell.class]) return NO;
    SEL layout = @selector(layoutSubviews), reuse = @selector(prepareForReuse);
    SEL config = NSSelectorFromString(@"configWithMessage:");
    Method layoutMethod = DARCellMethod(cls, layout, 2);
    Method reuseMethod = DARCellMethod(cls, reuse, 2);
    Method configMethod = DARCellMethod(cls, config, 3);
    if (!layoutMethod || !reuseMethod || !configMethod) return NO;
    DAROriginalCellLayout = (void (*)(id, SEL))method_getImplementation(layoutMethod);
    DAROriginalCellReuse = (void (*)(id, SEL))method_getImplementation(reuseMethod);
    DAROriginalCellConfig = (void (*)(id, SEL, id))method_getImplementation(configMethod);
    DARReplaceCellMethod(cls, layout, layoutMethod, (IMP)DARCellLayout);
    DARReplaceCellMethod(cls, reuse, reuseMethod, (IMP)DARCellReuse);
    DARReplaceCellMethod(cls, config, configMethod, (IMP)DARCellConfig);
    return YES;
}
