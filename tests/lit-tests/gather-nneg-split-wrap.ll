; Regression coverage for an all-equal gather that folds to a scalar load.
; For x = INT32_MAX and y = 1, both original nsw adds are defined
; and the original offset is zero. Regrouping x + y at i32 width
; and independently sign extending it and INT32_MIN would read 4 GiB
; below the base. The oracle maps both addresses and checks the result.
;
; RUN: %{ispc-opt} --target=sse4-i32x4 --addressing=32 --passes=improve-memory-ops %s -o %t-sse4.ll
; RUN: %{cc} -O2 -x ir %t-sse4.ll -x c %S/gather-nneg-split-wrap.inc -o %t-sse4.bin
; RUN: %t-sse4.bin
; RUN: %{ispc-opt} --target=avx1-i32x4 --addressing=32 --passes=improve-memory-ops %s -o %t-avx1.ll
; RUN: %{cc} -O2 -x ir %t-avx1.ll -x c %S/gather-nneg-split-wrap.inc -o %t-avx1.bin
; RUN: %t-avx1.bin
; REQUIRES: X86_ENABLED, X86_64_HOST, LINUX_ENABLED, LLVM_20_0+

declare <4 x i64> @__pseudo_gather64_i64(<4 x i64>, <4 x i32>)
declare <4 x i64> @__pseudo_gather_base_offsets32_i64(ptr, i32, <4 x i32>, <4 x i32>)
declare <4 x i64> @__pseudo_gather_base_offsets64_i64(ptr, i32, <4 x i64>, <4 x i32>)
declare <4 x i64> @__pseudo_gather_factored_base_offsets32_i64(ptr, <4 x i32>, i32, <4 x i32>, <4 x i32>)
declare <4 x i64> @__pseudo_gather_factored_base_offsets64_i64(ptr, <4 x i64>, i32, <4 x i64>, <4 x i32>)

define i64 @read_split(ptr %base, i32 noundef %xs, i32 noundef %ys) {
  %xi = insertelement <4 x i32> poison, i32 %xs, i32 0
  %x = shufflevector <4 x i32> %xi, <4 x i32> poison, <4 x i32> zeroinitializer
  %yi = insertelement <4 x i32> poison, i32 %ys, i32 0
  %y = shufflevector <4 x i32> %yi, <4 x i32> poison, <4 x i32> zeroinitializer
  %a = add nsw <4 x i32> %x, splat (i32 -2147483648)
  %b = add nsw <4 x i32> %a, %y
  %off = zext nneg <4 x i32> %b to <4 x i64>
  %baseint = ptrtoint ptr %base to i64
  %bi = insertelement <4 x i64> poison, i64 %baseint, i32 0
  %bases = shufflevector <4 x i64> %bi, <4 x i64> poison, <4 x i32> zeroinitializer
  %addresses = add <4 x i64> %bases, %off
  %v = call <4 x i64> @__pseudo_gather64_i64(<4 x i64> %addresses, <4 x i32> splat (i32 -1))
  %r = extractelement <4 x i64> %v, i32 0
  ret i64 %r
}
