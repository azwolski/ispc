; A 32-bit native gather sign extends its index before scaling. On defined
; lanes, zext nneg has the same value as sext; an ordinary zext does not.
;
; RUN: %{ispc-opt} --target=avx2-i32x8 --addressing=32 --passes=improve-memory-ops %s -o - | FileCheck %s --check-prefix=A32
; RUN: %{ispc-opt} --target=avx2-i32x8 --addressing=64 --passes=improve-memory-ops %s -o - | FileCheck %s --check-prefix=A64
; REQUIRES: X86_ENABLED, LLVM_20_0+

declare <8 x float> @__pseudo_gather64_float(<8 x i64>, <8 x i32>)
declare <8 x float> @__pseudo_gather_base_offsets64_float(ptr, i32, <8 x i64>, <8 x i32>)
declare <8 x float> @__pseudo_gather_base_offsets32_float(ptr, i32, <8 x i32>, <8 x i32>)

; A32-LABEL: define <8 x float> @signed_index(
; A32: call <8 x float> @__pseudo_gather_base_offsets32_float(ptr {{[^,]+}}, i32 1, <8 x i32> %index,
; A64-LABEL: define <8 x float> @signed_index(
; A64: call <8 x float> @__pseudo_gather_base_offsets64_float(
define <8 x float> @signed_index(ptr %base, <8 x i32> %index, <8 x i32> %mask) {
  %wide = sext <8 x i32> %index to <8 x i64>
  %baseint = ptrtoint ptr %base to i64
  %insert = insertelement <8 x i64> poison, i64 %baseint, i32 0
  %bases = shufflevector <8 x i64> %insert, <8 x i64> poison, <8 x i32> zeroinitializer
  %addresses = add <8 x i64> %bases, %wide
  %value = call <8 x float> @__pseudo_gather64_float(<8 x i64> %addresses, <8 x i32> %mask)
  ret <8 x float> %value
}

; A32-LABEL: define <8 x float> @nonnegative_index(
; A32: call <8 x float> @__pseudo_gather_base_offsets32_float(ptr {{[^,]+}}, i32 1, <8 x i32> %index,
; A64-LABEL: define <8 x float> @nonnegative_index(
; A64: call <8 x float> @__pseudo_gather_base_offsets64_float(
define <8 x float> @nonnegative_index(ptr %base, <8 x i32> %index, <8 x i32> %mask) {
  %wide = zext nneg <8 x i32> %index to <8 x i64>
  %baseint = ptrtoint ptr %base to i64
  %insert = insertelement <8 x i64> poison, i64 %baseint, i32 0
  %bases = shufflevector <8 x i64> %insert, <8 x i64> poison, <8 x i32> zeroinitializer
  %addresses = add <8 x i64> %bases, %wide
  %value = call <8 x float> @__pseudo_gather64_float(<8 x i64> %addresses, <8 x i32> %mask)
  ret <8 x float> %value
}

; A32-LABEL: define <8 x float> @unsigned_index(
; A32: call <8 x float> @__pseudo_gather_base_offsets64_float(
; A64-LABEL: define <8 x float> @unsigned_index(
; A64: call <8 x float> @__pseudo_gather_base_offsets64_float(
define <8 x float> @unsigned_index(ptr %base, <8 x i32> %index, <8 x i32> %mask) {
  %wide = zext <8 x i32> %index to <8 x i64>
  %baseint = ptrtoint ptr %base to i64
  %insert = insertelement <8 x i64> poison, i64 %baseint, i32 0
  %bases = shufflevector <8 x i64> %insert, <8 x i64> poison, <8 x i32> zeroinitializer
  %addresses = add <8 x i64> %bases, %wide
  %value = call <8 x float> @__pseudo_gather64_float(<8 x i64> %addresses, <8 x i32> %mask)
  ret <8 x float> %value
}
