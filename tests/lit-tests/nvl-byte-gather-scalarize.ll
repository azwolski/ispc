; Copyright (c) 2026, Intel Corporation
; SPDX-License-Identifier: BSD-3-Clause

; REQUIRES: X86_ENABLED && !MACOS_HOST && LLVM_22_0+
; RUN: %{ispc-opt} --target=avx10.2nvl-x16 --arch=x86-64 --passes=scalarize %s -o - | FileCheck %s --check-prefix=NVL
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --arch=x86-64 --passes=scalarize %s -o - | FileCheck %s --check-prefix=OUTSIDE
; RUN: %{ispc-opt} --target=avx512spr-x16 --arch=x86-64 --passes=scalarize %s -o - | FileCheck %s --check-prefix=OUTSIDE

; NVL-LABEL: define i8 @ordinary(
; NVL: [[LANE:%.*]] = extractelement <16 x i32> %indices, i64 3
; NVL-NEXT: [[OFFSET:%.*]] = zext nneg i32 [[LANE]] to i64
; NVL-NEXT: %address = getelementptr i8, ptr %base, i64 [[OFFSET]]
; OUTSIDE-LABEL: define i8 @ordinary(
; OUTSIDE: %wide = zext nneg <16 x i32> %indices to <16 x i64>
; OUTSIDE-NEXT: %offset = extractelement <16 x i64> %wide, i64 3
define i8 @ordinary(ptr %idx, ptr %base) {
  %indices = load <16 x i32>, ptr %idx, align 4
  %wide = zext nneg <16 x i32> %indices to <16 x i64>
  %offset = extractelement <16 x i64> %wide, i64 3
  %address = getelementptr i8, ptr %base, i64 %offset
  %byte = load i8, ptr %address, align 1
  ret i8 %byte
}

; NVL-LABEL: define i8 @multiple_blocks(
; NVL-NOT: zext <16 x i32>
; NVL: [[FIRST_INDEX:%.*]] = extractelement <16 x i32> %indices, i64 3
; NVL-NEXT: [[FIRST_OFFSET:%.*]] = zext i32 [[FIRST_INDEX]] to i64
; NVL-NEXT: %first.address = getelementptr inbounds i8, ptr %base, i64 [[FIRST_OFFSET]]
; NVL: second.block:
; NVL-NEXT: [[SECOND_INDEX:%.*]] = extractelement <16 x i32> %indices, i64 15
; NVL-NEXT: [[SECOND_OFFSET:%.*]] = zext i32 [[SECOND_INDEX]] to i64
; NVL-NEXT: %second.address = getelementptr i8, ptr %base, i64 [[SECOND_OFFSET]]
define i8 @multiple_blocks(ptr %idx, ptr %base, i1 %cond) {
  %indices = load <16 x i32>, ptr %idx, align 4
  %wide = zext <16 x i32> %indices to <16 x i64>
  %first = extractelement <16 x i64> %wide, i64 3
  %first.address = getelementptr inbounds i8, ptr %base, i64 %first
  %first.byte = load i8, ptr %first.address, align 1
  br i1 %cond, label %second.block, label %exit

second.block:
  %second = extractelement <16 x i64> %wide, i64 15
  %second.address = getelementptr i8, ptr %base, i64 %second
  %second.byte = load i8, ptr %second.address, align 1
  %sum = add i8 %first.byte, %second.byte
  ret i8 %sum

exit:
  ret i8 %first.byte
}

; NVL-LABEL: define i8 @live_narrow_vector(
; NVL: store <16 x i32> %indices, ptr %copy
; NVL: %wide = zext <16 x i32> %indices to <16 x i64>
; NVL-NEXT: %offset = extractelement <16 x i64> %wide, i64 3
define i8 @live_narrow_vector(ptr %idx, ptr %base, ptr %copy) {
  %indices = load <16 x i32>, ptr %idx, align 4
  store <16 x i32> %indices, ptr %copy, align 4
  %wide = zext <16 x i32> %indices to <16 x i64>
  %offset = extractelement <16 x i64> %wide, i64 3
  %address = getelementptr i8, ptr %base, i64 %offset
  %byte = load i8, ptr %address, align 1
  ret i8 %byte
}

; NVL-LABEL: define i8 @live_wide_vector(
; NVL: %wide = zext <16 x i32> %indices to <16 x i64>
; NVL-NEXT: store <16 x i64> %wide, ptr %copy
; NVL-NEXT: %offset = extractelement <16 x i64> %wide, i64 3
define i8 @live_wide_vector(ptr %idx, ptr %base, ptr %copy) {
  %indices = load <16 x i32>, ptr %idx, align 4
  %wide = zext <16 x i32> %indices to <16 x i64>
  store <16 x i64> %wide, ptr %copy, align 8
  %offset = extractelement <16 x i64> %wide, i64 3
  %address = getelementptr i8, ptr %base, i64 %offset
  %byte = load i8, ptr %address, align 1
  ret i8 %byte
}

; NVL-LABEL: define i8 @mixed_loads(
; NVL: %wide = zext <16 x i32> %indices to <16 x i64>
; NVL-NEXT: %first = extractelement <16 x i64> %wide, i64 3
; NVL: %second = extractelement <16 x i64> %wide, i64 15
define i8 @mixed_loads(ptr %idx, ptr %base, ptr %other) {
  %indices = load <16 x i32>, ptr %idx, align 4
  %wide = zext <16 x i32> %indices to <16 x i64>
  %first = extractelement <16 x i64> %wide, i64 3
  %first.address = getelementptr i8, ptr %base, i64 %first
  %first.byte = load i8, ptr %first.address, align 1
  %second = extractelement <16 x i64> %wide, i64 15
  %second.address = getelementptr i8, ptr %other, i64 %second
  %second.byte = load volatile i8, ptr %second.address, align 1
  %sum = add i8 %first.byte, %second.byte
  ret i8 %sum
}

; NVL-LABEL: define i64 @multi_use(
; NVL: %offset = extractelement <16 x i64> %wide, i64 3
define i64 @multi_use(ptr %idx, ptr %base) {
  %indices = load <16 x i32>, ptr %idx, align 4
  %wide = zext <16 x i32> %indices to <16 x i64>
  %offset = extractelement <16 x i64> %wide, i64 3
  %address = getelementptr i8, ptr %base, i64 %offset
  %byte = load i8, ptr %address, align 1
  %value = zext i8 %byte to i64
  %result = add i64 %value, %offset
  ret i64 %result
}

; NVL-LABEL: define i8 @masked(
; NVL: %offset = extractelement <16 x i64> %wide, i64 3
define i8 @masked(ptr %idx, ptr %base, <16 x i1> %mask) {
  %indices = call <16 x i32> @llvm.masked.load.v16i32.p0(ptr %idx, <16 x i1> %mask, <16 x i32> zeroinitializer)
  %wide = zext <16 x i32> %indices to <16 x i64>
  %offset = extractelement <16 x i64> %wide, i64 3
  %address = getelementptr i8, ptr %base, i64 %offset
  %byte = load i8, ptr %address, align 1
  ret i8 %byte
}
declare <16 x i32> @llvm.masked.load.v16i32.p0(ptr, <16 x i1>, <16 x i32>)

; NVL-LABEL: define i8 @computed(
; NVL: %wide = zext <16 x i32> %indices to <16 x i64>
; NVL-NEXT: %offset = extractelement <16 x i64> %wide, i64 3
define i8 @computed(ptr %idx, ptr %base) {
  %loaded = load <16 x i32>, ptr %idx, align 4
  %indices = add <16 x i32> %loaded, splat (i32 2)
  %wide = zext <16 x i32> %indices to <16 x i64>
  %offset = extractelement <16 x i64> %wide, i64 3
  %address = getelementptr i8, ptr %base, i64 %offset
  %value = load i8, ptr %address, align 1
  ret i8 %value
}

; NVL-LABEL: define i8 @select_fed(
; NVL: %wide = zext <16 x i32> %indices to <16 x i64>
; NVL-NEXT: %offset = extractelement <16 x i64> %wide, i64 3
define i8 @select_fed(ptr %idx, ptr %base, <16 x i1> %mask) {
  %loaded = load <16 x i32>, ptr %idx, align 4
  %indices = select <16 x i1> %mask, <16 x i32> %loaded, <16 x i32> zeroinitializer
  %wide = zext <16 x i32> %indices to <16 x i64>
  %offset = extractelement <16 x i64> %wide, i64 3
  %address = getelementptr i8, ptr %base, i64 %offset
  %value = load i8, ptr %address, align 1
  ret i8 %value
}

; NVL-LABEL: define i8 @dynamic(
; NVL: %wide = zext <16 x i32> %indices to <16 x i64>
; NVL-NEXT: %offset = extractelement <16 x i64> %wide, i64 %lane
define i8 @dynamic(ptr %idx, ptr %base, i64 %lane) {
  %indices = load <16 x i32>, ptr %idx, align 4
  %wide = zext <16 x i32> %indices to <16 x i64>
  %offset = extractelement <16 x i64> %wide, i64 %lane
  %address = getelementptr i8, ptr %base, i64 %offset
  %value = load i8, ptr %address, align 1
  ret i8 %value
}

; NVL-LABEL: define i16 @wider(
; NVL: %wide = zext <16 x i32> %indices to <16 x i64>
; NVL-NEXT: %offset = extractelement <16 x i64> %wide, i64 3
define i16 @wider(ptr %idx, ptr %base) {
  %indices = load <16 x i32>, ptr %idx, align 4
  %wide = zext <16 x i32> %indices to <16 x i64>
  %offset = extractelement <16 x i64> %wide, i64 3
  %address = getelementptr i16, ptr %base, i64 %offset
  %value = load i16, ptr %address, align 1
  ret i16 %value
}

; NVL-LABEL: define i8 @volatile_indices(
; NVL: %wide = zext <16 x i32> %indices to <16 x i64>
; NVL-NEXT: %offset = extractelement <16 x i64> %wide, i64 3
define i8 @volatile_indices(ptr %idx, ptr %base) {
  %indices = load volatile <16 x i32>, ptr %idx, align 4
  %wide = zext <16 x i32> %indices to <16 x i64>
  %offset = extractelement <16 x i64> %wide, i64 3
  %address = getelementptr i8, ptr %base, i64 %offset
  %value = load i8, ptr %address, align 1
  ret i8 %value
}
