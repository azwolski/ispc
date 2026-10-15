// Regression test for CodeQL alert 20: unary '!' and '~' must not crash when
// the operand's code generation fails after an error has been reported.

// RUN: not %{ispc} --target=host --nowrap --nostdlib %s -o - 2>&1 | FileCheck %s

// CHECK: Error: Illegal to pass a "varying" lvalue to a reference parameter
// CHECK: Error: Illegal to pass a "varying" lvalue to a reference parameter
// CHECK-NOT: FATAL ERROR

bool f(int &x) { return x > 0; }
int h(int &x) { return x; }

bool logical_not(uniform int arr[]) { return !f(arr[programIndex]); }

int bit_not(uniform int arr[]) { return ~h(arr[programIndex]); }
