// (c) 2023 SAFARI Research Group at ETH Zurich, Gagandeep Singh, D-ITET   
  
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

module @hdiff_single_AIE {
  %t71 = AIE.tile(7, 1)
  %t70 = AIE.tile(7, 0)
  
  %lock71_14 = AIE.lock(%t71, 14) { sym_name = "lock71_14" }

  AIE.objectFifo @obj_in (%t70, {%t71}, 6 : i32) : !AIE.objectFifo<memref<256xi32>>
  AIE.objectFifo @obj_out (%t71, {%t70}, 2 : i32) : !AIE.objectFifo<memref<256xi32>>

   // DDR buffer
  %ext_buffer_in0 = AIE.external_buffer {sym_name = "ddr_test_buffer_in0"}: memref<1536 x i32>
  %ext_buffer_out = AIE.external_buffer {sym_name = "ddr_test_buffer_out"}: memref<512 x i32>
      
  // Register the external memory pointers to the object FIFOs.
  AIE.objectFifo.registerExternalBuffers @obj_in (%t70, {%ext_buffer_in0}) : (memref<1536xi32>)
  AIE.objectFifo.registerExternalBuffers @obj_out (%t70, {%ext_buffer_out}) : (memref<512xi32>)

  func.func private @vec_hdiff(%A: memref<256xi32>, %B: memref<256xi32>, %C:  memref<256xi32>, %D: memref<256xi32>, %E:  memref<256xi32>,  %O: memref<256xi32>) -> ()

  %c13 = AIE.core(%t71) { 
    %lb = arith.constant 0 : index
    %ub = arith.constant 2: index // 256*1= (256-2)*1
    %step = arith.constant 1 : index
    AIE.useLock(%lock71_14, "Acquire", 0) // start the timer
    scf.for %iv = %lb to %ub step %step {  
      %obj_in_subview = AIE.objectFifo.acquire @obj_in (Consume, 5) : !AIE.objectFifoSubview<memref<256xi32>>
      %row0 = AIE.objectFifo.subview.access %obj_in_subview[0] : !AIE.objectFifoSubview<memref<256xi32>> -> memref<256xi32>
      %row1 = AIE.objectFifo.subview.access %obj_in_subview[1] : !AIE.objectFifoSubview<memref<256xi32>> -> memref<256xi32>
      %row2 = AIE.objectFifo.subview.access %obj_in_subview[2] : !AIE.objectFifoSubview<memref<256xi32>> -> memref<256xi32>
      %row3 = AIE.objectFifo.subview.access %obj_in_subview[3] : !AIE.objectFifoSubview<memref<256xi32>> -> memref<256xi32>
      %row4 = AIE.objectFifo.subview.access %obj_in_subview[4] : !AIE.objectFifoSubview<memref<256xi32>> -> memref<256xi32>

      %obj_out_subview = AIE.objectFifo.acquire @obj_out (Produce, 1) : !AIE.objectFifoSubview<memref<256xi32>>
      %obj_out = AIE.objectFifo.subview.access %obj_out_subview[0] : !AIE.objectFifoSubview<memref<256xi32>> -> memref<256xi32>
    
      func.call @vec_hdiff(%row0,%row1,%row2,%row3,%row4,%obj_out) : (memref<256xi32>,memref<256xi32>, memref<256xi32>, memref<256xi32>, memref<256xi32>,  memref<256xi32>) -> ()
      AIE.objectFifo.release @obj_in (Consume, 1)
      AIE.objectFifo.release @obj_out (Produce, 1)
    }
    AIE.useLock(%lock71_14, "Release", 0) // stop the timer
    AIE.objectFifo.release @obj_in (Consume, 4)

    AIE.end
  } { link_with="hdiff.o" }
}
