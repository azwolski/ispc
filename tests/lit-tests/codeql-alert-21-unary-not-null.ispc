// Check that ISPC reports an error and does not crash when the operand of
// a unary "~" or "!" fails to generate a value (here due to an invalid
// reference initializer). CodeQL alert 21.
// RUN: not %{ispc} %s --nowrap --nostdlib --target=host -o %t.o 2>&1 | FileCheck %s

// CHECK: Error: Initializer for reference-type variable "r" must have an lvalue type.
// CHECK: Error: Initializer for reference-type variable "s" must have an lvalue type.
// CHECK-NOT: FATAL ERROR
int bitnot(int a) {
    int &r = a + 1;
    return ~r;
}

bool lognot(bool a) {
    bool &s = a && true;
    return !s;
}
