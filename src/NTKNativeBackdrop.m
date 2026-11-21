#import "NTKRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <notify.h>
#import <stdatomic.h>

@interface NTKNativeState : NSObject
@property(nonatomic, strong) UIVisualEffect *effect;
@property(nonatomic, strong) UIColor *color;
@property(nonatomic) BOOL replaced;
@end
@implementation NTKNativeState
@end

static char kNTKNativeKey;
static NSHashTable<UIVisualEffectView *> *gNTKBackdrops;
static dispatch_source_t gNTKNativeTimer;
static int gNTKLeaseToken = -1, gNTKAckToken = -1;
static NSString *gNTKClient, *gNTKAckName;
static BOOL gNTKInstalled, gNTKNativeMutating;
static NSUInteger gNTKStyleDepth;
static atomic_bool gNTKInstallQueued;
static void (*gNTKLayoutOrig)(id, SEL);
static void (*gNTKMoveOrig)(id, SEL);
static void (*gNTKStyleOrig)(id, SEL, NSInteger);
static void (*gNTKEffectOrig)(id, SEL, UIVisualEffect *);
static void (*gNTKColorOrig)(id, SEL, UIColor *);

static BOOL NTKWriteNativeAck(uint64_t state) {
    return gNTKAckToken >= 0 && notify_set_state(gNTKAckToken, state) == NOTIFY_STATUS_OK &&
        notify_post(gNTKAckName.UTF8String) == NOTIFY_STATUS_OK;
}

static BOOL NTKBackdropSupported(UIVisualEffectView *backdrop) {
    UIWindow *window = backdrop.window;
    if (!window || window.hidden || backdrop.hidden || backdrop.alpha < 0.99 ||
        window.screen != UIScreen.mainScreen) return NO;
    CGRect rect = [backdrop convertRect:backdrop.bounds toView:window];
    rect = [window convertRect:rect toCoordinateSpace:window.screen.coordinateSpace];
    CGRect screen = window.screen.bounds;
    return NTKDockedRegion(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
                          screen.size.width, screen.size.height);
}

static void NTKRestoreBackdrop(UIVisualEffectView *view, NTKNativeState *state) {
    if (!state.replaced) return;
    gNTKNativeMutating = YES;
    @try {
        view.effect = state.effect;
        view.backgroundColor = state.color;
        state.replaced = NO;
    } @finally { gNTKNativeMutating = NO; }
    NTKRecordStage("native-restored");
}

static BOOL NTKRefreshBackdrop(UIVisualEffectView *view, uint64_t lease, uint64_t now) {
    NTKNativeState *state = objc_getAssociatedObject(view, &kNTKNativeKey);
    if (!state) {
        state = [NTKNativeState new];
        objc_setAssociatedObject(view, &kNTKNativeKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gNTKBackdrops addObject:view];
    }
    if (!NTKLeaseIsFresh(lease, now) || !NTKBackdropSupported(view)) {
        NTKRestoreBackdrop(view, state);
        return NO;
    }
    if (!state.replaced) {
        state.effect = view.effect;
        state.color = view.backgroundColor;
        state.replaced = YES;
        NTKRecordStage("native-ready-lease-received");
    }
    gNTKNativeMutating = YES;
    @try {
        // Only the backdrop's material. Never hide a view or change contentView/keys.
        if (view.effect) view.effect = nil;
        if (![view.backgroundColor isEqual:UIColor.clearColor]) view.backgroundColor = UIColor.clearColor;
    } @finally { gNTKNativeMutating = NO; }
    return YES;
}

static id NTKObjectGetter(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString *NTKCurrentKeyboardClient(void) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"InputUI"])
        return NTKClientLeaseName(NSBundle.mainBundle.bundleIdentifier) ? NSBundle.mainBundle.bundleIdentifier : nil;
    // Public iOS17 runtime header declares activeInstance and _remoteAppId.
    // Missing or changed ABI disables native clearing; never guess another client.
    id keyboard = NTKObjectGetter(NSClassFromString(@"UIKeyboardImpl"), NSSelectorFromString(@"activeInstance"));
    id client = NTKObjectGetter(keyboard, NSSelectorFromString(@"_remoteAppId"));
    return NTKClientLeaseName(client) ? client : nil;
}

static void NTKRefreshAllNative(void);

static BOOL NTKSelectClient(NSString *client) {
    if (client && [client isEqual:gNTKClient] && gNTKLeaseToken >= 0 && gNTKAckToken >= 0) return YES;
    for (UIVisualEffectView *view in gNTKBackdrops.allObjects)
        NTKRestoreBackdrop(view, objc_getAssociatedObject(view, &kNTKNativeKey));
    NTKWriteNativeAck(0);
    if (gNTKLeaseToken >= 0) notify_cancel(gNTKLeaseToken);
    if (gNTKAckToken >= 0) notify_cancel(gNTKAckToken);
    gNTKLeaseToken = gNTKAckToken = -1; gNTKClient = nil; gNTKAckName = nil;
    NSString *leaseName = NTKClientLeaseName(client), *ackName = NTKClientAckName(client);
    if (!leaseName || !ackName) { NTKRecordStage("native-input-client-unavailable"); return NO; }
    if (notify_register_check(ackName.UTF8String, &gNTKAckToken) != NOTIFY_STATUS_OK) {
        gNTKAckToken = -1; return NO;
    }
    if (notify_register_dispatch(leaseName.UTF8String, &gNTKLeaseToken, dispatch_get_main_queue(),
        ^(int token) { if (token == gNTKLeaseToken) NTKRefreshAllNative(); }) != NOTIFY_STATUS_OK) {
        notify_cancel(gNTKAckToken); gNTKLeaseToken = gNTKAckToken = -1; return NO;
    }
    gNTKClient = [client copy]; gNTKAckName = ackName;
    return YES;
}

static void NTKRefreshAllNative(void) {
    if (![NSThread isMainThread] || gNTKNativeMutating || gNTKStyleDepth) return;
    uint64_t now = NTKNowMS(), lease = 0;
    BOOL clientReady = NTKSelectClient(NTKCurrentKeyboardClient());
    if (!clientReady || gNTKLeaseToken < 0 || notify_get_state(gNTKLeaseToken, &lease) != NOTIFY_STATUS_OK) lease = 0;
    BOOL any = NO;
    for (UIVisualEffectView *view in gNTKBackdrops.allObjects) {
        any |= NTKRefreshBackdrop(view, lease, now);
    }
    if (any) {
        uint64_t ack = NTKMakeLease(now, (uint32_t)NTKLeaseOwner(lease));
        if (!NTKWriteNativeAck(ack)) {
            for (UIVisualEffectView *view in gNTKBackdrops.allObjects)
                NTKRestoreBackdrop(view, objc_getAssociatedObject(view, &kNTKNativeKey));
            NTKRecordStage("native-ack-failed-restored");
        }
        if (!gNTKNativeTimer) {
            gNTKNativeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(gNTKNativeTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 200),
                                     NSEC_PER_MSEC * 200, NSEC_PER_MSEC * 30);
            dispatch_source_set_event_handler(gNTKNativeTimer, ^{ NTKRefreshAllNative(); });
            dispatch_resume(gNTKNativeTimer);
        }
    } else if (gNTKNativeTimer) {
        dispatch_source_cancel(gNTKNativeTimer);
        gNTKNativeTimer = nil;
        NTKWriteNativeAck(0);
    }
}

static void NTKObserveBackdrop(UIVisualEffectView *view) {
    if (![NSThread isMainThread] || gNTKNativeMutating || gNTKStyleDepth) return;
    [gNTKBackdrops addObject:view];
    NTKRefreshAllNative();
}

static void NTKNativeLayout(id self, SEL cmd) {
    if (gNTKLayoutOrig) gNTKLayoutOrig(self, cmd);
    NTKObserveBackdrop(self);
}
static void NTKNativeMove(id self, SEL cmd) {
    if (gNTKMoveOrig) gNTKMoveOrig(self, cmd);
    NTKObserveBackdrop(self);
}
static void NTKNativeStyle(id self, SEL cmd, NSInteger style) {
    if (gNTKNativeMutating) {
        if (gNTKStyleOrig) gNTKStyleOrig(self, cmd, style);
        return;
    }
    ++gNTKStyleDepth;
    @try {
        NTKRestoreBackdrop(self, objc_getAssociatedObject(self, &kNTKNativeKey));
        if (gNTKStyleOrig) gNTKStyleOrig(self, cmd, style);
    } @finally { --gNTKStyleDepth; }
    NTKObserveBackdrop(self);
}
static void NTKNativeEffect(id self, SEL cmd, UIVisualEffect *effect) {
    NTKNativeState *state = objc_getAssociatedObject(self, &kNTKNativeKey);
    if (state.replaced && !gNTKNativeMutating) state.effect = effect;
    if (gNTKEffectOrig) gNTKEffectOrig(self, cmd, effect);
    if (!gNTKNativeMutating) NTKObserveBackdrop(self);
}
static void NTKNativeColor(id self, SEL cmd, UIColor *color) {
    NTKNativeState *state = objc_getAssociatedObject(self, &kNTKNativeKey);
    if (state.replaced && !gNTKNativeMutating) state.color = color;
    if (gNTKColorOrig) gNTKColorOrig(self, cmd, color);
    if (!gNTKNativeMutating) NTKObserveBackdrop(self);
}

static BOOL NTKVoidMethod(Class cls, SEL selector, NSUInteger arguments, const char *argument) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    return sig && sig.numberOfArguments == arguments && strcmp(sig.methodReturnType, @encode(void)) == 0 &&
        (!argument || strcmp([sig getArgumentTypeAtIndex:2], argument) == 0);
}

static void NTKReplaceLocal(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method inherited = class_getInstanceMethod(cls, selector);
    IMP current = method_getImplementation(inherited);
    // Materialize an override when inherited; never change UIVisualEffectView/UIView globally.
    if (class_addMethod(cls, selector, replacement, method_getTypeEncoding(inherited))) {
        *original = current;
    } else {
        *original = method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    }
}

static void NTKDiscoverBackdrops(UIView *root, Class cls) {
    if ([root isKindOfClass:cls]) [gNTKBackdrops addObject:(UIVisualEffectView *)root];
    for (UIView *view in root.subviews) NTKDiscoverBackdrops(view, cls);
}

static void NTKTryInstallBackdrop(void) {
    if (gNTKInstalled) return;
    Class cls = NSClassFromString(@"UIKBBackdropView");
    if (!cls || ![cls isSubclassOfClass:UIVisualEffectView.class]) {
        NTKRecordStage("native-waiting-for-backdrop-class"); return;
    }
    if (!NTKVoidMethod(cls, @selector(layoutSubviews), 2, NULL) ||
        !NTKVoidMethod(cls, @selector(didMoveToWindow), 2, NULL) ||
        !NTKVoidMethod(cls, @selector(setEffect:), 3, @encode(id)) ||
        !NTKVoidMethod(cls, @selector(setBackgroundColor:), 3, @encode(id))) {
        NTKRecordStage("native-hook-abi-rejected"); return;
    }
    gNTKInstalled = YES; // All retries/late image callbacks stop before replacing orig slots.
    NTKReplaceLocal(cls, @selector(layoutSubviews), (IMP)NTKNativeLayout, (IMP *)&gNTKLayoutOrig);
    NTKReplaceLocal(cls, @selector(didMoveToWindow), (IMP)NTKNativeMove, (IMP *)&gNTKMoveOrig);
    NTKReplaceLocal(cls, @selector(setEffect:), (IMP)NTKNativeEffect, (IMP *)&gNTKEffectOrig);
    NTKReplaceLocal(cls, @selector(setBackgroundColor:), (IMP)NTKNativeColor, (IMP *)&gNTKColorOrig);
    SEL style = NSSelectorFromString(@"transitionToStyle:");
    if (NTKVoidMethod(cls, style, 3, @encode(NSInteger)))
        NTKReplaceLocal(cls, style, (IMP)NTKNativeStyle, (IMP *)&gNTKStyleOrig);
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) NTKDiscoverBackdrops(window, cls);
    }
    NTKRefreshAllNative();
    NTKRecordStage("native-hooks-installed");
}

static void NTKImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    if (atomic_exchange(&gNTKInstallQueued, true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        atomic_store(&gNTKInstallQueued, false);
        NTKTryInstallBackdrop();
    });
}

void NTKStartNativeBackdrop(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Native UIKBBackdropView mutation belongs only to the keyboard service.
        // App processes load the same dylib solely for the content-window renderer.
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"InputUI"]) return;
        gNTKBackdrops = [NSHashTable weakObjectsHashTable];
        _dyld_register_func_for_add_image(NTKImageAdded);
        NTKTryInstallBackdrop();
    });
}
