#ifndef REALTIME_ATOMICS_H
#define REALTIME_ATOMICS_H

#include <stdbool.h>
#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct RTAtomicUInt8 RTAtomicUInt8;

RTAtomicUInt8 *rt_atomic_u8_create(uint8_t initial_value);
void rt_atomic_u8_destroy(RTAtomicUInt8 *atomic_value);
uint8_t rt_atomic_u8_load_acquire(const RTAtomicUInt8 *atomic_value);
bool rt_atomic_u8_is_lock_free(const RTAtomicUInt8 *atomic_value);
void rt_atomic_u8_store_release(
    RTAtomicUInt8 *atomic_value,
    uint8_t desired
);
bool rt_atomic_u8_compare_exchange_acq_rel(
    RTAtomicUInt8 *atomic_value,
    uint8_t expected,
    uint8_t desired
);
uint8_t rt_atomic_u8_exchange_acq_rel(
    RTAtomicUInt8 *atomic_value,
    uint8_t desired
);

#if defined(__cplusplus)
}
#endif

#endif
