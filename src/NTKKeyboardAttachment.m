// Copyright 2026 Ning. New keyboard integration, no historical project code.
// Experimental: native backdrop capture requires iOS 17.2.1 runtime testing.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "NTKBridge.h"

const char *NTKResourceDirectory(void) {
    static NSString *directory;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info = {0};
        if (dladdr((const void *)&NTKResourceDirectory, &info) && info.dli_fname) {
            directory = [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
        }
    });
    return directory.fileSystemRepresentation ?: "";
}

static const char kNTKSurfaceKey;
static BOOL gNTKInstalled = NO;
static BOOL gNTKAttaching = NO; // Main-thread capture/layout reentrancy guard.
static void (*gNTKOrigLayout)(id, SEL);
static void (*gNTKOrigMove)(id, SEL);
static void (*gNTKOrigStyle)(id, SEL, long long);

typedef void (*NTKHookMessage)(Class, SEL, IMP, IMP *);

// All static helpers are defined before their first use.
static void NTKUpdateAttachment(UIVisualEffectView *backdrop, BOOL contentChanged) {
    if (![NSThread isMainThread] || gNTKAttaching) return;
    gNTKAttaching = YES;
    @try {
        UIView *surface = objc_getAssociatedObject(backdrop, &kNTKSurfaceKey);
        if (!backdrop.window || backdrop.hidden || backdrop.alpha <= 0.01) {
            if (surface) ((void (*)(id, SEL, BOOL))objc_msgSend)(surface, @selector(setSuspended:), YES);
            return;
        }
        UIView *host = backdrop.contentView;
        BOOL unsafeHost = !host || CGRectIsEmpty(host.bounds);
        // Do not draw over any foreground content. This is a background-only host.
        for (UIView *child in host.subviews) {
            if (child != surface) unsafeHost = YES;
        }
        if (unsafeHost) {
            if (surface) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(surface, @selector(setSuspended:), YES);
                [surface removeFromSuperview];
            }
            return;
        }
        if (!surface) {
            Class surfaceClass = NSClassFromString(@"NTKGlassBackground");
            if (!surfaceClass || ![surfaceClass isSubclassOfClass:[UIView class]]) return;
            surface = [[surfaceClass alloc] initWithFrame:host.bounds];
            if (!surface) return;
            objc_setAssociatedObject(backdrop, &kNTKSurfaceKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            contentChanged = YES;
        }
        if (surface.superview != host || !CGRectEqualToRect(surface.frame, host.bounds)) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(surface,
                @selector(attachToBackgroundHost:sourceView:), host, backdrop);
            contentChanged = YES;
        }
        ((void (*)(id, SEL, BOOL))objc_msgSend)(surface, @selector(setSuspended:), NO);
        if (contentChanged) {
            ((void (*)(id, SEL))objc_msgSend)(surface, @selector(nativeBackgroundDidChange));
        }
    } @finally {
        gNTKAttaching = NO;
    }
}

static void NTKLayout(id self, SEL cmd) {
    if (gNTKOrigLayout) gNTKOrigLayout(self, cmd);
    NTKUpdateAttachment(self, NO);
}

static void NTKMove(id self, SEL cmd) {
    if (gNTKOrigMove) gNTKOrigMove(self, cmd);
    NTKUpdateAttachment(self, YES);
}

static void NTKStyle(id self, SEL cmd, long long style) {
    if (gNTKOrigStyle) gNTKOrigStyle(self, cmd, style);
    NTKUpdateAttachment(self, YES);
}

static void NTKInstall(void) {
    if (gNTKInstalled) return;
    Class cls = NSClassFromString(@"UIKBBackdropView");
    NTKHookMessage hook = (NTKHookMessage)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (!cls || !hook || ![cls isSubclassOfClass:[UIVisualEffectView class]]) return;
    if (!NSClassFromString(@"NTKGlassBackground")) return;
    // Never reinstall and overwrite orig slots with our own wrappers.
    gNTKInstalled = YES;
    hook(cls, @selector(layoutSubviews), (IMP)NTKLayout, (IMP *)&gNTKOrigLayout);
    hook(cls, @selector(didMoveToWindow), (IMP)NTKMove, (IMP *)&gNTKOrigMove);
    SEL transition = NSSelectorFromString(@"transitionToStyle:");
    if (class_getInstanceMethod(cls, transition)) {
        hook(cls, transition, (IMP)NTKStyle, (IMP *)&gNTKOrigStyle);
    }
}

__attribute__((constructor)) static void NTKLoad(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ NTKInstall(); });
}
