//===- base_test_4.aie.mlir --------------------------*- MLIR -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// (c) Copyright 2021 Xilinx Inc.
//
// Date: June 1st 2022
// 
//===----------------------------------------------------------------------===//

// RUN: aie-opt --aie-register-objectFifos %s | FileCheck %s

// CHECK: module @registerPatterns {
// CHECK:    %0 = AIE.tile(1, 2)
// CHECK:    %1 = AIE.tile(1, 3)
// CHECK:    AIE.objectFifo @objfifo(%0, {%1}, 4 : i32) : !AIE.objectFifo<memref<16xi32>>
// CHECK:    %cst = arith.constant dense<[2, 3, 3, 3, 0]> : tensor<5xi32>
// CHECK:    %cst_0 = arith.constant dense<[0, 1, 1, 2, 1]> : tensor<5xi32>
// CHECK:    %c10 = arith.constant 10 : index
// CHECK:    func.func @producer_work() {
// CHECK:      return
// CHECK:    }
// CHECK:    %2 = AIE.core(%0) {
// CHECK:      %3 = AIE.objectFifo.acquire @objfifo(Produce, 2) : !AIE.objectFifoSubview<memref<16xi32>>
// CHECK:      %4 = AIE.objectFifo.subview.access %3[0] : !AIE.objectFifoSubview<memref<16xi32>> -> memref<16xi32>
// CHECK:      %5 = AIE.objectFifo.subview.access %3[1] : !AIE.objectFifoSubview<memref<16xi32>> -> memref<16xi32>
// CHECK:      func.call @producer_work() : () -> ()
// CHECK:      %c0 = arith.constant 0 : index
// CHECK:      %c2 = arith.constant 2 : index
// CHECK:      %c1 = arith.constant 1 : index
// CHECK:      scf.for %arg0 = %c0 to %c2 step %c1 {
// CHECK:        %10 = AIE.objectFifo.acquire @objfifo(Produce, 3) : !AIE.objectFifoSubview<memref<16xi32>>
// CHECK:        %11 = AIE.objectFifo.subview.access %10[0] : !AIE.objectFifoSubview<memref<16xi32>> -> memref<16xi32>
// CHECK:        %12 = AIE.objectFifo.subview.access %10[1] : !AIE.objectFifoSubview<memref<16xi32>> -> memref<16xi32>
// CHECK:        %13 = AIE.objectFifo.subview.access %10[2] : !AIE.objectFifoSubview<memref<16xi32>> -> memref<16xi32>
// CHECK:        func.call @producer_work() : () -> ()
// CHECK:        AIE.objectFifo.release @objfifo(Produce, 1)
// CHECK:      }
// CHECK:      %6 = AIE.objectFifo.acquire @objfifo(Produce, 3) : !AIE.objectFifoSubview<memref<16xi32>>
// CHECK:      %7 = AIE.objectFifo.subview.access %6[0] : !AIE.objectFifoSubview<memref<16xi32>> -> memref<16xi32>
// CHECK:      %8 = AIE.objectFifo.subview.access %6[1] : !AIE.objectFifoSubview<memref<16xi32>> -> memref<16xi32>
// CHECK:      %9 = AIE.objectFifo.subview.access %6[2] : !AIE.objectFifoSubview<memref<16xi32>> -> memref<16xi32>
// CHECK:      func.call @producer_work() : () -> ()
// CHECK:      AIE.objectFifo.release @objfifo(Produce, 2)
// CHECK:      AIE.objectFifo.release @objfifo(Produce, 1)
// CHECK:      AIE.end
// CHECK:    }
// CHECK:  }

module @registerPatterns  {
    AIE.device(xcvc1902) {
        %tile12 = AIE.tile(1, 2)
        %tile13 = AIE.tile(1, 3)

        AIE.objectFifo @objfifo (%tile12, {%tile13}, 4 : i32) : !AIE.objectFifo<memref<16xi32>>

        %acquirePattern = arith.constant dense<[2,3,3,3,0]> : tensor<5xi32>
        %releasePattern = arith.constant dense<[0,1,1,2,1]> : tensor<5xi32>
        %length = arith.constant 10 : index
        func.func @producer_work() -> () { 
            return
        }

        AIE.objectFifo.registerProcess @objfifo (Produce, %acquirePattern : tensor<5xi32>, %releasePattern : tensor<5xi32>, @producer_work, %length) 
    }
}
