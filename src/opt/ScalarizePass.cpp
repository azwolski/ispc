/*
  Copyright (c) 2024-2026, Intel Corporation

  SPDX-License-Identifier: BSD-3-Clause
*/

#include "ScalarizePass.h"
#include "builtins-decl.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/Analysis/VectorUtils.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/ValueHandle.h"
#include "llvm/Transforms/Utils/Local.h"

namespace ispc {

using namespace llvm::PatternMatch;

static llvm::Value *lMatchAndScalarize(llvm::Instruction *inst) {
    llvm::Value *Vec = nullptr, *OutZeroMask = nullptr;
    llvm::BinaryOperator *BO = nullptr;
    if (!match(inst, m_Shuffle(m_BinOp(BO), m_Poison(), m_ZeroMask())) &&
        !match(inst, m_Shuffle(m_BinOp(BO), m_Undef(), m_ZeroMask()))) {
        return nullptr;
    }

    llvm::ShuffleVectorInst *SVI = llvm::cast<llvm::ShuffleVectorInst>(inst);
    OutZeroMask = SVI->getShuffleMaskForBitcode();

    llvm::BinaryOperator::BinaryOps Opc = BO->getOpcode();
    llvm::Value *Op1 = nullptr, *Op2 = nullptr;
    if (match(BO, m_BinOp(m_InsertElt(m_Undef(), m_Value(Op1), m_ZeroInt()), m_Value(Vec))) ||
        match(BO, m_BinOp(m_Value(Vec), m_InsertElt(m_Undef(), m_Value(Op2), m_ZeroInt())))) {

        if (llvm::ConstantVector *CV = llvm::dyn_cast<llvm::ConstantVector>(Vec)) {
            unsigned N = CV->getType()->getNumElements();
            bool isTailPoison = true;
            unsigned EltIdx = 0;

            for (unsigned i = 1; i < N; i++) {
                auto E = CV->getAggregateElement(i);
                if (!llvm::isa<llvm::PoisonValue>(E) && !llvm::isa<llvm::UndefValue>(E)) {
                    isTailPoison = false;
                    break;
                }
            }

            if (isTailPoison) {
                (!Op1 ? Op1 : Op2) = CV->getAggregateElement(EltIdx);
                Assert(Op1 && Op2);

                llvm::Type *VecType = Vec->getType();
                llvm::Value *PV = llvm::PoisonValue::get(VecType);
                llvm::IRBuilder<> Builder(inst);

                llvm::Value *ScalarBinOp = Builder.CreateBinOp(Opc, Op1, Op2);
                llvm::Value *newVec = Builder.CreateInsertElement(PV, ScalarBinOp, (uint64_t)0);
                return Builder.CreateShuffleVector(newVec, PV, OutZeroMask);
            }
        }
    }
    return nullptr;
}

// Limit scalar rematerialization to short chains of lane-wise address arithmetic.
struct ByteOffsetStep {
    llvm::BinaryOperator *op;
    llvm::Constant *constants;
    bool constantsOnLeft;
};

static llvm::ShuffleVectorInst *lMatchComputedByteOffsets(llvm::Value *value,
                                                          llvm::SmallVectorImpl<ByteOffsetStep> &steps) {
    constexpr unsigned MaxAddressOps = 3;
    while (auto *op = llvm::dyn_cast<llvm::BinaryOperator>(value)) {
        if (steps.size() == MaxAddressOps) {
            return nullptr;
        }
        const auto opcode = op->getOpcode();
        if (opcode != llvm::Instruction::Add && opcode != llvm::Instruction::Or && opcode != llvm::Instruction::Shl) {
            return nullptr;
        }
        auto *constants = llvm::dyn_cast<llvm::Constant>(op->getOperand(1));
        bool constantsOnLeft = false;
        if (!constants && opcode != llvm::Instruction::Shl) {
            constants = llvm::dyn_cast<llvm::Constant>(op->getOperand(0));
            constantsOnLeft = true;
        }
        if (!constants) {
            return nullptr;
        }
        steps.push_back({op, constants, constantsOnLeft});
        value = op->getOperand(constantsOnLeft ? 1 : 0);
    }

    auto *shuffle = llvm::dyn_cast<llvm::ShuffleVectorInst>(value);
    if (!shuffle) {
        return nullptr;
    }
    const int lane = llvm::getSplatIndex(shuffle->getShuffleMask());
    if (lane < 0 || !llvm::all_of(shuffle->getShuffleMask(), [lane](int elt) { return elt == lane; })) {
        return nullptr;
    }
    // Accept a splat of an existing scalar without traversing a second vector DAG.
    const auto sourceWidth = llvm::cast<llvm::FixedVectorType>(shuffle->getOperand(0)->getType())->getNumElements();
    const unsigned sourceLane = unsigned(lane) % sourceWidth;
    auto *insert = llvm::dyn_cast<llvm::InsertElementInst>(shuffle->getOperand(unsigned(lane) / sourceWidth));
    auto *insertLane = insert ? llvm::dyn_cast<llvm::ConstantInt>(insert->getOperand(2)) : nullptr;
    return insertLane && insertLane->equalsInt(sourceLane) ? shuffle : nullptr;
}

static llvm::ConstantInt *lMatchByteAddressLane(llvm::User *user, unsigned width) {
    auto *extract = llvm::dyn_cast<llvm::ExtractElementInst>(user);
    if (!extract || !extract->hasOneUse()) {
        return nullptr;
    }
    auto *lane = llvm::dyn_cast<llvm::ConstantInt>(extract->getIndexOperand());
    if (!lane || lane->getValue().uge(width)) {
        return nullptr;
    }
    auto *address = llvm::dyn_cast<llvm::GetElementPtrInst>(*extract->user_begin());
    if (!address || !address->getSourceElementType()->isIntegerTy(8) || !address->hasOneUse()) {
        return nullptr;
    }
    auto *byte = llvm::dyn_cast<llvm::LoadInst>(*address->user_begin());
    return byte && byte->isSimple() && byte->getPointerOperand() == address && byte->getType()->isIntegerTy(8)
               ? lane
               : nullptr;
}

static bool lScalarizeByteAddresses(llvm::ZExtInst *extend, unsigned width) {
    auto *indices = extend->getOperand(0);
    auto *i32 = llvm::Type::getInt32Ty(extend->getContext());
    auto *i64 = llvm::Type::getInt64Ty(extend->getContext());
    if (indices->getType() != llvm::FixedVectorType::get(i32, width) ||
        extend->getType() != llvm::FixedVectorType::get(i64, width)) {
        return false;
    }

    auto *load = llvm::dyn_cast<llvm::LoadInst>(indices);
    llvm::SmallVector<ByteOffsetStep, 3> steps;
    llvm::ShuffleVectorInst *splat = nullptr;
    llvm::Value *scalar = nullptr;
    if (load) {
        // Retaining the vector load can make instruction selection add scalar reloads.
        if (!load->isSimple() || !load->hasOneUse()) {
            return false;
        }
    } else {
        splat = lMatchComputedByteOffsets(indices, steps);
        if (!splat) {
            return false;
        }
        scalar = llvm::findScalarElement(splat, 0);
        if (!scalar || llvm::isa<llvm::Constant>(scalar)) {
            return false;
        }
    }

    llvm::SmallVector<std::pair<llvm::ExtractElementInst *, llvm::ConstantInt *>, 16> extracts;
    const bool sharedProducer =
        splat &&
        (!splat->hasOneUse() || llvm::any_of(steps, [](const ByteOffsetStep &step) { return !step.op->hasOneUse(); }));
    bool sharedWidening = false;
    for (auto *user : extend->users()) {
        auto *lane = lMatchByteAddressLane(user, width);
        if (!lane) {
            sharedWidening = true;
            continue;
        }
        if (llvm::any_of(steps, [lane](const ByteOffsetStep &step) {
                return !llvm::isa_and_nonnull<llvm::ConstantInt>(
                    step.constants->getAggregateElement(unsigned(lane->getZExtValue())));
            })) {
            return false;
        }
        extracts.emplace_back(llvm::cast<llvm::ExtractElementInst>(user), lane);
    }
    if (extracts.empty()) {
        return false;
    }
    if (sharedProducer || sharedWidening) {
        // Preserve the existing wider-vector OR case. Its scalar address costs
        // at most one OR per lane and adds no index loads. Keep newly matched
        // expressions exclusive so they do not duplicate live vector work.
        if (!splat || width < 8 || steps.size() != 1 || steps.front().op->getOpcode() != llvm::Instruction::Or ||
            steps.front().constantsOnLeft || splat->getMaskValue(0) != 0 ||
            !llvm::isa<llvm::PoisonValue>(splat->getOperand(1)) ||
            !llvm::isa<llvm::PoisonValue>(llvm::cast<llvm::InsertElementInst>(splat->getOperand(0))->getOperand(0)) ||
            llvm::any_of(
                extracts,
                [&](const auto &entry) {
                    return llvm::cast<llvm::ConstantInt>(
                               steps.front().constants->getAggregateElement(unsigned(entry.second->getZExtValue())))
                        ->isNegative();
                })) {
            return false;
        }
    }

    // The IR defines these integer operations lane by lane. Rebuild the selected
    // lane at i32, keeping poison-generating flags, then apply the original zext.
    for (auto [extract, lane] : extracts) {
        llvm::IRBuilder<> builder(extract);
        llvm::Value *index = load ? builder.CreateExtractElement(indices, lane) : scalar;
        for (const auto &step : llvm::reverse(steps)) {
            auto *constant = step.constants->getAggregateElement(unsigned(lane->getZExtValue()));
            auto *lhs = step.constantsOnLeft ? constant : index;
            auto *rhs = step.constantsOnLeft ? index : constant;
            switch (step.op->getOpcode()) {
            case llvm::Instruction::Add:
                index = builder.CreateAdd(lhs, rhs, "", step.op->hasNoUnsignedWrap(), step.op->hasNoSignedWrap());
                break;
            case llvm::Instruction::Or:
                index = builder.CreateOr(lhs, rhs, "", llvm::cast<llvm::PossiblyDisjointInst>(step.op)->isDisjoint());
                break;
            case llvm::Instruction::Shl:
                index = builder.CreateShl(lhs, rhs, "", step.op->hasNoUnsignedWrap(), step.op->hasNoSignedWrap());
                break;
            default:
                llvm_unreachable("unexpected byte address operation");
            }
        }
        auto *wide = builder.CreateZExt(index, i64, "", extend->hasNonNeg());
        extract->replaceAllUsesWith(wide);
        extract->eraseFromParent();
    }
    llvm::RecursivelyDeleteTriviallyDeadInstructions(extend);
    return true;
}

bool ScalarizePass::matchAndReplace(llvm::BasicBlock &bb) {
    DEBUG_START_BB("ScalarizePass");

    bool modifiedAny = false;

    // Note: we do modify instruction list during the traversal, so the iterator
    // is moved forward before the instruction is processed.
    for (llvm::BasicBlock::iterator iter = bb.begin(), e = bb.end(); iter != e;) {
        llvm::Instruction *inst = &*(iter++);

        llvm::Value *newValue = lMatchAndScalarize(inst);
        if (newValue != nullptr) {
            inst->replaceAllUsesWith(newValue);
            llvm::RecursivelyDeleteTriviallyDeadInstructions(inst);
            modifiedAny = true;
        }
    }

    DEBUG_END_BB("ScalarizePass");

    return modifiedAny;
}

llvm::PreservedAnalyses ScalarizePass::run(llvm::Function &F, llvm::FunctionAnalysisManager &FAM) {
    llvm::TimeTraceScope FuncScope("ScalarizePass::run", F.getName());

    bool modifiedAny = false;
    for (llvm::BasicBlock &BB : F) {
        modifiedAny |= matchAndReplace(BB);
    }

    if (g && g->target && g->target->getISA() == Target::NVL_AVX10_2) {
        unsigned width = g->target->getVectorWidth();
        if (width == 4 || width == 8 || width == 16) {
            // Collect first because a use group may span multiple basic blocks.
            llvm::SmallVector<llvm::WeakTrackingVH, 4> addressExtends;
            for (auto &bb : F) {
                for (auto &inst : bb) {
                    auto *extend = llvm::dyn_cast<llvm::ZExtInst>(&inst);
                    if (extend && extend->getType()->isVectorTy()) {
                        addressExtends.push_back(extend);
                    }
                }
            }
            for (const auto &candidate : addressExtends) {
                if (auto *extend = llvm::dyn_cast_or_null<llvm::ZExtInst>(candidate)) {
                    modifiedAny |= lScalarizeByteAddresses(extend, width);
                }
            }
        }
    }

    if (!modifiedAny) {
        // No changes, all analyses are preserved.
        return llvm::PreservedAnalyses::all();
    }

    llvm::PreservedAnalyses PA;
    PA.preserveSet<llvm::CFGAnalyses>();
    return PA;
}

} // namespace ispc
