#pragma once
#import <UIKit/UIKit.h>
#import "NTKBridge.h"
#import "NTKLeasePolicy.h"

#define NTK_LEASE_NAME "com.ning.theseuskeyboard.surface.v2"
#define NTK_ACK_NAME "com.ning.theseuskeyboard.native.v2"

NSString *NTKClientLeaseName(NSString *bundleIdentifier);
NSString *NTKClientAckName(NSString *bundleIdentifier);
BOOL NTKIsKeyboardProcess(void);
BOOL NTKHasKeyboardRuntimeObjects(void);
void NTKStartAppCoordinator(void);
void NTKStartNativeBackdrop(void);
