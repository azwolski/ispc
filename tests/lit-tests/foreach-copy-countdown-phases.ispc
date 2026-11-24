// REQUIRES: LINUX_HOST && X86_ENABLED
// RUN: rm -rf %t.phases
// RUN: %{ispc} %s -O3 --target=avx512spr-x4 --arch=x86-64 --emit-llvm-text -o %t.ll --debug-phase=299,300,390 --dump-file=%t.phases/all
// RUN: ls %t.phases/all | FileCheck %s --check-prefixes=DELETE,UNROLL,CLEANUP
// RUN: %{ispc} %s -O3 --target=avx512spr-x4 --arch=x86-64 --emit-llvm-text -o %t.ll --debug-phase=299,300,390 --off-phase=299 --dump-file=%t.phases/no-delete
// RUN: ls %t.phases/no-delete | FileCheck %s --check-prefixes=UNROLL,CLEANUP --implicit-check-not=LoopDeletionPass
// RUN: %{ispc} %s -O3 --target=avx512spr-x4 --arch=x86-64 --emit-llvm-text -o %t.ll --debug-phase=299,300,390 --off-phase=300 --dump-file=%t.phases/no-unroll
// RUN: ls %t.phases/no-unroll | FileCheck %s --check-prefixes=DELETE,CLEANUP --implicit-check-not=LoopUnrollPass
// RUN: %{ispc} %s -O3 --target=avx512spr-x4 --arch=x86-64 --emit-llvm-text -o %t.ll --debug-phase=299,300,390 --off-phase=300 --opt=disable-loop-unroll --dump-file=%t.phases/unroll-disabled
// RUN: ls %t.phases/unroll-disabled | FileCheck %s --check-prefixes=DELETE,CLEANUP --implicit-check-not=LoopUnrollPass
// RUN: %{ispc} %s -O3 --target=avx512spr-x4 --arch=x86-64 --emit-llvm-text -o %t.ll --debug-phase=299,300,390 --off-phase=390 --dump-file=%t.phases/no-cleanup
// RUN: ls %t.phases/no-cleanup | FileCheck %s --check-prefixes=DELETE,UNROLL --implicit-check-not=IndVarSimplifyPass

// DELETE: ir_299_LoopDeletionPass.ll
// UNROLL: ir_300_LoopUnrollPass.ll
// CLEANUP: ir_390_IndVarSimplifyPass.ll

#include "foreach-copy-countdown.inc"
