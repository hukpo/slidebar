#include "CSlidebarPrivate.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <pthread.h>
#include <string.h>

// MARK: - Private types (layout used by MultitouchSupport since 10.x)

typedef struct { float x, y; } mt_point;
typedef struct { mt_point position, velocity; } mt_vector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    mt_vector normalized;
    float size;
    int32_t pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    mt_vector absolute;
    int32_t reserved[2];
    float density;
} mt_finger;

_Static_assert(sizeof(mt_finger) == 96, "mt_finger layout changed");

typedef void *MTDeviceRef;
typedef int (*MTContactCallback)(MTDeviceRef, mt_finger *, int, double, int);

typedef CFMutableArrayRef (*fn_MTDeviceCreateList)(void);
typedef void (*fn_MTRegister)(MTDeviceRef, MTContactCallback);
typedef void (*fn_MTDeviceStart)(MTDeviceRef, int);
typedef void (*fn_MTDeviceStop)(MTDeviceRef);
typedef bool (*fn_MTDeviceIsBuiltIn)(MTDeviceRef);
typedef int32_t (*fn_MTDeviceGetDeviceID)(MTDeviceRef, uint64_t *);
typedef int (*fn_MTDeviceGetSensorSurfaceDimensions)(MTDeviceRef, int *, int *);
typedef CFTypeRef (*fn_MTActuatorCreateFromDeviceID)(uint64_t);
typedef int32_t (*fn_MTActuatorOpen)(CFTypeRef);
typedef int32_t (*fn_MTActuatorActuate)(CFTypeRef, int32_t, uint32_t, float, float);

typedef int (*fn_DSGetBrightness)(uint32_t, float *);
typedef int (*fn_DSSetBrightness)(uint32_t, float);

static struct {
    bool loaded;
    void *mt;
    void *ds;
    fn_MTDeviceCreateList createList;
    fn_MTRegister registerCallback;
    fn_MTRegister unregisterCallback;
    fn_MTDeviceStart start;
    fn_MTDeviceStop stop;
    fn_MTDeviceIsBuiltIn isBuiltIn;
    fn_MTDeviceGetDeviceID getDeviceID;
    fn_MTDeviceGetSensorSurfaceDimensions surfaceDimensions;
    fn_MTActuatorCreateFromDeviceID actuatorCreate;
    fn_MTActuatorOpen actuatorOpen;
    fn_MTActuatorActuate actuatorActuate;
    fn_DSGetBrightness getBrightness;
    fn_DSSetBrightness setBrightness;
} api;

static pthread_once_t loadOnce = PTHREAD_ONCE_INIT;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static CFMutableArrayRef devices = NULL;
static SlidebarTouchCallback userCallback = NULL;
static void *userContext = NULL;
static CFTypeRef actuator = NULL;
static bool actuatorTried = false;

static void loadAPI(void) {
    api.mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (api.mt) {
        api.createList = (fn_MTDeviceCreateList)dlsym(api.mt, "MTDeviceCreateList");
        api.registerCallback = (fn_MTRegister)dlsym(api.mt, "MTRegisterContactFrameCallback");
        api.unregisterCallback = (fn_MTRegister)dlsym(api.mt, "MTUnregisterContactFrameCallback");
        api.start = (fn_MTDeviceStart)dlsym(api.mt, "MTDeviceStart");
        api.stop = (fn_MTDeviceStop)dlsym(api.mt, "MTDeviceStop");
        api.isBuiltIn = (fn_MTDeviceIsBuiltIn)dlsym(api.mt, "MTDeviceIsBuiltIn");
        api.getDeviceID = (fn_MTDeviceGetDeviceID)dlsym(api.mt, "MTDeviceGetDeviceID");
        api.surfaceDimensions = (fn_MTDeviceGetSensorSurfaceDimensions)dlsym(api.mt, "MTDeviceGetSensorSurfaceDimensions");
        api.actuatorCreate = (fn_MTActuatorCreateFromDeviceID)dlsym(api.mt, "MTActuatorCreateFromDeviceID");
        api.actuatorOpen = (fn_MTActuatorOpen)dlsym(api.mt, "MTActuatorOpen");
        api.actuatorActuate = (fn_MTActuatorActuate)dlsym(api.mt, "MTActuatorActuate");
    }
    api.ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW);
    if (api.ds) {
        api.getBrightness = (fn_DSGetBrightness)dlsym(api.ds, "DisplayServicesGetBrightness");
        api.setBrightness = (fn_DSSetBrightness)dlsym(api.ds, "DisplayServicesSetBrightness");
    }
    api.loaded = true;
}

static void ensureLoaded(void) { pthread_once(&loadOnce, loadAPI); }

// MARK: - Multitouch

#define BRIM_MAX_TOUCHES 20

static int contactFrame(MTDeviceRef device, mt_finger *fingers, int count, double timestamp, int frame) {
    (void)device; (void)frame;
    SlidebarTouchCallback cb = userCallback;
    if (!cb) return 0;
    SlidebarTouch touches[BRIM_MAX_TOUCHES];
    int n = count < BRIM_MAX_TOUCHES ? count : BRIM_MAX_TOUCHES;
    for (int i = 0; i < n; i++) {
        touches[i].identifier = fingers[i].identifier;
        touches[i].state = fingers[i].state;
        touches[i].x = fingers[i].normalized.position.x;
        touches[i].y = fingers[i].normalized.position.y;
        touches[i].vx = fingers[i].normalized.velocity.x;
        touches[i].vy = fingers[i].normalized.velocity.y;
        touches[i].size = fingers[i].size;
        touches[i].majorAxis = fingers[i].majorAxis;
        touches[i].minorAxis = fingers[i].minorAxis;
    }
    cb(touches, n, timestamp, userContext);
    return 0;
}

bool SlidebarMTAvailable(void) {
    ensureLoaded();
    return api.createList && api.registerCallback && api.start;
}

static void stopLocked(void) {
    if (!devices) return;
    CFIndex n = CFArrayGetCount(devices);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        if (api.unregisterCallback) api.unregisterCallback(dev, contactFrame);
        if (api.stop) api.stop(dev);
    }
    CFRelease(devices);
    devices = NULL;
}

int32_t SlidebarMTStart(SlidebarTouchCallback callback, void *context) {
    if (!SlidebarMTAvailable()) return 0;
    pthread_mutex_lock(&lock);
    stopLocked();
    userCallback = callback;
    userContext = context;
    devices = api.createList();
    int32_t count = 0;
    if (devices) {
        count = (int32_t)CFArrayGetCount(devices);
        for (CFIndex i = 0; i < count; i++) {
            MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
            api.registerCallback(dev, contactFrame);
            api.start(dev, 0);
        }
    }
    pthread_mutex_unlock(&lock);
    return count;
}

double SlidebarMTSurfaceAspect(void) {
    if (!api.loaded || !api.surfaceDimensions) return 0;
    double aspect = 0;
    pthread_mutex_lock(&lock);
    CFIndex n = devices ? CFArrayGetCount(devices) : 0;
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        int w = 0, h = 0;
        if (api.surfaceDimensions(dev, &w, &h) != 0 || w <= 0 || h <= 0) continue;
        bool builtIn = api.isBuiltIn && api.isBuiltIn(dev);
        if (aspect == 0 || builtIn) aspect = (double)w / h;
        if (builtIn) break;
    }
    pthread_mutex_unlock(&lock);
    return aspect;
}

void SlidebarMTStop(void) {
    if (!api.loaded) return;
    pthread_mutex_lock(&lock);
    stopLocked();
    pthread_mutex_unlock(&lock);
}

// MARK: - Haptics

static void prepareActuatorLocked(void) {
    if (actuatorTried) return;
    actuatorTried = true;
    if (!api.actuatorCreate || !api.actuatorOpen || !api.actuatorActuate || !api.getDeviceID) return;

    CFMutableArrayRef list = api.createList ? api.createList() : NULL;
    if (!list) return;
    CFIndex n = CFArrayGetCount(list);
    // Prefer the built-in trackpad, then anything with an actuator.
    for (int pass = 0; pass < 2 && !actuator; pass++) {
        for (CFIndex i = 0; i < n && !actuator; i++) {
            MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
            bool builtIn = api.isBuiltIn ? api.isBuiltIn(dev) : false;
            if (pass == 0 && !builtIn) continue;
            uint64_t deviceID = 0;
            if (api.getDeviceID(dev, &deviceID) != 0 || deviceID == 0) continue;
            CFTypeRef act = api.actuatorCreate(deviceID);
            if (!act) continue;
            if (api.actuatorOpen(act) == 0) {
                actuator = act;
            } else {
                CFRelease(act);
            }
        }
    }
    CFRelease(list);
}

bool SlidebarHapticActuate(int32_t actuationID) {
    ensureLoaded();
    pthread_mutex_lock(&lock);
    prepareActuatorLocked();
    bool ok = false;
    if (actuator) ok = api.actuatorActuate(actuator, actuationID, 0, 0.0f, 0.0f) == 0;
    pthread_mutex_unlock(&lock);
    return ok;
}

// MARK: - Brightness

bool SlidebarGetBrightness(uint32_t displayID, float *outValue) {
    ensureLoaded();
    if (!api.getBrightness || !outValue) return false;
    return api.getBrightness(displayID, outValue) == 0;
}

bool SlidebarSetBrightness(uint32_t displayID, float value) {
    ensureLoaded();
    if (!api.setBrightness) return false;
    if (value < 0) value = 0;
    if (value > 1) value = 1;
    return api.setBrightness(displayID, value) == 0;
}

// MARK: - Windows

typedef int32_t (*fn_SLSMainConnectionID)(void);
typedef CFArrayRef (*fn_SLSCopySpacesForWindows)(int32_t, int32_t, CFArrayRef);
typedef CGError (*fn_SLPSSetFrontProcessWithOptions)(ProcessSerialNumber *, uint32_t, uint32_t);
typedef CGError (*fn_SLPSPostEventRecordTo)(ProcessSerialNumber *, uint8_t *);

static struct {
    fn_SLSMainConnectionID mainConnection;
    fn_SLSCopySpacesForWindows spacesForWindows;
    fn_SLPSSetFrontProcessWithOptions setFrontProcess;
    fn_SLPSPostEventRecordTo postEventRecord;
} sky;
static pthread_once_t skyOnce = PTHREAD_ONCE_INIT;

static void loadSkyLight(void) {
    void *sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW);
    if (!sl) return;
    sky.mainConnection = (fn_SLSMainConnectionID)dlsym(sl, "SLSMainConnectionID");
    sky.spacesForWindows = (fn_SLSCopySpacesForWindows)dlsym(sl, "SLSCopySpacesForWindows");
    sky.setFrontProcess = (fn_SLPSSetFrontProcessWithOptions)dlsym(sl, "_SLPSSetFrontProcessWithOptions");
    sky.postEventRecord = (fn_SLPSPostEventRecordTo)dlsym(sl, "SLPSPostEventRecordTo");
}

/// The app's frontmost ordinary window that's on a desktop, or 0.
static uint32_t frontWindowOf(pid_t pid) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!list) return 0;
    uint32_t found = 0;
    int32_t connection = sky.mainConnection();
    for (CFIndex i = 0; i < CFArrayGetCount(list) && !found; i++) {  // front to back
        CFDictionaryRef w = CFArrayGetValueAtIndex(list, i);
        int owner = 0, layer = -1;
        uint32_t number = 0;
        CGRect bounds = CGRectZero;
        CFNumberGetValue(CFDictionaryGetValue(w, kCGWindowOwnerPID), kCFNumberIntType, &owner);
        CFNumberGetValue(CFDictionaryGetValue(w, kCGWindowLayer), kCFNumberIntType, &layer);
        CFNumberGetValue(CFDictionaryGetValue(w, kCGWindowNumber), kCFNumberIntType, &number);
        CGRectMakeWithDictionaryRepresentation(CFDictionaryGetValue(w, kCGWindowBounds), &bounds);
        if (owner != pid || layer != 0 || bounds.size.height < 100) continue;
        CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &number);
        CFArrayRef ids = CFArrayCreate(NULL, (const void **)&n, 1, &kCFTypeArrayCallBacks);
        CFArrayRef spaces = sky.spacesForWindows(connection, 7, ids);
        if (spaces) {
            if (CFArrayGetCount(spaces) > 0) found = number;
            CFRelease(spaces);
        }
        CFRelease(ids);
        CFRelease(n);
    }
    CFRelease(list);
    return found;
}

bool SlidebarFocusFrontWindow(int32_t pid) {
    pthread_once(&skyOnce, loadSkyLight);
    if (!sky.mainConnection || !sky.spacesForWindows || !sky.setFrontProcess || !sky.postEventRecord) return false;
    uint32_t window = frontWindowOf(pid);
    if (!window) return false;
    ProcessSerialNumber psn;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (GetProcessForPID(pid, &psn) != noErr) return false;
#pragma clang diagnostic pop
    sky.setFrontProcess(&psn, window, 0x200);  // kCPSUserGenerated
    // Make it the key window: a press and release record addressed to the window.
    for (uint8_t kind = 1; kind <= 2; kind++) {
        uint8_t record[0xf8] = { 0 };
        record[0x04] = 0xf8;
        record[0x08] = kind;
        record[0x3a] = 0x10;
        memset(record + 0x20, 0xff, 0x10);
        memcpy(record + 0x3c, &window, sizeof window);
        sky.postEventRecord(&psn, record);
    }
    return true;
}
