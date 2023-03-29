//===- threshold.h -------------------------------------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Copyright (C) 2022, Advanced Micro Devices, Inc.
//
//===----------------------------------------------------------------------===//

#ifndef _VITIS_VISION_THRESHOLD_H
#define _VITIS_VISION_THRESHOLD_H

#include <stdint.h>

extern "C" {

void vitis_vision_threshold(int16_t *img_in, int16_t *img_out); 

} // extern "C"

#endif
