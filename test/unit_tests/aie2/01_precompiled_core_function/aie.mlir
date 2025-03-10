//===- aie.mlir ------------------------------------------------*- MLIR -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// (c) Copyright 2021 Xilinx Inc.
//
//===----------------------------------------------------------------------===//

// RUN: clang --target=aie2 -c %S/kernel.cc
// RUN: aiecc.py %VitisSysrootFlag% --host-target=%aieHostTargetTriplet% %s -I%host_runtime_lib%/test_lib/include -L%host_runtime_lib%/test_lib/lib -ltest_lib %S/test.cpp -o test.elf
// RUN: %run_on_board ./test.elf

// CHECK: PASS!

module @test_chesss_01_precompiled_core_function {
  AIE.device(xcve2802) {
    %tile13 = AIE.tile(1, 3)

    %buf13_0 = AIE.buffer(%tile13) { sym_name = "a" } : memref<256xi32>
    %buf13_1 = AIE.buffer(%tile13) { sym_name = "b" } : memref<256xi32>

    %lock13_3 = AIE.lock(%tile13, 3) { sym_name = "input_lock" }
    %lock13_5 = AIE.lock(%tile13, 5) { sym_name = "output_lock" }

    func.func private @func(%A: memref<256xi32>, %B: memref<256xi32>) -> ()

    %core13 = AIE.core(%tile13) {
      AIE.useLock(%lock13_3, "Acquire", 1) // acquire for read(e.g. input ping)
      AIE.useLock(%lock13_5, "Acquire", 0) // acquire for write
      func.call @func(%buf13_0, %buf13_1) : (memref<256xi32>, memref<256xi32>) -> ()
      AIE.useLock(%lock13_3, "Release", 0) // release for write
      AIE.useLock(%lock13_5, "Release", 1) // release for read
      AIE.end
    } { link_with="kernel.o" }
  }
}
