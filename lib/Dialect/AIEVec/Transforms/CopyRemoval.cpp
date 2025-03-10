//===- CopyRemoval.cpp - Removing the redundant copies --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "mlir/Interfaces/CopyOpInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/Passes.h"

using namespace mlir;
using namespace MemoryEffects;

namespace {

//===----------------------------------------------------------------------===//
// TODO: this pass once existed in the upstream MLIR and was removed at
// https://reviews.llvm.org/D99172. This CopyRemoval pass was removed due to the
// introduction of memref.clone (now bufferization.clone). bufferization.clone
// is essentially memref.alloc+copy ops and is mostly created in
// buffer-deallocation pass. It is introduced for better memory deallocation and
// optimization. The canonicalization pass can optimize out some of the
// bufferization.clone+memref.dealloc ops. If the bufferization.clone still
// exists in the end of bufferization pass, we should call
// "-convert-bufferization-to-memref" pass to convert it back to
// memref.alloc+memref.copy.  Hence, the original CopyRemoval pass (which
// removes memref.alloc/copy/dealloc) is replaced by the canonicalization of
// bufferization.clone+memref.dealloc op. However, in our case, memref.alloc()
// is from the tensor.empty() after bufferization, memref.copy() is added in
// buffer-results-to-out-params pass, and memref.dealloc() is added in
// buffer-deallocation pass, which creates a pattern that the existing
// canonicalizer cannot support. As a result, we recover this CopyRemoval pass
// back into the canonicalization pass for Vector before lowering to AIEVec and
// help eliminate unnecessary memory allocation after the bufferization. Note
// that we can also try to remove copy op before the bufferization. This will
// require the function to be converted to destination-passing style code at
// tensor level, which isn't fully supported in the existing MLIR environment
// yet. Once the upstream MLIR has a mature support on this, removing copy op
// before bufferization can be another direction to pursue.
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// CopyRemovalPass
//===----------------------------------------------------------------------===//

/// This pass removes the redundant Copy operations. Additionally, it
/// removes the leftover definition and deallocation operations by erasing the
/// copy operation.
class CopyRemovalPass : public PassWrapper<CopyRemovalPass, OperationPass<>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(CopyRemovalPass)

  void runOnOperation() override {
    getOperation()->walk([&](CopyOpInterface copyOp) {
      reuseCopySourceAsTarget(copyOp);
      reuseCopyTargetAsSource(copyOp);
    });
    for (std::pair<Value, Value> &pair : replaceList)
      pair.first.replaceAllUsesWith(pair.second);
    for (Operation *op : eraseList)
      op->erase();
  }

private:
  /// List of operations that need to be removed.
  llvm::SmallPtrSet<Operation *, 4> eraseList;

  /// List of values that need to be replaced with their counterparts.
  llvm::SmallDenseSet<std::pair<Value, Value>, 4> replaceList;

  /// Returns the allocation operation for `value` in `block` if it exists.
  /// nullptr otherwise.
  Operation *getAllocationOpInBlock(Value value, Block *block) {
    assert(block && "Block cannot be null");
    Operation *op = value.getDefiningOp();
    if (op && op->getBlock() == block) {
      auto effects = dyn_cast<MemoryEffectOpInterface>(op);
      if (effects && effects.hasEffect<Allocate>())
        return op;
    }
    return nullptr;
  }

  /// Returns the deallocation operation for `value` in `block` if it exists.
  /// nullptr otherwise.
  Operation *getDeallocationOpInBlock(Value value, Block *block) {
    assert(block && "Block cannot be null");
    auto valueUsers = value.getUsers();
    auto it = llvm::find_if(valueUsers, [&](Operation *op) {
      auto effects = dyn_cast<MemoryEffectOpInterface>(op);
      return effects && op->getBlock() == block && effects.hasEffect<Free>();
    });
    return (it == valueUsers.end() ? nullptr : *it);
  }

  /// Returns true if an operation between start and end operations has memory
  /// effect.
  bool hasMemoryEffectOpBetween(Operation *start, Operation *end) {
    assert((start || end) && "Start and end operations cannot be null");
    assert(start->getBlock() == end->getBlock() &&
           "Start and end operations should be in the same block.");
    Operation *op = start->getNextNode();
    while (op->isBeforeInBlock(end)) {
      if (isa<MemoryEffectOpInterface>(op))
        return true;
      op = op->getNextNode();
    }
    return false;
  };

  /// Returns true if `val` value has at least a user between `start` and
  /// `end` operations.
  bool hasUsersBetween(Value val, Operation *start, Operation *end) {
    assert((start || end) && "Start and end operations cannot be null");
    Block *block = start->getBlock();
    assert(block == end->getBlock() &&
           "Start and end operations should be in the same block.");
    return llvm::any_of(val.getUsers(), [&](Operation *op) {
      return op->getBlock() == block && start->isBeforeInBlock(op) &&
             op->isBeforeInBlock(end);
    });
  };

  bool areOpsInTheSameBlock(ArrayRef<Operation *> operations) {
    assert(!operations.empty() &&
           "The operations list should contain at least a single operation");
    Block *block = operations.front()->getBlock();
    return llvm::none_of(
        operations, [&](Operation *op) { return block != op->getBlock(); });
  }

  /// Input:
  /// func(){
  ///   %from = alloc()
  ///   write_to(%from)
  ///   %to = alloc()
  ///   copy(%from,%to)
  ///   dealloc(%from)
  ///   return %to
  /// }
  ///
  /// Output:
  /// func(){
  ///   %from = alloc()
  ///   write_to(%from)
  ///   return %from
  /// }
  /// Constraints:
  /// 1) %to, copy and dealloc must all be defined and lie in the same block.
  /// 2) This transformation cannot be applied if there is a single user/alias
  /// of `to` value between the defining operation of `to` and the copy
  /// operation.
  /// 3) This transformation cannot be applied if there is a single user/alias
  /// of `from` value between the copy operation and the deallocation of `from`.
  /// TODO: Alias analysis is not available at the moment. Currently, we check
  /// if there are any operations with memory effects between copy and
  /// deallocation operations.
  void reuseCopySourceAsTarget(CopyOpInterface copyOp) {
    if (eraseList.count(copyOp))
      return;

    Value from = copyOp.getSource();
    Value to = copyOp.getTarget();

    Operation *copy = copyOp.getOperation();
    Block *copyBlock = copy->getBlock();
    Operation *fromDefiningOp = from.getDefiningOp();
    Operation *fromFreeingOp = getDeallocationOpInBlock(from, copyBlock);
    Operation *toDefiningOp = getAllocationOpInBlock(to, copyBlock);
    if (!fromDefiningOp || !fromFreeingOp || !toDefiningOp ||
        !areOpsInTheSameBlock({fromFreeingOp, toDefiningOp, copy}) ||
        hasUsersBetween(to, toDefiningOp, copy) ||
        hasUsersBetween(from, copy, fromFreeingOp) ||
        hasMemoryEffectOpBetween(copy, fromFreeingOp))
      return;

    replaceList.insert({to, from});
    eraseList.insert(copy);
    eraseList.insert(toDefiningOp);
    eraseList.insert(fromFreeingOp);
  }

  /// Input:
  /// func(){
  ///   %to = alloc()
  ///   %from = alloc()
  ///   write_to(%from)
  ///   copy(%from,%to)
  ///   dealloc(%from)
  ///   return %to
  /// }
  ///
  /// Output:
  /// func(){
  ///   %to = alloc()
  ///   write_to(%to)
  ///   return %to
  /// }
  /// Constraints:
  /// 1) %from, copy and dealloc must all be defined and lie in the same block.
  /// 2) This transformation cannot be applied if there is a single user/alias
  /// of `to` value between the defining operation of `from` and the copy
  /// operation.
  /// 3) This transformation cannot be applied if there is a single user/alias
  /// of `from` value between the copy operation and the deallocation of `from`.
  /// TODO: Alias analysis is not available at the moment. Currently, we check
  /// if there are any operations with memory effects between copy and
  /// deallocation operations.
  void reuseCopyTargetAsSource(CopyOpInterface copyOp) {
    if (eraseList.count(copyOp))
      return;

    Value from = copyOp.getSource();
    Value to = copyOp.getTarget();

    Operation *copy = copyOp.getOperation();
    Block *copyBlock = copy->getBlock();
    Operation *fromDefiningOp = getAllocationOpInBlock(from, copyBlock);
    Operation *fromFreeingOp = getDeallocationOpInBlock(from, copyBlock);
    if (!fromDefiningOp || !fromFreeingOp ||
        !areOpsInTheSameBlock({fromFreeingOp, fromDefiningOp, copy}) ||
        hasUsersBetween(to, fromDefiningOp, copy) ||
        hasUsersBetween(from, copy, fromFreeingOp) ||
        hasMemoryEffectOpBetween(copy, fromFreeingOp))
      return;

    replaceList.insert({from, to});
    eraseList.insert(copy);
    eraseList.insert(fromDefiningOp);
    eraseList.insert(fromFreeingOp);
  }
};

} // end anonymous namespace

//===----------------------------------------------------------------------===//
// CopyRemovalPass construction
//===----------------------------------------------------------------------===//

std::unique_ptr<::mlir::Pass> createCopyRemovalPass() {
  return std::make_unique<CopyRemovalPass>();
}
