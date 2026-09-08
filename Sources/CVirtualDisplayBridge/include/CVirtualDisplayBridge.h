#ifndef CVirtualDisplayBridge_h
#define CVirtualDisplayBridge_h

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *DMXVirtualDisplayRef;

bool DMXVirtualDisplayIsSupported(void);

DMXVirtualDisplayRef _Nullable DMXVirtualDisplayCreate(
  const char * _Nonnull name,
  size_t nativeWidth,
  size_t nativeHeight,
  size_t logicalWidth,
  size_t logicalHeight,
  double refreshRate,
  uint32_t vendorID,
  uint32_t productID,
  uint32_t serialNumber,
  char * _Nullable errorBuffer,
  size_t errorBufferLength
);

CGDirectDisplayID DMXVirtualDisplayGetDisplayID(DMXVirtualDisplayRef _Nonnull display);
void DMXVirtualDisplayRelease(DMXVirtualDisplayRef _Nullable display);

#ifdef __cplusplus
}
#endif

#endif
