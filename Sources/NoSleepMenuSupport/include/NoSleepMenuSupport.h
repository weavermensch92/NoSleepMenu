#ifndef NoSleepMenuSupport_h
#define NoSleepMenuSupport_h

#include <stdbool.h>

bool NoSleepKeyboardBrightnessIsAvailable(void);
double NoSleepKeyboardBrightnessGet(void);
bool NoSleepKeyboardBrightnessSet(double brightness);
bool NoSleepExternalDisplayIsConnected(void);
bool NoSleepBuiltInDisplaySetEnabled(bool enabled);
double NoSleepBuiltInDisplayBrightnessGet(void);
bool NoSleepBuiltInDisplayBrightnessSet(double brightness);
double NoSleepSystemOutputVolumeGet(void);
bool NoSleepSystemOutputVolumeSet(double volume);
bool NoSleepPauseMediaPlayback(void);

#endif
