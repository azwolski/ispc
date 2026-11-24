; REQUIRES: X86_ENABLED && LLVM_22_0+
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %s -o - | FileCheck %s --check-prefix=NARROW
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=64 --passes=improve-memory-ops %s -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed -e 's/declare <8 x float>/declare fastcc <8 x float>/g' -e 's/call <8 x float>/call fastcc <8 x float>/' %s > %t.fastcc.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.fastcc.ll -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed '/^declare.*offsets32/s/ptr,/ptr addrspace(1),/' %s > %t.addrspace.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.addrspace.ll -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed '/^declare.*offsets32/s/<8 x i1>/<8 x i32>/' %s > %t.signature.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.signature.ll -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed 's/splat (i1 true))/<i1 true, i1 true, i1 true, i1 true, i1 true, i1 true, i1 true, i1 undef>)/' %s > %t.undef.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.undef.ll -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed 's/splat (i1 true))/<i1 true, i1 true, i1 true, i1 true, i1 true, i1 true, i1 true, i1 poison>)/' %s > %t.poison.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.poison.ll -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed 's/splat (i1 true))/<i1 true, i1 true, i1 true, i1 true, i1 true, i1 true, i1 true, i1 false>)/' %s > %t.inactive.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.inactive.ll -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed '/^  %value/s/$/ [ "deopt"(i32 0) ]/' %s > %t.bundle.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.bundle.ll -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed '/^declare.*offsets32/s/ptr,/ptr align 256,/' %s > %t.aligned.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.aligned.ll -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed '/^  %value/s/call /notail call /' %s > %t.notail.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.notail.ll -o - | FileCheck %s --check-prefix=KEEP
; RUN: sed -e '/^define/s/i32 %counter)/i32 %counter, <8 x i1> %mask)/' -e '/^  %value/s/splat (i1 true)/%mask/' %s > %t.dynamic.ll
; RUN: %{ispc-opt} --target=avx10.2nvl-x8 --addressing=32 --passes=improve-memory-ops %t.dynamic.ll -o - | FileCheck %s --check-prefix=KEEP

; The unflagged i32 shift models both the unsigned sign boundary and wrap.
; Narrow only when the lane and field offsets fit below the aligned origin.
declare <8 x float> @__pseudo_gather_base_offsets64_float(ptr, i32, <8 x i64>, <8 x i1>) memory(read)
declare <8 x float> @__pseudo_gather_base_offsets32_float(ptr, i32, <8 x i32>, <8 x i1>) memory(read)

; NARROW-LABEL: define <8 x float> @packed(
; NARROW: [[LOW:%.*]] = extractelement <8 x i32> %bytes, i64 0
; NARROW-NEXT: [[ORIGIN:%.*]] = zext i32 [[LOW]] to i64
; NARROW-NEXT: [[BASE:%.*]] = getelementptr i8, ptr %base, i64 [[ORIGIN]]
; NARROW-NEXT: call <8 x float> @__pseudo_gather_base_offsets32_float(ptr [[BASE]], i32 1, <8 x i32> <i32 12, i32 28, i32 44, i32 60, i32 76, i32 92, i32 108, i32 124>, <8 x i1> splat (i1 true))
; KEEP-LABEL: define <8 x float> @packed(
; KEEP-NOT: @__pseudo_gather_base_offsets32_float
; KEEP: call {{(fastcc )?}}<8 x float> @__pseudo_gather_base_offsets64_float(ptr %base, i32 1, <8 x i64> %indices,
; KEEP: ret
define <8 x float> @packed(ptr %base, i32 %counter) {
  %seed = insertelement <8 x i32> poison, i32 %counter, i64 0
  %splat = shufflevector <8 x i32> %seed, <8 x i32> poison, <8 x i32> zeroinitializer
  %lanes = or disjoint <8 x i32> %splat, <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
  %bytes = shl <8 x i32> %lanes, splat (i32 4)
  %field = or disjoint <8 x i32> %bytes, splat (i32 12)
  %indices = zext <8 x i32> %field to <8 x i64>
  %value = call <8 x float> @__pseudo_gather_base_offsets64_float(ptr %base, i32 1, <8 x i64> %indices, <8 x i1> splat (i1 true))
  ret <8 x float> %value
}
