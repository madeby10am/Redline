// Private IOKit HID calls used to read Apple Silicon temperature sensors.
#include <CoreFoundation/CoreFoundation.h>

typedef CFTypeRef IOHIDEventSystemClientRef;
typedef CFTypeRef IOHIDServiceClientRef;
typedef CFTypeRef IOHIDEventRef;

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator) CF_RETURNS_RETAINED;
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client) CF_RETURNS_RETAINED;
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp) CF_RETURNS_RETAINED;
CFStringRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property) CF_RETURNS_RETAINED;
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);
