// The CGS* symbols are private and resolved at link time against SkyLight.
// MSSSwitchSpaceGesture is our own code: it synthesizes the trackpad "Dock
// swipe" gesture the OS uses to change spaces. The CGEventField raw values and
// type constants below are private (not in any public header) and are set via
// plain integer casts here — they can't be expressed through Swift's closed
// CGEventField enum. Technique mirrors jurplel/InstantSpaceSwitcher.
#include "CSkyLight.h"

#include <CoreGraphics/CoreGraphics.h>
#include <float.h>
#include <math.h>

// Private CGEventField indices observed in real Dock-swipe gesture traces.
static const CGEventField kFieldEventType     = (CGEventField)55;
static const CGEventField kFieldGestureHIDType = (CGEventField)110;
static const CGEventField kFieldSwipeMotion   = (CGEventField)123;
static const CGEventField kFieldSwipeProgress = (CGEventField)124;
static const CGEventField kFieldSwipeVelX     = (CGEventField)129;
static const CGEventField kFieldSwipeVelY     = (CGEventField)130;
static const CGEventField kFieldGesturePhase  = (CGEventField)132;

static const int64_t kEventDockControl   = 30; // CGSEventType: Dock control
static const int64_t kIOHIDDockSwipe     = 23; // IOHIDEventType: dock swipe
static const int64_t kMotionHorizontal   = 1;

// CGSGesturePhase values. All three must be sent or the WindowServer ignores
// the gesture.
static const int64_t kPhaseBegan   = 1;
static const int64_t kPhaseChanged = 2;
static const int64_t kPhaseEnded   = 4;

static const double kGestureVelocity = 2000.0;

static void mss_post_dock_swipe(int64_t phase, int direction, double x, double y) {
    const bool isRight = direction > 0;
    // Pinning progress to the smallest representable float makes the switch
    // instant: the WindowServer treats it as a completed swipe with no slide.
    const double progress = isRight ? (double)FLT_TRUE_MIN : -(double)FLT_TRUE_MIN;
    const double velocity = isRight ? kGestureVelocity : -kGestureVelocity;

    CGEventRef ev = CGEventCreate(NULL);
    if (!ev) return;
    // Stamp the location onto a target display, or leave it at the cursor.
    if (!isnan(x) && !isnan(y)) {
        CGEventSetLocation(ev, CGPointMake(x, y));
    }
    CGEventSetIntegerValueField(ev, kFieldEventType, kEventDockControl);
    CGEventSetIntegerValueField(ev, kFieldGestureHIDType, kIOHIDDockSwipe);
    CGEventSetIntegerValueField(ev, kFieldGesturePhase, phase);
    CGEventSetDoubleValueField(ev, kFieldSwipeProgress, progress);
    CGEventSetIntegerValueField(ev, kFieldSwipeMotion, kMotionHorizontal);
    CGEventSetDoubleValueField(ev, kFieldSwipeVelX, velocity);
    CGEventSetDoubleValueField(ev, kFieldSwipeVelY, velocity);
    CGEventPost(kCGSessionEventTap, ev);
    CFRelease(ev);
}

void MSSSwitchSpaceGesture(int direction, double x, double y) {
    mss_post_dock_swipe(kPhaseBegan, direction, x, y);
    mss_post_dock_swipe(kPhaseChanged, direction, x, y);
    mss_post_dock_swipe(kPhaseEnded, direction, x, y);
}
