#import "CVirtualDisplayBridge.h"

#import <AppKit/AppKit.h>
#import <objc/message.h>

// The selectors and object graph were independently validated against the
// MIT-licensed DeskPad project by Bastian Andelefski. No private declarations
// escape this runtime-only bridge.

@interface DMXVirtualDisplayBox : NSObject
@property(nonatomic, strong) id display;
@end

@implementation DMXVirtualDisplayBox
@end

static Class DMXClass(NSString *name) {
  return NSClassFromString(name);
}

static void DMXWriteError(char *buffer, size_t length, NSString *message) {
  if (buffer == NULL || length == 0) {
    return;
  }
  const char *utf8 = message.UTF8String ?: "unknown virtual display error";
  snprintf(buffer, length, "%s", utf8);
}

bool DMXVirtualDisplayIsSupported(void) {
  return DMXClass(@"CGVirtualDisplayDescriptor") != Nil
    && DMXClass(@"CGVirtualDisplay") != Nil
    && DMXClass(@"CGVirtualDisplayMode") != Nil
    && DMXClass(@"CGVirtualDisplaySettings") != Nil;
}

DMXVirtualDisplayRef DMXVirtualDisplayCreate(
  const char *name,
  size_t nativeWidth,
  size_t nativeHeight,
  size_t logicalWidth,
  size_t logicalHeight,
  double refreshRate,
  uint32_t vendorID,
  uint32_t productID,
  uint32_t serialNumber,
  char *errorBuffer,
  size_t errorBufferLength
) {
  if (!DMXVirtualDisplayIsSupported()) {
    DMXWriteError(errorBuffer, errorBufferLength, @"CGVirtualDisplay is unavailable on this macOS version");
    return NULL;
  }

  @try {
    Class descriptorClass = DMXClass(@"CGVirtualDisplayDescriptor");
    Class displayClass = DMXClass(@"CGVirtualDisplay");
    Class modeClass = DMXClass(@"CGVirtualDisplayMode");
    Class settingsClass = DMXClass(@"CGVirtualDisplaySettings");

    id descriptor = [[descriptorClass alloc] init];
    [descriptor setValue:[NSString stringWithUTF8String:name ?: "DeskMux Virtual Display"] forKey:@"name"];
    [descriptor setValue:@(nativeWidth) forKey:@"maxPixelsWide"];
    [descriptor setValue:@(nativeHeight) forKey:@"maxPixelsHigh"];
    [descriptor setValue:@(vendorID) forKey:@"vendorID"];
    [descriptor setValue:@(productID) forKey:@"productID"];
    [descriptor setValue:@(serialNumber) forKey:@"serialNum"];

    // A plausible 24-inch 16:10 panel keeps the requested pixel density below
    // WindowServer's virtual-display rejection threshold.
    CGSize millimeters = CGSizeMake(517, 323);
    [descriptor setValue:[NSValue valueWithSize:millimeters] forKey:@"sizeInMillimeters"];
    ((void (*)(id, SEL, dispatch_queue_t))objc_msgSend)(
      descriptor,
      NSSelectorFromString(@"setDispatchQueue:"),
      dispatch_get_main_queue()
    );

    id display = ((id (*)(id, SEL, id))objc_msgSend)(
      [displayClass alloc],
      NSSelectorFromString(@"initWithDescriptor:"),
      descriptor
    );
    if (display == nil) {
      DMXWriteError(errorBuffer, errorBufferLength, @"WindowServer rejected the virtual display descriptor");
      return NULL;
    }

    SEL modeSelector = NSSelectorFromString(@"initWithWidth:height:refreshRate:");
    id nativeMode = ((id (*)(id, SEL, NSUInteger, NSUInteger, CGFloat))objc_msgSend)(
      [modeClass alloc], modeSelector, nativeWidth, nativeHeight, refreshRate
    );
    id logicalMode = ((id (*)(id, SEL, NSUInteger, NSUInteger, CGFloat))objc_msgSend)(
      [modeClass alloc], modeSelector, logicalWidth, logicalHeight, refreshRate
    );
    id settings = [[settingsClass alloc] init];
    [settings setValue:@YES forKey:@"hiDPI"];
    [settings setValue:@[nativeMode, logicalMode] forKey:@"modes"];

    BOOL applied = ((BOOL (*)(id, SEL, id))objc_msgSend)(
      display,
      NSSelectorFromString(@"applySettings:"),
      settings
    );
    if (!applied) {
      DMXWriteError(errorBuffer, errorBufferLength, @"WindowServer rejected the virtual display modes");
      return NULL;
    }

    DMXVirtualDisplayBox *box = [DMXVirtualDisplayBox new];
    box.display = display;
    return (__bridge_retained void *)box;
  } @catch (NSException *exception) {
    DMXWriteError(errorBuffer, errorBufferLength, exception.reason ?: exception.name);
    return NULL;
  }
}

CGDirectDisplayID DMXVirtualDisplayGetDisplayID(DMXVirtualDisplayRef reference) {
  if (reference == NULL) {
    return kCGNullDirectDisplay;
  }
  DMXVirtualDisplayBox *box = (__bridge DMXVirtualDisplayBox *)reference;
  return ((CGDirectDisplayID (*)(id, SEL))objc_msgSend)(
    box.display,
    NSSelectorFromString(@"displayID")
  );
}

void DMXVirtualDisplayRelease(DMXVirtualDisplayRef reference) {
  if (reference != NULL) {
    CFBridgingRelease(reference);
  }
}
