// Thin C layer over private macOS frameworks (MultitouchSupport, DisplayServices).
// Everything is loaded at runtime with dlopen, so a missing symbol degrades gracefully.

#pragma once

#include <stdbool.h>
#include <stdint.h>

// A single finger on a trackpad, in normalized coordinates.
// x: 0 = left edge, 1 = right edge. y: 0 = bottom edge, 1 = top edge.
typedef struct {
    int32_t identifier;
    int32_t state;
    float x, y;
    float vx, vy;
    float size;
    // Contact ellipse. A fingertip is about 6-10 across; a palm is much longer.
    float majorAxis, minorAxis;
} SlidebarTouch;

typedef void (*SlidebarTouchCallback)(const SlidebarTouch *touches, int32_t count, double timestamp, void *context);

// MARK: Multitouch (MultitouchSupport.framework)

/// True when the private multitouch framework could be loaded.
bool SlidebarMTAvailable(void);
/// Starts listening on every trackpad. Returns the number of devices found.
/// The callback runs on a private framework thread.
int32_t SlidebarMTStart(SlidebarTouchCallback callback, void *context);
/// Stops listening on all trackpads.
void SlidebarMTStop(void);
/// Width over height of the trackpad being listened to (the built-in one if there is one),
/// or 0 when unknown. Call after SlidebarMTStart.
double SlidebarMTSurfaceAspect(void);

// MARK: Haptics (MTActuator)

/// Fires the Force Touch actuator of the built-in trackpad. Returns false if unavailable.
bool SlidebarHapticActuate(int32_t actuationID);

// MARK: Display brightness (DisplayServices.framework)

bool SlidebarGetBrightness(uint32_t displayID, float *outValue);
bool SlidebarSetBrightness(uint32_t displayID, float value);
