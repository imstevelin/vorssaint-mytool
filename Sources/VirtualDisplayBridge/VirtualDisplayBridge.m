// Adapted from HiDPIScaler, Copyright (c) 2026 txdadlab, MIT.
// See ThirdParty/HiDPIScaler-LICENSE. Private classes resolved at runtime.
#import "VirtualDisplayBridge.h"
#import <Foundation/Foundation.h>

@interface NSObject (VSDPrivateAPI)
- (id)initWithDescriptor:(id)descriptor;
- (id)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
- (BOOL)applySettings:(id)settings;
- (unsigned int)displayID;
@end

static NSMutableDictionary *ownedDisplays;
bool VSDVirtualDisplayAvailable(void) {
    Class display = NSClassFromString(@"CGVirtualDisplay");
    Class mode = NSClassFromString(@"CGVirtualDisplayMode");
    return display && NSClassFromString(@"CGVirtualDisplayDescriptor") &&
        NSClassFromString(@"CGVirtualDisplaySettings") && mode &&
        [display instancesRespondToSelector:@selector(initWithDescriptor:)] &&
        [display instancesRespondToSelector:@selector(applySettings:)] &&
        [mode instancesRespondToSelector:@selector(initWithWidth:height:refreshRate:)];
}

CGDirectDisplayID VSDCreateVirtualDisplay(uint32_t width, uint32_t height, double rate,
    uint32_t serial, double millimetersWide, double millimetersHigh, const char *name) {
    if (!VSDVirtualDisplayAvailable() || width < 640 || height < 480 ||
        width > 5120 || height > 5120 || (uint64_t)width * height > 14745600 ||
        !isfinite(rate) || rate < 24 || rate > 240) return 0;
    id descriptor = nil, display = nil, settings = nil, mode = nil;
    CGDirectDisplayID result = 0;
    @try {
        descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        [descriptor setValue:[NSString stringWithUTF8String:name ?: "HiDPI"] forKey:@"name"];
        [descriptor setValue:@(width * 2) forKey:@"maxPixelsWide"];
        [descriptor setValue:@(height * 2) forKey:@"maxPixelsHigh"];
        [descriptor setValue:[NSValue valueWithSize:NSMakeSize(width * 2 * 25.4 / 220.0, height * 2 * 25.4 / 220.0)]
                      forKey:@"sizeInMillimeters"];
        [descriptor setValue:@(0xeeee) forKey:@"vendorID"];
        [descriptor setValue:@((width << 16) ^ height ^ 0x1234) forKey:@"productID"];
        [descriptor setValue:@(serial) forKey:@"serialNum"];
        if ([descriptor respondsToSelector:NSSelectorFromString(@"setSerialNumber:")])
            [descriptor setValue:@(serial) forKey:@"serialNumber"];
        // Standard sRGB primaries, required for a usable virtual color profile.
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.64, 0.33)] forKey:@"redPrimary"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.30, 0.60)] forKey:@"greenPrimary"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.15, 0.06)] forKey:@"bluePrimary"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.3127, 0.3290)] forKey:@"whitePoint"];
        [descriptor setValue:dispatch_get_main_queue() forKey:@"queue"];
        display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (display) {
            settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
            [settings setValue:@1 forKey:@"hiDPI"];
            // Advertise the requested 2x pixel mode first; verify the synthesized desktop after mirroring.
            mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                initWithWidth:width * 2 height:height * 2 refreshRate:rate];
            if (mode) {
                // macOS synthesizes the requested Retina mode when the logical
                // base mode precedes its 2x pixel mode. Reversing these can
                // produce only a 1x desktop even though hiDPI is enabled.
                id baseMode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                    initWithWidth:width height:height refreshRate:rate];
                if (baseMode) [settings setValue:@[baseMode, mode] forKey:@"modes"];
                [baseMode release];
            }
            if (mode && [display applySettings:settings]) {
                result = [display displayID];
                if (result) {
                    if (!ownedDisplays) ownedDisplays = [NSMutableDictionary new];
                    ownedDisplays[@(result)] = display;
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Virtual display creation failed: %@", exception.name);
        result = 0;
    } @finally {
        [mode release]; [settings release]; [display release]; [descriptor release];
    }
    return result;
}
void VSDDestroyVirtualDisplay(CGDirectDisplayID display) {
    [ownedDisplays removeObjectForKey:@(display)];
}
