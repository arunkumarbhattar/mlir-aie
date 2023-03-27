//===- simple.mlir ---------------------------------------------*- MLIR -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// (c) Copyright 2021 Xilinx Inc.
//
//===----------------------------------------------------------------------===//

// RUN: not aie-opt --aie-assign-buffer-addresses %s |& FileCheck %s
// CHECK:   error: 'AIE.tile' op allocated buffers exceeded available memory
// CHECK:   (stack) : 0x0-0x3FF     (1024 bytes)
// CHECK:   b       : 0x400-0x83FF         (32768 bytes)
// CHECK:   c       : 0x8400-0x841F         (32 bytes)
// CHECK:   a       : 0x8420-0x842F         (16 bytes)

module @test {
 AIE.device(xcvc1902) {
  %0 = AIE.tile(3, 3)
  %b1 = AIE.buffer(%0) { sym_name = "a" } : memref<16xi8>
  %1 = AIE.buffer(%0) { sym_name = "b" } : memref<8192xi32>
  %b2 = AIE.buffer(%0) { sym_name = "c" } : memref<16xi16>
  %3 = AIE.tile(4, 4)
  %4 = AIE.buffer(%3) : memref<500xi32>
 }
}
