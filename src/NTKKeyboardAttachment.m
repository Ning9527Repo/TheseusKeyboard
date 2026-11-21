// Copyright 2026 Ning. New keyboard integration, no historical project code.
// Experimental: native backdrop capture requires iOS 17.2.1 runtime testing.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <os/log.h>
#import <objc/message.h>
#import <unistd.h>
#import "NTKRuntime.h"

void NTKRecordStage(const char *stage);

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

uint64_t NTKNowMS(void) {
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&timebase); });
    long double milliseconds = (long double)mach_continuous_time() * timebase.numer / timebase.denom / 1000000.0L;
    return (uint64_t)milliseconds;
}

static NSString *NTKClientName(NSString *bundle, NSString *prefix) {
    if (![bundle isKindOfClass:NSString.class] || !bundle.length || bundle.length > 180) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                              @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
    if ([bundle rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return nil;
    return [prefix stringByAppendingFormat:@".%@", bundle];
}
NSString *NTKClientLeaseName(NSString *bundle) { return NTKClientName(bundle, @NTK_LEASE_NAME); }
NSString *NTKClientAckName(NSString *bundle) { return NTKClientName(bundle, @NTK_ACK_NAME); }
static BOOL NTKWindowIsRemoteKeyboard(UIWindow *window) {
    if (!window) return NO;
    Class remote = NSClassFromString(@"UIRemoteKeyboardWindow");
    if (remote && [window isKindOfClass:remote]) return YES;
    SEL selector = NSSelectorFromString(@"_isRemoteKeyboardWindow");
    if (![window respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [window methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != 'c') return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(window, selector);
}

BOOL NTKHasKeyboardRuntimeObjects(void) {
    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (NTKWindowIsRemoteKeyboard(window)) return YES;
        }
    }
    Class keyboardClass = NSClassFromString(@"UIKeyboardImpl");
    SEL active = NSSelectorFromString(@"activeInstance");
    if (keyboardClass && [keyboardClass respondsToSelector:active]) {
        NSMethodSignature *signature = [keyboardClass methodSignatureForSelector:active];
        if (signature && signature.numberOfArguments == 2 && signature.methodReturnType[0] == '@') {
            id instance = ((id (*)(id, SEL))objc_msgSend)(keyboardClass, active);
            if (instance && [instance respondsToSelector:NSSelectorFromString(@"_remoteAppId")]) return YES;
        }
    }
    return NO;
}

BOOL NTKIsKeyboardProcess(void) {
    NSString *name = NSProcessInfo.processInfo.processName.lowercaseString;
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    NSString *executable = [NSBundle.mainBundle.infoDictionary[@"CFBundleExecutable"] lowercaseString];
    NSString *bundlePath = NSBundle.mainBundle.bundlePath.lowercaseString;
    // Do not infer from UIKit class registration alone: ordinary apps share it.
    // The service identity, InputUI path, or a live remote-keyboard window is required.
    if ([identifier isEqualToString:@"com.apple.inputui"] ||
        [name isEqualToString:@"inputui"] || [name isEqualToString:@"inputservice"] ||
        [name containsString:@"keyboardservice"] || [executable isEqualToString:@"inputui"] ||
        [bundlePath hasSuffix:@"/inputui.app"] || [bundlePath containsString:@"/inputui.app/"]) return YES;
    return NTKHasKeyboardRuntimeObjects();
}

static void NTKRecordProcessIdentity(void) {
    NSString *line = [NSString stringWithFormat:@"identity process=%@ bundle=%@ executable=%@ path=%@",
                      NSProcessInfo.processInfo.processName ?: @"?",
                      NSBundle.mainBundle.bundleIdentifier ?: @"?",
                      NSBundle.mainBundle.infoDictionary[@"CFBundleExecutable"] ?: @"?",
                      NSBundle.mainBundle.bundlePath ?: @"?"];
    NTKRecordStage(line.UTF8String);
}

void NTKRecordStage(const char *stage) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.ning.theseuskeyboard", "lifecycle"); });
    os_log_info(log, "%{public}s", stage ?: "unknown");
    // Bounded per-process lifecycle trace; contains no pixels, text, app id or user data.
    static NSString *tracePath;
    static NSMutableArray<NSString *> *entries;
    static NSMutableSet<NSString *> *seen;
    @synchronized(NSProcessInfo.processInfo) {
        if (!entries) {
            entries = [NSMutableArray new]; seen = [NSMutableSet new];
            tracePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"theseus-keyboard-%d.log", getpid()]];
        }
        NSString *entry = [NSString stringWithUTF8String:stage ?: "unknown"];
        if ([seen containsObject:entry] || entries.count >= 48) return;
        [seen addObject:entry];
        [entries addObject:[NSString stringWithFormat:@"%llu %@", (unsigned long long)NTKNowMS(), entry]];
        [[entries componentsJoinedByString:@"\n"] writeToFile:tracePath atomically:YES
                                                   encoding:NSUTF8StringEncoding error:NULL];
    }
}

__attribute__((constructor)) static void NTKLoad(void) {
    NTKRecordStage("dylib-loaded");
    dispatch_async(dispatch_get_main_queue(), ^{
        NTKRecordProcessIdentity();
        // The visible path is local to UIKBBackdropView. Do not create an
        // App-owned UIWindow: remote keyboard composition places it behind us.
        NTKStartNativeBackdrop();
    });
}
