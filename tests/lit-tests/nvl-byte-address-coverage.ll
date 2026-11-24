; Copyright (c) 2026, Intel Corporation
; SPDX-License-Identifier: BSD-3-Clause

; REQUIRES: X86_ENABLED && !MACOS_HOST && LLVM_22_0+
; RUN: %{ispc-opt} --target=avx10.2nvl-x4 --arch=x86-64 --passes=scalarize %s -o - | FileCheck %s --check-prefixes=NVL4,KEEP
; RUN: %{ispc-opt} --target=avx512spr-x4 --arch=x86-64 --passes=scalarize %s -o - | FileCheck %s --check-prefixes=SPR4,KEEP

; NVL4-LABEL: define i8 @factored(
; NVL4: [[LANE:%.*]] = or disjoint i32 %offset, 2
; NVL4-NEXT: [[SCALED:%.*]] = shl nuw nsw i32 [[LANE]], 1
; NVL4-NEXT: [[ADDR:%.*]] = zext nneg i32 [[SCALED]] to i64
; NVL4-NEXT: %address = getelementptr inbounds i8, ptr %base, i64 [[ADDR]]
; SPR4-LABEL: define i8 @factored(
; SPR4: %lane = extractelement <4 x i64> %wide, i64 2

define i8 @factored(ptr %base, i32 %offset) {
  %seed = insertelement <4 x i32> poison, i32 %offset, i64 0
  %splat = shufflevector <4 x i32> %seed, <4 x i32> poison, <4 x i32> zeroinitializer
  %offsets = or disjoint <4 x i32> %splat, <i32 0, i32 1, i32 2, i32 3>
  %shift = shl nuw nsw <4 x i32> %offsets, splat (i32 1)
  %wide = zext nneg <4 x i32> %shift to <4 x i64>
  %lane = extractelement <4 x i64> %wide, i64 2
  %address = getelementptr inbounds i8, ptr %base, i64 %lane
  %byte = load i8, ptr %address, align 1
  ret i8 %byte
}

; KEEP-LABEL: define i8 @live_computed(
; KEEP: %wide = zext <4 x i32> %offsets to <4 x i64>
; KEEP-NEXT: store <4 x i64> %wide, ptr %copy
; KEEP-NEXT: %lane = extractelement <4 x i64> %wide, i64 2

define i8 @live_computed(ptr %base, ptr %copy, i32 %offset) {
  %seed = insertelement <4 x i32> poison, i32 %offset, i64 0
  %splat = shufflevector <4 x i32> %seed, <4 x i32> poison, <4 x i32> zeroinitializer
  %offsets = or disjoint <4 x i32> %splat, <i32 0, i32 1, i32 2, i32 3>
  %wide = zext <4 x i32> %offsets to <4 x i64>
  store <4 x i64> %wide, ptr %copy, align 8
  %lane = extractelement <4 x i64> %wide, i64 2
  %address = getelementptr i8, ptr %base, i64 %lane
  %byte = load i8, ptr %address, align 1
  ret i8 %byte
}

; KEEP-LABEL: define i8 @mixed_computed(
; KEEP: %wide = zext <4 x i32> %offsets to <4 x i64>
; KEEP-NEXT: %first = extractelement <4 x i64> %wide, i64 1
; KEEP: %second = extractelement <4 x i64> %wide, i64 2

define i8 @mixed_computed(ptr %base, ptr %other, i32 %offset, i1 %cond) {
  %seed = insertelement <4 x i32> poison, i32 %offset, i64 0
  %splat = shufflevector <4 x i32> %seed, <4 x i32> poison, <4 x i32> zeroinitializer
  %offsets = or disjoint <4 x i32> %splat, <i32 0, i32 1, i32 2, i32 3>
  %wide = zext <4 x i32> %offsets to <4 x i64>
  %first = extractelement <4 x i64> %wide, i64 1
  %first.address = getelementptr i8, ptr %base, i64 %first
  %first.byte = load i8, ptr %first.address, align 1
  br i1 %cond, label %other.block, label %exit

other.block:
  %second = extractelement <4 x i64> %wide, i64 2
  %second.address = getelementptr i8, ptr %other, i64 %second
  %second.byte = load atomic i8, ptr %second.address monotonic, align 1
  %sum = add i8 %first.byte, %second.byte
  ret i8 %sum

exit:
  ret i8 %first.byte
}

; KEEP-LABEL: define i8 @out_of_bounds(
; KEEP: %wide = zext <4 x i32> %offsets to <4 x i64>
; KEEP-NEXT: %first = extractelement <4 x i64> %wide, i64 1
; KEEP: %second = extractelement <4 x i64> %wide, i64 4

define i8 @out_of_bounds(ptr %base, i32 %offset, i1 %cond) {
  %seed = insertelement <4 x i32> poison, i32 %offset, i64 0
  %splat = shufflevector <4 x i32> %seed, <4 x i32> poison, <4 x i32> zeroinitializer
  %offsets = or disjoint <4 x i32> %splat, <i32 0, i32 1, i32 2, i32 3>
  %wide = zext <4 x i32> %offsets to <4 x i64>
  %first = extractelement <4 x i64> %wide, i64 1
  %first.address = getelementptr i8, ptr %base, i64 %first
  %first.byte = load i8, ptr %first.address, align 1
  br i1 %cond, label %other.block, label %exit

other.block:
  %second = extractelement <4 x i64> %wide, i64 4
  %second.address = getelementptr i8, ptr %base, i64 %second
  %second.byte = load i8, ptr %second.address, align 1
  %sum = add i8 %first.byte, %second.byte
  ret i8 %sum

exit:
  ret i8 %first.byte
}
