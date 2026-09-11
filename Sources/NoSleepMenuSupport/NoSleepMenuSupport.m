#import "NoSleepMenuSupport.h"

#import <CoreAudio/CoreAudio.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>
#import <math.h>
#import <objc/message.h>

static CGDirectDisplayID NoSleepBuiltInDisplayID(void);

static id NoSleepKeyboardClient(void) {
    static id client = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreBrightness.framework"];
        [bundle load];

        Class clientClass = NSClassFromString(@"KeyboardBrightnessClient");
        if (clientClass != Nil) {
            client = [[clientClass alloc] init];
        }
    });

    return client;
}

static void *NoSleepDisplayServices(void) {
    static void *displayServices = NULL;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        displayServices = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        );
    });

    return displayServices;
}

static bool NoSleepDisplayServicesGetBrightness(double *brightness) {
    typedef int (*CanChangeBrightnessFunction)(CGDirectDisplayID);
    typedef int (*GetBrightnessFunction)(CGDirectDisplayID, float *);

    if (brightness == NULL) {
        return false;
    }

    void *displayServices = NoSleepDisplayServices();
    if (displayServices == NULL) {
        return false;
    }

    CanChangeBrightnessFunction canChangeBrightness =
        (CanChangeBrightnessFunction)dlsym(displayServices, "DisplayServicesCanChangeBrightness");
    GetBrightnessFunction getBrightness =
        (GetBrightnessFunction)dlsym(displayServices, "DisplayServicesGetBrightness");

    if (canChangeBrightness == NULL || getBrightness == NULL) {
        return false;
    }

    CGDirectDisplayID displayID = NoSleepBuiltInDisplayID();
    if (displayID == kCGNullDirectDisplay || canChangeBrightness(displayID) == 0) {
        return false;
    }

    float value = -1;
    if (getBrightness(displayID, &value) != 0 || !isfinite(value)) {
        return false;
    }

    *brightness = fmax(0.0, fmin(1.0, (double)value));
    return true;
}

static bool NoSleepDisplayServicesSetBrightness(double brightness) {
    typedef int (*CanChangeBrightnessFunction)(CGDirectDisplayID);
    typedef int (*SetBrightnessFunction)(CGDirectDisplayID, float);

    void *displayServices = NoSleepDisplayServices();
    if (displayServices == NULL) {
        return false;
    }

    CanChangeBrightnessFunction canChangeBrightness =
        (CanChangeBrightnessFunction)dlsym(displayServices, "DisplayServicesCanChangeBrightness");
    SetBrightnessFunction setBrightness =
        (SetBrightnessFunction)dlsym(displayServices, "DisplayServicesSetBrightness");

    if (canChangeBrightness == NULL || setBrightness == NULL) {
        return false;
    }

    CGDirectDisplayID displayID = NoSleepBuiltInDisplayID();
    if (displayID == kCGNullDirectDisplay || canChangeBrightness(displayID) == 0) {
        return false;
    }

    double clampedBrightness = fmax(0.0, fmin(1.0, brightness));
    return setBrightness(displayID, (float)clampedBrightness) == 0;
}

static uint64_t NoSleepKeyboardID(id client) {
    SEL selector = NSSelectorFromString(@"copyKeyboardBacklightIDs");
    if (client == nil || ![client respondsToSelector:selector]) {
        return 0;
    }

    NSArray *keyboardIDs = ((NSArray *(*)(id, SEL))objc_msgSend)(client, selector);
    NSNumber *keyboardID = keyboardIDs.firstObject;
    return keyboardID.unsignedLongLongValue;
}

bool NoSleepKeyboardBrightnessIsAvailable(void) {
    id client = NoSleepKeyboardClient();
    return NoSleepKeyboardID(client) != 0;
}

double NoSleepKeyboardBrightnessGet(void) {
    id client = NoSleepKeyboardClient();
    uint64_t keyboardID = NoSleepKeyboardID(client);
    SEL selector = NSSelectorFromString(@"brightnessForKeyboard:");

    if (keyboardID == 0 || ![client respondsToSelector:selector]) {
        return -1;
    }

    float brightness = ((float (*)(id, SEL, uint64_t))objc_msgSend)(client, selector, keyboardID);
    return (double)brightness;
}

bool NoSleepKeyboardBrightnessSet(double brightness) {
    id client = NoSleepKeyboardClient();
    uint64_t keyboardID = NoSleepKeyboardID(client);

    if (keyboardID == 0) {
        return false;
    }

    float clampedBrightness = (float)fmax(0.0, fmin(1.0, brightness));
    SEL fadeSelector = NSSelectorFromString(@"setBrightness:fadeSpeed:commit:forKeyboard:");

    if ([client respondsToSelector:fadeSelector]) {
        return ((BOOL (*)(id, SEL, float, int, BOOL, uint64_t))objc_msgSend)(
            client,
            fadeSelector,
            clampedBrightness,
            0,
            YES,
            keyboardID
        );
    }

    SEL selector = NSSelectorFromString(@"setBrightness:forKeyboard:");
    if (![client respondsToSelector:selector]) {
        return false;
    }

    return ((BOOL (*)(id, SEL, float, uint64_t))objc_msgSend)(client, selector, clampedBrightness, keyboardID);
}

static bool NoSleepGetDisplays(CGDirectDisplayID displays[], uint32_t maxDisplays, uint32_t *displayCount) {
    CGError error = CGGetOnlineDisplayList(maxDisplays, displays, displayCount);
    return error == kCGErrorSuccess;
}

static CGDirectDisplayID NoSleepBuiltInDisplayID(void) {
    CGDirectDisplayID displays[16];
    uint32_t displayCount = 0;

    if (!NoSleepGetDisplays(displays, 16, &displayCount)) {
        return kCGNullDirectDisplay;
    }

    for (uint32_t index = 0; index < displayCount; index += 1) {
        CGDirectDisplayID displayID = displays[index];
        if (CGDisplayIsBuiltin(displayID)) {
            return displayID;
        }
    }

    return kCGNullDirectDisplay;
}

static CGDirectDisplayID NoSleepFirstExternalDisplayID(void) {
    CGDirectDisplayID displays[16];
    uint32_t displayCount = 0;

    if (!NoSleepGetDisplays(displays, 16, &displayCount)) {
        return kCGNullDirectDisplay;
    }

    for (uint32_t index = 0; index < displayCount; index += 1) {
        CGDirectDisplayID displayID = displays[index];
        if (!CGDisplayIsBuiltin(displayID)) {
            return displayID;
        }
    }

    return kCGNullDirectDisplay;
}

bool NoSleepExternalDisplayIsConnected(void) {
    CGDirectDisplayID displays[16];
    uint32_t displayCount = 0;

    if (!NoSleepGetDisplays(displays, 16, &displayCount)) {
        return false;
    }

    for (uint32_t index = 0; index < displayCount; index += 1) {
        if (!CGDisplayIsBuiltin(displays[index])) {
            return true;
        }
    }

    return false;
}

bool NoSleepBuiltInDisplaySetEnabled(bool enabled) {
    typedef CGError (*ConfigureDisplayEnabledFunction)(CGDisplayConfigRef, CGDirectDisplayID, boolean_t);

    CGDirectDisplayID builtInDisplayID = NoSleepBuiltInDisplayID();
    if (builtInDisplayID == kCGNullDirectDisplay) {
        return false;
    }

    CGDirectDisplayID externalDisplayID = NoSleepFirstExternalDisplayID();
    if (!enabled && externalDisplayID == kCGNullDirectDisplay) {
        return false;
    }

    ConfigureDisplayEnabledFunction configureDisplayEnabled =
        (ConfigureDisplayEnabledFunction)dlsym(RTLD_DEFAULT, "CGSConfigureDisplayEnabled");

    if (configureDisplayEnabled == NULL) {
        void *coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
        if (coreGraphics != NULL) {
            configureDisplayEnabled = (ConfigureDisplayEnabledFunction)dlsym(coreGraphics, "CGSConfigureDisplayEnabled");
        }
    }

    if (configureDisplayEnabled == NULL) {
        return false;
    }

    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error != kCGErrorSuccess || config == NULL) {
        return false;
    }

    if (externalDisplayID != kCGNullDirectDisplay) {
        configureDisplayEnabled(config, externalDisplayID, true);
        CGConfigureDisplayMirrorOfDisplay(config, externalDisplayID, kCGNullDirectDisplay);
        CGConfigureDisplayOrigin(config, externalDisplayID, 0, 0);
    }

    if (enabled) {
        CGConfigureDisplayMirrorOfDisplay(config, builtInDisplayID, kCGNullDirectDisplay);
    }

    error = configureDisplayEnabled(config, builtInDisplayID, enabled ? true : false);
    if (error != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        return false;
    }

    error = CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
    return error == kCGErrorSuccess;
}

double NoSleepBuiltInDisplayBrightnessGet(void) {
    double displayServicesBrightness = -1;
    if (NoSleepDisplayServicesGetBrightness(&displayServicesBrightness)) {
        return displayServicesBrightness;
    }

    return -1;
}

bool NoSleepBuiltInDisplayBrightnessSet(double brightness) {
    double clampedBrightness = fmax(0.0, fmin(1.0, brightness));
    return NoSleepDisplayServicesSetBrightness(clampedBrightness);
}

static AudioObjectID NoSleepDefaultOutputDevice(void) {
    AudioObjectID deviceID = kAudioObjectUnknown;
    UInt32 dataSize = sizeof(deviceID);
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    OSStatus status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address,
        0,
        NULL,
        &dataSize,
        &deviceID
    );

    if (status != noErr) {
        return kAudioObjectUnknown;
    }

    return deviceID;
}

static bool NoSleepOutputVolumeGetForElement(
    AudioObjectID deviceID,
    AudioObjectPropertyElement element,
    Float32 *volume
) {
    if (volume == NULL || deviceID == kAudioObjectUnknown) {
        return false;
    }

    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyVolumeScalar,
        kAudioDevicePropertyScopeOutput,
        element
    };

    if (!AudioObjectHasProperty(deviceID, &address)) {
        return false;
    }

    Float32 value = 0;
    UInt32 dataSize = sizeof(value);
    OSStatus status = AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &dataSize, &value);
    if (status != noErr || !isfinite(value)) {
        return false;
    }

    *volume = fmaxf(0.0f, fminf(1.0f, value));
    return true;
}

static bool NoSleepOutputVolumeSetForElement(
    AudioObjectID deviceID,
    AudioObjectPropertyElement element,
    Float32 volume
) {
    if (deviceID == kAudioObjectUnknown) {
        return false;
    }

    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyVolumeScalar,
        kAudioDevicePropertyScopeOutput,
        element
    };

    if (!AudioObjectHasProperty(deviceID, &address)) {
        return false;
    }

    Float32 clampedVolume = fmaxf(0.0f, fminf(1.0f, volume));
    OSStatus status = AudioObjectSetPropertyData(deviceID, &address, 0, NULL, sizeof(clampedVolume), &clampedVolume);
    return status == noErr;
}

double NoSleepSystemOutputVolumeGet(void) {
    AudioObjectID deviceID = NoSleepDefaultOutputDevice();
    Float32 volume = 0;

    if (NoSleepOutputVolumeGetForElement(deviceID, kAudioObjectPropertyElementMain, &volume)) {
        return (double)volume;
    }

    Float32 leftVolume = 0;
    Float32 rightVolume = 0;
    bool hasLeft = NoSleepOutputVolumeGetForElement(deviceID, 1, &leftVolume);
    bool hasRight = NoSleepOutputVolumeGetForElement(deviceID, 2, &rightVolume);

    if (hasLeft && hasRight) {
        return (double)((leftVolume + rightVolume) / 2.0f);
    }

    if (hasLeft) {
        return (double)leftVolume;
    }

    if (hasRight) {
        return (double)rightVolume;
    }

    return -1;
}

bool NoSleepSystemOutputVolumeSet(double volume) {
    AudioObjectID deviceID = NoSleepDefaultOutputDevice();
    Float32 clampedVolume = (Float32)fmax(0.0, fmin(1.0, volume));

    if (NoSleepOutputVolumeSetForElement(deviceID, kAudioObjectPropertyElementMain, clampedVolume)) {
        return true;
    }

    bool setLeft = NoSleepOutputVolumeSetForElement(deviceID, 1, clampedVolume);
    bool setRight = NoSleepOutputVolumeSetForElement(deviceID, 2, clampedVolume);
    return setLeft || setRight;
}

bool NoSleepPauseMediaPlayback(void) {
    typedef Boolean (*SendCommandFunction)(unsigned int, CFDictionaryRef);

    void *mediaRemote = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY
    );

    if (mediaRemote == NULL) {
        return false;
    }

    SendCommandFunction sendCommand =
        (SendCommandFunction)dlsym(mediaRemote, "MRMediaRemoteSendCommand");

    if (sendCommand == NULL) {
        return false;
    }

    return sendCommand(1, NULL);
}
