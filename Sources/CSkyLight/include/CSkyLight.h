#ifndef CSKYLIGHT_H
#define CSKYLIGHT_H

#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>

typedef int CGSConnectionID;

CF_IMPLICIT_BRIDGING_ENABLED

CGSConnectionID CGSMainConnectionID(void);
uint64_t CGSGetActiveSpace(CGSConnectionID cid);
CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID cid);
CFStringRef CGSCopyActiveMenuBarDisplayIdentifier(CGSConnectionID cid);
void CGSManagedDisplaySetCurrentSpace(CGSConnectionID cid,
                                      CFStringRef displayIdentifier,
                                      uint64_t spaceID);

CF_IMPLICIT_BRIDGING_DISABLED

/// Switches one space to the left (direction < 0) or right (direction > 0) by
/// posting a synthetic horizontal Dock-swipe gesture with near-zero progress,
/// which makes the WindowServer perform the switch instantly (no slide
/// animation) and — unlike CGSManagedDisplaySetCurrentSpace — through the real
/// compositor path, so the outgoing space is properly replaced. Requires
/// Accessibility permission. Call once per space to move (N times to jump N).
///
/// (x, y) stamps the event's location so the swipe lands on a specific display
/// (use a point inside that display's bounds, in global top-left CG
/// coordinates). Pass NAN for both to leave the gesture on the display under the
/// current cursor.
void MSSSwitchSpaceGesture(int direction, double x, double y);

#endif /* CSKYLIGHT_H */
