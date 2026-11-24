// RUN: %{ispc} %s -O3 --target=avx512spr-x4 --arch=x86-64 --emit-llvm-text -o %t.on.ll
// RUN: %{ispc} %s -O3 --target=avx512spr-x4 --arch=x86-64 --opt=disable-gathers --emit-llvm-text -o %t.off.ll
// RUN: FileCheck %s --check-prefix=COPY --input-file=%t.on.ll
// RUN: FileCheck %s --check-prefix=COPY --input-file=%t.off.ll
// RUN: opt "-passes=print<loops>" -disable-output %t.on.ll 2>&1 | FileCheck %s --check-prefix=LOOPS
// RUN: opt "-passes=print<loops>" -disable-output %t.off.ll 2>&1 | FileCheck %s --check-prefix=LOOPS
// REQUIRES: X86_ENABLED && LLVM_21_0+

// COPY-LABEL: define void @copy(
// COPY: call void @llvm.memcpy
// COPY: call <4 x i64> @llvm.masked.load
// COPY: call void @llvm.masked.store
// COPY-LABEL: define void @copy_with_or(
// COPY: or <4 x i64>
// COPY: store <4 x i64>
// COPY-LABEL: define void @clear_bytes(
// COPY: call void @llvm.memset

// LoopInfo detects the empty countdown even if its block names change.
// LOOPS-LABEL: Loop info for function 'copy':
// LOOPS-NOT: Loop at depth
// LOOPS-LABEL: Loop info for function 'copy_with_or':
// LOOPS: Loop at depth 1 containing:
// LOOPS-LABEL: Loop info for function 'clear_bytes':
// LOOPS-NOT: Loop at depth
// LOOPS-LABEL: Loop info for function 'copy_and_sum':
// LOOPS: Loop at depth 1 containing:

#include "foreach-copy-countdown.inc"
