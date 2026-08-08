#import "GYSyncFormatNegotiation.h"

GYSyncFormatMode GYNextSyncFormatMode(GYSyncFormatMode currentMode,
                                      BOOL requestedV4,
                                      NSInteger httpStatusCode,
                                      BOOL responseParsesAsV4Shape,
                                      BOOL responseParsesAsV3Shape) {
  if (!requestedV4) return currentMode;
  if (httpStatusCode != 200) return currentMode;
  if (responseParsesAsV4Shape) return GYSyncFormatV4Confirmed;
  if (responseParsesAsV3Shape) return GYSyncFormatV3Only;
  return currentMode;
}
