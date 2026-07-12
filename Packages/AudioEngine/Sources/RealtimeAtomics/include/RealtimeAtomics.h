#ifndef REALTIME_ATOMICS_H
#define REALTIME_ATOMICS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct RTAtomicUInt8 RTAtomicUInt8;

RTAtomicUInt8 * _Nullable rt_atomic_u8_create(uint8_t initial_value);
void rt_atomic_u8_destroy(RTAtomicUInt8 * _Nullable atomic_value);
uint8_t rt_atomic_u8_load_acquire(
    const RTAtomicUInt8 * _Nonnull atomic_value
);
bool rt_atomic_u8_is_lock_free(
    const RTAtomicUInt8 * _Nonnull atomic_value
);
void rt_atomic_u8_store_release(
    RTAtomicUInt8 * _Nonnull atomic_value,
    uint8_t desired
);
bool rt_atomic_u8_compare_exchange_acq_rel(
    RTAtomicUInt8 * _Nonnull atomic_value,
    uint8_t expected,
    uint8_t desired
);
uint8_t rt_atomic_u8_exchange_acq_rel(
    RTAtomicUInt8 * _Nonnull atomic_value,
    uint8_t desired
);

bool rt_spectrum_mailbox_submit(
    void * _Nonnull context,
    const float * _Nonnull samples,
    intptr_t count
);
typedef void (*RTSpectrumReleaseFunction)(void * _Nonnull context);

void rt_audio_node_install_spectrum_tap(
    void * _Nonnull node,
    uint32_t bus,
    uint32_t buffer_size,
    void * _Nonnull submit_context,
    void * _Nonnull lifetime_context,
    RTSpectrumReleaseFunction _Nonnull release_lifetime
);

#if defined(__cplusplus)
}
#endif

#endif
