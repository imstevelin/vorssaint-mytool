#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
bool VSDVirtualDisplayAvailable(void);
CGDirectDisplayID VSDCreateVirtualDisplay(uint32_t width, uint32_t height, double rate,
                                          uint32_t serial, double millimetersWide,
                                          double millimetersHigh, const char *name);
void VSDDestroyVirtualDisplay(CGDirectDisplayID display);
