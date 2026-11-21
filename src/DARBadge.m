#import "DARBadge.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#include <math.h>

static char DARBadgeAssociation;
static char DARLiveRecallAssociation;
static NSHashTable<UITableViewCell *> *DARBoundCells;
static BOOL DARRefreshingStatus;
static void (*DAROriginalCellLayout)(id, SEL);
static void (*DAROriginalCellReuse)(id, SEL);
static void (*DAROriginalCellConfig)(id, SEL, id);
static void (*DARModernLayout)(id, SEL);
static void (*DARModernReuse)(id, SEL);
static void (*DARModernRender)(id, SEL, id);

static id DARBadgeObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char type[128];
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, "@")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static NSArray *DARCellMessages(id cell) {
    id viewModel = DARBadgeObject(cell, @"viewModel");
    id context = DARBadgeObject(cell, @"currentContext");
    NSMutableArray *messages = [NSMutableArray new];
    for (id candidate in @[
        DARBadgeObject(cell, @"message") ?: NSNull.null,
        DARBadgeObject(viewModel, @"message") ?: NSNull.null,
        DARBadgeObject(viewModel, @"iesMessage") ?: NSNull.null,
        DARBadgeObject(context, @"message") ?: NSNull.null,
        DARBadgeObject(DARBadgeObject(context, @"messageViewModel"), @"message") ?: NSNull.null]) {
        if (candidate != NSNull.null) [messages addObject:candidate];
    }
    return messages;
}
static BOOL DARCellMatchesKey(id cell, NSString *key) {
    for (id message in DARCellMessages(cell))
        if ([DARTrackingKeyForMessage(message) isEqualToString:key]) return YES;
    return NO;
}
static BOOL DARCellHasBadge(id cell) {
    NSString *liveKey = objc_getAssociatedObject(cell, &DARLiveRecallAssociation);
    if (liveKey && DARCellMatchesKey(cell, liveKey)) return YES;
    if (DARHasRecallBadge(DARBadgeObject(cell, @"message"))) return YES;
    id viewModel = DARBadgeObject(cell, @"viewModel");
    if (DARHasRecallBadge(DARBadgeObject(viewModel, @"message")) ||
        DARHasRecallBadge(DARBadgeObject(viewModel, @"iesMessage"))) return YES;
    id context = DARBadgeObject(cell, @"currentContext");
    if (DARHasRecallBadge(DARBadgeObject(context, @"message"))) return YES;
    return DARHasRecallBadge(DARBadgeObject(DARBadgeObject(context, @"messageViewModel"), @"message"));
}
static UIView *DARFindBubble(UIView *host) {
    // Component cells expose their message through currentContext rather than message.
    // Only use known bubble view families; never guess from arbitrary labels or avatars.
    NSMutableArray<UIView *> *pending = [host.subviews mutableCopy];
    UIView *found = nil;
    NSUInteger visited = 0;
    while (pending.count && visited++ < 256) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (view.hidden || view.alpha < 0.01) continue;
        NSString *name = NSStringFromClass(view.class);
        if ([name hasPrefix:@"AWEIMMessageBubble"] || [name isEqualToString:@"AWEIMMessageAnimationBubbleView"]) {
            if (!found || view.bounds.size.width * view.bounds.size.height > found.bounds.size.width * found.bounds.size.height)
                found = view;
        }
        [pending addObjectsFromArray:view.subviews];
    }
    return found;
}
static void DARUpdateBadge(UITableViewCell *cell) {
    [DARBoundCells addObject:cell];
    UILabel *label = objc_getAssociatedObject(cell, &DARBadgeAssociation);
    if (!DARCellHasBadge(cell)) { label.hidden = YES; return; }
    UIView *host = cell.contentView;
    id candidate = DARBadgeObject(cell, @"visibleContentView");
    if (![candidate isKindOfClass:UIView.class] || candidate == cell || candidate == host)
        candidate = DARBadgeObject(cell, @"containerView");
    UIView *knownBubble = DARFindBubble(host);
    if (knownBubble) candidate = knownBubble;
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
    objc_setAssociatedObject(self, &DARLiveRecallAssociation, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UILabel *label = objc_getAssociatedObject(self, &DARBadgeAssociation);
    label.hidden = YES;
    DAROriginalCellReuse(self, selector);
}
static void DARCellConfig(id self, SEL selector, id message) {
    // Hide before the next layout so a reused cell cannot briefly show stale status.
    UILabel *label = objc_getAssociatedObject(self, &DARBadgeAssociation);
    label.hidden = YES;
    DAROriginalCellConfig(self, selector, message);
    [DARBoundCells addObject:self];
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
static BOOL DARInstallLegacyBadgeHooks(void) {
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

static void DARModernCellLayout(id self, SEL selector) {
    DARModernLayout(self, selector);
    @try { DARUpdateBadge(self); }
    @catch (__unused NSException *exception) {
        UILabel *label = objc_getAssociatedObject(self, &DARBadgeAssociation);
        label.hidden = YES;
    }
}
static void DARModernCellReuse(id self, SEL selector) {
    objc_setAssociatedObject(self, &DARLiveRecallAssociation, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UILabel *label = objc_getAssociatedObject(self, &DARBadgeAssociation);
    label.hidden = YES;
    DARModernReuse(self, selector);
}
static void DARModernCellRender(id self, SEL selector, id holder) {
    UILabel *label = objc_getAssociatedObject(self, &DARBadgeAssociation);
    label.hidden = YES;
    DARModernRender(self, selector, holder);
    [DARBoundCells addObject:self];
    [self setNeedsLayout];
}
static BOOL DARInstallModernBadgeHooks(void) {
    if (DARModernLayout) return YES;
    Class cls = objc_getClass("AWEIMReusableCommonCell");
    if (!cls || ![cls isSubclassOfClass:UITableViewCell.class]) return NO;
    SEL layout = @selector(layoutSubviews), reuse = @selector(prepareForReuse);
    SEL render = NSSelectorFromString(@"renderWithHolder:");
    Method lm = DARCellMethod(cls, layout, 2), rm = DARCellMethod(cls, reuse, 2);
    Method cm = DARCellMethod(cls, render, 3);
    if (!lm || !rm || !cm) return NO;
    DARModernLayout = (void (*)(id, SEL))method_getImplementation(lm);
    DARModernReuse = (void (*)(id, SEL))method_getImplementation(rm);
    DARModernRender = (void (*)(id, SEL, id))method_getImplementation(cm);
    DARReplaceCellMethod(cls, layout, lm, (IMP)DARModernCellLayout);
    DARReplaceCellMethod(cls, reuse, rm, (IMP)DARModernCellReuse);
    DARReplaceCellMethod(cls, render, cm, (IMP)DARModernCellRender);
    return YES;
}
BOOL DARInstallBadgeHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DARBoundCells = [NSHashTable weakObjectsHashTable];
        [[NSNotificationCenter defaultCenter] addObserverForName:DARRecallStatusDidChangeNotification
                                                         object:nil queue:nil usingBlock:^(NSNotification *notice) {
            void (^refresh)(void) = ^{
                NSString *key = notice.userInfo[@"key"];
                if (![key isKindOfClass:NSString.class] || !key.length || DARRefreshingStatus) return;
                // Some SDK bridge getters can trigger another model conversion.
                // A nested notice must not recursively refresh the same cells.
                DARRefreshingStatus = YES;
                @try {
                    for (UITableViewCell *cell in DARBoundCells.allObjects) {
                        @try {
                            if (!DARCellMatchesKey(cell, key)) continue;
                            objc_setAssociatedObject(cell, &DARLiveRecallAssociation, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
                            DARUpdateBadge(cell);
                            [cell setNeedsLayout];
                        } @catch (__unused NSException *exception) {
                            // One unsupported presentation object must not abort SDK processing.
                        }
                    }
                } @finally { DARRefreshingStatus = NO; }
            };
            if (NSThread.isMainThread) refresh();
            else dispatch_async(dispatch_get_main_queue(), refresh);
        }];
    });
    BOOL legacy = DARInstallLegacyBadgeHooks();
    BOOL modern = DARInstallModernBadgeHooks();
    return legacy && modern;
}
