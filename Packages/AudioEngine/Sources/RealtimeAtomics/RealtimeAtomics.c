#include "RealtimeAtomics.h"

#include <stdatomic.h>
#include <stdlib.h>

struct RTAtomicUInt8 {
    _Atomic uint8_t value;
};

RTAtomicUInt8 *rt_atomic_u8_create(uint8_t initial_value) {
    RTAtomicUInt8 *atomic_value = malloc(sizeof(RTAtomicUInt8));
    if (atomic_value == NULL) {
        return NULL;
    }
    atomic_init(&atomic_value->value, initial_value);
    return atomic_value;
}

void rt_atomic_u8_destroy(RTAtomicUInt8 *atomic_value) {
    free(atomic_value);
}

uint8_t rt_atomic_u8_load_acquire(const RTAtomicUInt8 *atomic_value) {
    return atomic_load_explicit(
        &atomic_value->value,
        memory_order_acquire
    );
}

bool rt_atomic_u8_is_lock_free(const RTAtomicUInt8 *atomic_value) {
    return atomic_is_lock_free(&atomic_value->value);
}

void rt_atomic_u8_store_release(
    RTAtomicUInt8 *atomic_value,
    uint8_t desired
) {
    atomic_store_explicit(
        &atomic_value->value,
        desired,
        memory_order_release
    );
}

bool rt_atomic_u8_compare_exchange_acq_rel(
    RTAtomicUInt8 *atomic_value,
    uint8_t expected,
    uint8_t desired
) {
    return atomic_compare_exchange_strong_explicit(
        &atomic_value->value,
        &expected,
        desired,
        memory_order_acq_rel,
        memory_order_acquire
    );
}

uint8_t rt_atomic_u8_exchange_acq_rel(
    RTAtomicUInt8 *atomic_value,
    uint8_t desired
) {
    return atomic_exchange_explicit(
        &atomic_value->value,
        desired,
        memory_order_acq_rel
    );
}
