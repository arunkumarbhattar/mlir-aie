//===- aie.mlir ------------------------------------------------*- MLIR -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// (c) Copyright 2021 Xilinx Inc.
//
//===----------------------------------------------------------------------===//

// RUN: aiecc.py --no-unified %s
// RUN: aiecc.py --unified    %s

module @test00_itsalive {
  AIE.device(xcve2802) {
    %tile12 = AIE.tile(1, 3)

    %buf12_0 = AIE.buffer(%tile12) { sym_name = "a", address = 0 } : memref<256xi32>

    %core12 = AIE.core(%tile12) {
      %val1 = arith.constant 1 : i32
      %idx1 = arith.constant 3 : index
      %2 = arith.addi %val1, %val1 : i32
      AIE.end
    }
  }
}