// Check that pre/post increment/decrement of an expression whose value can't
// be emitted (impossible gather) reports an error instead of crashing.
// RUN: not %{ispc} --target=host --nowrap --nostdlib %s -o - 2>&1 | FileCheck %s

// CHECK-NOT: FATAL ERROR
// CHECK: Error: Gather operation is impossible due to the presence of struct member "a" with uniform type
// CHECK-NOT: FATAL ERROR

struct S {
    uniform int a;
    int b;
};

void foo(varying S * uniform arr[4], int idx) {
    arr[idx]++;
}
