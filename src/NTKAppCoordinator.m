#import "NTKRuntime.h"
#import <notify.h>
#import <unistd.h>

@protocol NTKSurface <NSObject>
- (void)attachToBackgroundHost:(UIView *)host sourceWindow:(UIWindow *)source;
- (void)setPresentedHandler:(void (^)(uint64_t capturedAtMS))handler;
- (void)setSuspended:(BOOL)suspended;
- (void)nativeBackgroundDidChange;
- (BOOL)rendererReady;
@end
@protocol NTKSurfaceFactory <NSObject>
+ (UIView<NTKSurface> *)makeSurface;
@end

@interface NTKPassThroughWindow : UIWindow
@end
@implementation NTKPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    (void)point; (void)event; return nil;
}
@end

@interface NTKAppCoordinator : NSObject
@property(nonatomic, strong) NTKPassThroughWindow *overlay;
@property(nonatomic, weak) UIWindow *source;
@property(nonatomic, strong) UIView<NTKSurface> *surface;
@property(nonatomic, strong) UIView *host;
@property(nonatomic, strong) NSMutableArray<UIWindow *> *retiredWindows;
@property(nonatomic, strong) NSTimer *retireTimer;
@property(nonatomic) uint64_t retiredUntilMS;
@property(nonatomic, strong) NSTimer *refreshTimer;
@property(nonatomic) uint64_t generation, beganMS, lastPresentedMS, lastLease;
@property(nonatomic) uint32_t leaseOwner;
@property(nonatomic) CGRect screenFrame;
@property(nonatomic) BOOL running, acknowledged, frameNoticeLogged;
@property(nonatomic, copy) NSString *leaseName, *ackName;
@property(nonatomic) int leaseToken, ackToken;
- (void)stop;
- (void)checkPresentation;
- (void)checkRetiredWindows;
@end

static UIResponder *NTKFindFirstResponder(UIView *view) {
    if (view.isFirstResponder) return view;
    for (UIView *child in view.subviews) {
        UIResponder *found = NTKFindFirstResponder(child);
        if (found) return found;
    }
    return nil;
}

static UIWindow *NTKContentWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (app.applicationState != UIApplicationStateActive) return nil;
    UIWindowScene *activeScene = nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (activeScene) return nil;
        activeScene = (UIWindowScene *)scene;
    }
    if (!activeScene || activeScene.screen != UIScreen.mainScreen) return nil;
    for (UIWindow *window in activeScene.windows) {
        if (!window.keyWindow || window.hidden || window.alpha < 0.99 ||
            window.windowLevel != UIWindowLevelNormal ||
            [window isKindOfClass:NTKPassThroughWindow.class]) continue;
        NSString *name = NSStringFromClass(window.class);
        if ([name containsString:@"Keyboard"] || [name containsString:@"TextEffects"]) continue;
        UIResponder *input = NTKFindFirstResponder(window);
        if (!input) continue;
        if ([input conformsToProtocol:@protocol(UITextInputTraits)] &&
            [input respondsToSelector:@selector(isSecureTextEntry)] &&
            [(id<UITextInputTraits>)input isSecureTextEntry]) return nil;
        return window;
    }
    return nil;
}

@implementation NTKAppCoordinator
- (instancetype)init {
    if ((self = [super init])) {
        _leaseToken = _ackToken = -1;
        _leaseName = NTKClientLeaseName(NSBundle.mainBundle.bundleIdentifier);
        _ackName = NTKClientAckName(NSBundle.mainBundle.bundleIdentifier);
        if (!_leaseName || !_ackName) return nil;
        if (notify_register_check(_leaseName.UTF8String, &_leaseToken) != NOTIFY_STATUS_OK) {
            _leaseToken = -1; return nil;
        }
        __weak NTKAppCoordinator *weakSelf = self;
        if (notify_register_dispatch(_ackName.UTF8String, &_ackToken, dispatch_get_main_queue(),
            ^(int token) { (void)token; [weakSelf checkPresentation]; }) != NOTIFY_STATUS_OK) {
            notify_cancel(_leaseToken); _leaseToken = -1; _ackToken = -1; return nil;
        }
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(keyboardDidChange:) name:UIKeyboardDidChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(keyboardDidChange:) name:UIKeyboardDidShowNotification object:nil];
        for (NSNotificationName name in @[UIKeyboardWillHideNotification, UIApplicationWillResignActiveNotification,
                                         UISceneWillDeactivateNotification])
            [center addObserver:self selector:@selector(invalidate:) name:name object:nil];
    }
    return self;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_refreshTimer invalidate]; [_retireTimer invalidate];
    if (_leaseToken >= 0) notify_cancel(_leaseToken);
    if (_ackToken >= 0) notify_cancel(_ackToken);
}
- (void)invalidate:(NSNotification *)notification { (void)notification; [self stop]; }
- (void)keyboardWillChange:(NSNotification *)note { (void)note; [self stop]; }

- (void)revokeLease {
    uint64_t current = 0;
    if (self.leaseToken >= 0 && notify_get_state(self.leaseToken, &current) == NOTIFY_STATUS_OK &&
        NTKLeaseOwner(current) == self.leaseOwner) {
        if (notify_set_state(self.leaseToken, 0) != NOTIFY_STATUS_OK ||
            notify_post(self.leaseName.UTF8String) != NOTIFY_STATUS_OK)
            NTKRecordStage("lease-revoke-failed-native-will-expire");
    }
    self.lastLease = 0;
}
- (void)stop {
    if (!self.running && !self.overlay) return;
    self.running = NO;
    ++self.generation;
    [self.refreshTimer invalidate]; self.refreshTimer = nil;
    [self revokeLease];
    [self.surface setSuspended:YES];
    // Keep the last glass during the lease restoration bound, then release it.
    // It lives only in this App window and cannot show on the next App.
    if (self.overlay) {
        if (!self.retiredWindows) self.retiredWindows = [NSMutableArray new];
        [self.retiredWindows addObject:self.overlay];
        self.retiredUntilMS = NTKNowMS() + NTK_LEASE_TTL_MS + 250;
        if (!self.retireTimer) {
            __weak NTKAppCoordinator *weakSelf = self;
            self.retireTimer = [NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
                (void)timer; [weakSelf checkRetiredWindows];
            }];
            [NSRunLoop.mainRunLoop addTimer:self.retireTimer forMode:NSRunLoopCommonModes];
        }
    }
    self.surface = nil; self.host = nil; self.overlay = nil; self.source = nil;
    self.acknowledged = NO; self.lastPresentedMS = 0;
    NTKRecordStage("session-stopped");
}

- (void)checkRetiredWindows {
    uint64_t ack = 0;
    BOOL restored = self.ackToken >= 0 && notify_get_state(self.ackToken, &ack) == NOTIFY_STATUS_OK && !ack;
    if (restored || NTKNowMS() >= self.retiredUntilMS) {
        for (UIWindow *window in self.retiredWindows) window.hidden = YES;
        [self.retiredWindows removeAllObjects];
        [self.retireTimer invalidate]; self.retireTimer = nil;
    }
}

- (void)keyboardDidChange:(NSNotification *)note {
    NTKRecordStage("keyboard-frame-notification");
    NSNumber *local = note.userInfo[UIKeyboardIsLocalUserInfoKey];
    if (local && !local.boolValue) { [self stop]; return; }
    NSValue *frameValue = note.userInfo[UIKeyboardFrameEndUserInfoKey];
    if (!frameValue || (note.object && [note.object isKindOfClass:UIScreen.class] && note.object != UIScreen.mainScreen)) {
        [self stop]; return;
    }
    CGRect frame = frameValue.CGRectValue, screen = UIScreen.mainScreen.bounds;
    if (!NTKDockedRegion(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                         screen.size.width, screen.size.height)) {
        [self stop]; NTKRecordStage("keyboard-region-unsupported"); return;
    }
    UIWindow *source = NTKContentWindow();
    if (!source) { [self stop]; NTKRecordStage("content-window-unavailable"); return; }
    if (self.running && self.source == source && CGRectEqualToRect(self.screenFrame, frame)) return;
    [self stop];
    Class factory = NSClassFromString(@"NTKGlassBackground");
    if (!factory || ![factory respondsToSelector:@selector(makeSurface)]) {
        NTKRecordStage("swift-surface-unavailable"); return;
    }
    UIView<NTKSurface> *surface = [(id<NTKSurfaceFactory>)factory makeSurface];
    if (!surface) return;
    NTKPassThroughWindow *overlay = [[NTKPassThroughWindow alloc] initWithWindowScene:source.windowScene];
    overlay.frame = source.windowScene.coordinateSpace.bounds;
    overlay.windowLevel = source.windowLevel + 1;
    overlay.backgroundColor = UIColor.clearColor;
    overlay.opaque = NO;
    overlay.userInteractionEnabled = NO;
    overlay.accessibilityElementsHidden = YES;
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.clearColor;
    overlay.rootViewController = controller;
    overlay.hidden = NO; // Do not make key: preserve the editing App's input ownership.
    CGRect region = [overlay convertRect:frame fromCoordinateSpace:overlay.screen.coordinateSpace];
    UIView *host = [[UIView alloc] initWithFrame:region];
    host.backgroundColor = UIColor.clearColor;
    host.clipsToBounds = YES;
    host.userInteractionEnabled = NO;
    [controller.view addSubview:host];
    self.overlay = overlay; self.host = host; self.surface = surface; self.source = source;
    self.screenFrame = frame; self.running = YES; self.acknowledged = NO;
    self.beganMS = NTKNowMS(); self.lastPresentedMS = 0; self.frameNoticeLogged = NO;
    self.leaseOwner = arc4random_uniform((uint32_t)NTK_LEASE_OWNER_MASK) + 1;
    uint64_t generation = ++self.generation;
    __weak NTKAppCoordinator *weakSelf = self;
    [surface setPresentedHandler:^(uint64_t capturedAtMS) {
        NTKAppCoordinator *owner = weakSelf;
        if (!owner || !owner.running || owner.generation != generation || !owner.source ||
            owner.overlay.hidden || owner.source.windowScene.activationState != UISceneActivationStateForegroundActive)
            return;
        uint64_t now = NTKNowMS();
        if (capturedAtMS < owner.beganMS || now < capturedAtMS ||
            now - capturedAtMS >= NTK_LEASE_TTL_MS || NTKContentWindow() != owner.source) return;
        owner.lastPresentedMS = capturedAtMS;
        if (!owner.frameNoticeLogged) { NTKRecordStage("content-frame-presented"); owner.frameNoticeLogged = YES; }
        uint64_t lease = NTKMakeLease(owner.lastPresentedMS, owner.leaseOwner);
        if (!lease || notify_set_state(owner.leaseToken, lease) != NOTIFY_STATUS_OK ||
            notify_post(owner.leaseName.UTF8String) != NOTIFY_STATUS_OK) {
            NTKRecordStage("lease-publish-failed"); [owner stop]; return;
        }
        owner.lastLease = lease;
    }];
    [surface attachToBackgroundHost:host sourceWindow:source];
    [surface layoutIfNeeded];
    if (![surface rendererReady]) { NTKRecordStage("renderer-unavailable"); [self stop]; return; }
    [surface setSuspended:NO];
    [surface nativeBackgroundDidChange];
    self.refreshTimer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        NTKAppCoordinator *owner = weakSelf;
        if (!owner) return;
        [owner checkPresentation];
        if (owner.running) [owner.surface nativeBackgroundDidChange];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.refreshTimer forMode:NSRunLoopCommonModes];
    NTKRecordStage("content-session-started");
}

- (void)checkPresentation {
    if (!self.running) return;
    if (NTKContentWindow() != self.source) { [self stop]; return; }
    uint64_t now = NTKNowMS();
    uint64_t since = self.lastPresentedMS ?: self.beganMS;
    if (now < since || now - since >= NTK_LEASE_TTL_MS) {
        NTKRecordStage("frame-presentation-timeout"); [self stop]; return;
    }
    uint64_t ack = 0;
    BOOL ackValid = self.ackToken >= 0 && notify_get_state(self.ackToken, &ack) == NOTIFY_STATUS_OK &&
        NTKAckMatches(self.lastLease, ack, self.beganMS, now);
    if (!self.acknowledged && ackValid) {
        self.acknowledged = YES; NTKRecordStage("native-acknowledged");
    }
    if ((self.acknowledged && !ackValid) ||
        (!self.acknowledged && now - self.beganMS > 3000)) {
        NTKRecordStage("native-ack-timeout"); [self stop];
    }
}
@end

void NTKStartAppCoordinator(void) {
    static NTKAppCoordinator *coordinator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *process = NSProcessInfo.processInfo.processName;
        if ([process isEqualToString:@"InputUI"] || [process isEqualToString:@"SpringBoard"] ||
            [NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"appex"] ||
            !NSBundle.mainBundle.infoDictionary[@"CFBundlePackageType"] ||
            ![NSBundle.mainBundle.infoDictionary[@"CFBundlePackageType"] isEqual:@"APPL"]) return;
        coordinator = [NTKAppCoordinator new];
        NTKRecordStage(coordinator ? "content-coordinator-ready" : "content-notify-unavailable");
    });
}
