// Copyright (c) 2026, Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

// REQUIRES: X86_ENABLED && LINUX_ENABLED && !MACOS_HOST && LLVM_22_0+
// RUN: %{ispc} %s --target=avx10.2nvl-x4 --arch=x86-64 --target-os=linux -O3 --woff --emit-llvm-text -o - | FileCheck %s -D#WIDTH=4
// RUN: %{ispc} %s --target=avx10.2nvl-x4 --arch=x86-64 --target-os=linux -O3 --woff --emit-asm -o - | FileCheck %s --check-prefix=ASM
// RUN: %{ispc} %s --target=avx10.2nvl-x4 --arch=x86-64 --target-os=linux -O3 --woff --opt=disable-gathers --emit-llvm-text -o - | FileCheck %s -D#WIDTH=4
// RUN: %{ispc} %s --target=avx10.2nvl-x4 --arch=x86-64 --target-os=linux -O3 --woff --opt=disable-gathers --emit-asm -o - | FileCheck %s --check-prefix=ASM
// RUN: %{ispc} %s --target=avx10.2nvl-x8 --arch=x86-64 --target-os=linux -O3 --woff --emit-llvm-text -o - | FileCheck %s -D#WIDTH=8
// RUN: %{ispc} %s --target=avx10.2nvl-x8 --arch=x86-64 --target-os=linux -O3 --woff --emit-asm -o - | FileCheck %s --check-prefix=ASM
// RUN: %{ispc} %s --target=avx10.2nvl-x8 --arch=x86-64 --target-os=linux -O3 --woff --opt=disable-gathers --emit-llvm-text -o - | FileCheck %s -D#WIDTH=8
// RUN: %{ispc} %s --target=avx10.2nvl-x8 --arch=x86-64 --target-os=linux -O3 --woff --opt=disable-gathers --emit-asm -o - | FileCheck %s --check-prefix=ASM
// RUN: %{ispc} %s --target=avx10.2nvl-x16 --arch=x86-64 --target-os=linux -O3 --woff --emit-llvm-text -o - | FileCheck %s -D#WIDTH=16
// RUN: %{ispc} %s --target=avx10.2nvl-x16 --arch=x86-64 --target-os=linux -O3 --woff --emit-asm -o - | FileCheck %s --check-prefix=ASM
// RUN: %{ispc} %s --target=avx10.2nvl-x16 --arch=x86-64 --target-os=linux -O3 --woff --opt=disable-gathers --emit-llvm-text -o - | FileCheck %s -D#WIDTH=16
// RUN: %{ispc} %s --target=avx10.2nvl-x16 --arch=x86-64 --target-os=linux -O3 --woff --opt=disable-gathers --emit-asm -o - | FileCheck %s --check-prefix=ASM

// ASM-LABEL: gather_bytes:
// ASM: [[LOOP:\.LBB[0-9_]+]]:{{.*}}Inner Loop Header
// ASM-NOT: vpmovzxdq
// ASM: movl {{[0-9]*}}(%rsi,{{%r[a-z0-9]+}},4), {{%[a-z0-9]+}}
// ASM-NOT: vpmovzxdq
// ASM: j{{[a-z]+}} {{[[:space:]]*}}[[LOOP]]

// CHECK-LABEL: define void @gather_bytes(
// CHECK: foreach_full_body:
// CHECK: [[INDICES:%[^ ]+]] = load <[[#WIDTH]] x i32>
// CHECK-NOT: zext <[[#WIDTH]] x i32>
// CHECK: [[INDEX:%[^ ]+]] = extractelement <[[#WIDTH]] x i32> [[INDICES]], i64 0
// CHECK-NEXT: [[OFFSET:%[^ ]+]] = zext i32 [[INDEX]] to i64
// CHECK-NEXT: getelementptr i8, ptr %src, i64 [[OFFSET]]
// CHECK-NOT: zext <[[#WIDTH]] x i32>
// CHECK: br i1
// CHECK: [[MASKED:%[^ ]+]] = {{.*}}call <[[#WIDTH]] x i32> @llvm.masked.load
// CHECK: zext <[[#WIDTH]] x i32> [[MASKED]] to <[[#WIDTH]] x i64>
// CHECK: {{store i8|call void @llvm.masked.store}}
export void gather_bytes(uniform int8 src[], uniform uint32 indices[], uniform int8 dst[], uniform int n) {
    foreach (i = 0 ... n) {
        dst[i] = src[indices[i]];
    }
}
