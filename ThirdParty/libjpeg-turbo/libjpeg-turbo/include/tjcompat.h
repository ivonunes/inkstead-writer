/* Local shim, not part of upstream libjpeg-turbo. tj3Init became a
 * version-checking macro in libjpeg-turbo 3.2, and Swift cannot import
 * function-like macros; routing the call through a C function keeps the Swift
 * wrapper working on either side of that change. */
#ifndef TJCOMPAT_H
#define TJCOMPAT_H

#include "turbojpeg.h"

static inline tjhandle tjInitCompat(int initType)
{
  return tj3Init(initType);
}

#endif
