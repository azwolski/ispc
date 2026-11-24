// REQUIRES: X86_ENABLED && LLVM_22_0+
// RUN: %{ispc} %s --arch=x86-64 --target=avx10.2nvl-x8 --addressing=32 -O3 --woff --emit-asm -o - | FileCheck %s

struct Point {
    float c[4];
};

// CHECK-LABEL: packed_moments:
// CHECK-NOT: vgatherqps
// CHECK: [[LOOP:\.LBB[0-9]+_[0-9]+]]:{{.*}}Inner Loop Header
// CHECK-COUNT-4: vgatherdps
// CHECK-NOT: vgather{{[qd]}}ps
// CHECK: jb [[LOOP]]
// CHECK-NOT: vgatherqps
// CHECK-COUNT-4: vgatherdps
// CHECK-NOT: vgather{{[qd]}}ps
// CHECK: .Lfunc_end
export void packed_moments(const uniform Point pts[], uniform int n, uniform float out[]) {
    float s[4] = {0}, q = 0;
    foreach (i = 0 ... n) {
        Point p = pts[i];
        for (uniform int k = 0; k < 4; ++k) {
            s[k] += p.c[k];
            q += p.c[k] * p.c[k];
        }
    }
    for (uniform int k = 0; k < 4; ++k)
        out[k] = reduce_add(s[k]);
    out[4] = reduce_add(q);
}
