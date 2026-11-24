#ifdef ISPC
export void copy(uniform int64 dst[], const uniform int64 src[], uniform int n) {
    foreach (i = 0 ... n) {
        dst[i] = src[i];
    }
}

export void copy_with_or(uniform int64 dst[], const uniform int64 src[], uniform int n) {
    foreach (i = 0 ... n) {
        dst[i] |= src[i];
    }
}

export void clear_bytes(uniform int8 dst[], uniform int n) {
    foreach (i = 0 ... n) {
        dst[i] = 0;
    }
}

export uniform int64 copy_and_sum(uniform int64 dst[], const uniform int64 src[], uniform int n) {
    uniform int64 total = 0;
    foreach (i = 0 ... n) {
        int64 value = src[i];
        dst[i] = value;
        total += reduce_add(value);
    }
    return total;
}
#else
#include <stdio.h>

int main(void) {
    enum { capacity = 32, sentinel = 256 };
    int64_t src[capacity];
    for (int i = 0; i < capacity; ++i) {
        src[i] = i * 3 + 1;
    }
    for (int n = -7; n <= capacity; ++n) {
        int64_t copied[capacity], combined[capacity], summed[capacity];
        int8_t cleared[capacity];
        for (int i = 0; i < capacity; ++i) {
            copied[i] = combined[i] = summed[i] = sentinel;
            cleared[i] = 7;
        }
        copy(copied, src, n);
        copy_with_or(combined, src, n);
        clear_bytes(cleared, n);
        int64_t total = copy_and_sum(summed, src, n);
        int64_t expected_total = 0;
        for (int i = 0; i < capacity; ++i) {
            int64_t value = i * 3 + 1;
            int active = i < n;
            expected_total += active ? value : 0;
            if (src[i] != value || copied[i] != (active ? value : sentinel) ||
                combined[i] != (active ? sentinel | value : sentinel) ||
                summed[i] != (active ? value : sentinel) || cleared[i] != (active ? 0 : 7)) {
                fprintf(stderr, "unexpected memory contents for n=%d at i=%d\n", n, i);
                return 1;
            }
        }
        if (total != expected_total) {
            fprintf(stderr, "unexpected reduction for n=%d\n", n);
            return 1;
        }
    }
    return 0;
}
#endif
