// RUN: %{ispc} %s -O3 --pic --target=sse2-i32x4 --arch=x86-64 -h %t.h -o %t.o
// RUN: %{cc} -O2 -x c -c %S/foreach-copy-countdown.inc -include %t.h -o %t.c.o
// RUN: %{cc} %t.o %t.c.o -o %t.bin
// RUN: %t.bin
// REQUIRES: LINUX_HOST && X86_ENABLED && X86_64_HOST

#include "foreach-copy-countdown.inc"
