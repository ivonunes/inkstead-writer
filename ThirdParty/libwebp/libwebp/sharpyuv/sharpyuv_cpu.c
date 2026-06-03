// Copyright 2022 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
#include "sharpyuv/sharpyuv_cpu.h"

// Include src/dsp/cpu.c to create SharpYuvGetCPUInfo from VP8GetCPUInfo. The
// function pointer is renamed in sharpyuv_cpu.h.
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wambiguous-macro"
#endif
#include "src/dsp/cpu.c"
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
