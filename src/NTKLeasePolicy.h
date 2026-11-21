#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

// A lease contains only monotonic time and an owner id; never pixels or input.
#define NTK_LEASE_OWNER_BITS 22u
#define NTK_LEASE_OWNER_MASK ((UINT64_C(1) << NTK_LEASE_OWNER_BITS) - 1)
#define NTK_LEASE_TTL_MS UINT64_C(1800)
static inline uint64_t NTKLeaseOwner(uint64_t lease) {
    return lease & NTK_LEASE_OWNER_MASK;
}
static inline uint64_t NTKLeaseTime(uint64_t lease) {
    return lease >> NTK_LEASE_OWNER_BITS;
}
static inline uint64_t NTKMakeLease(uint64_t now, uint32_t owner) {
    if (!now || !owner || owner > NTK_LEASE_OWNER_MASK ||
        now > (UINT64_MAX >> NTK_LEASE_OWNER_BITS)) return 0;
    return (now << NTK_LEASE_OWNER_BITS) | owner;
}
static inline bool NTKLeaseIsFresh(uint64_t lease, uint64_t now) {
    uint64_t stamp = NTKLeaseTime(lease);
    return NTKLeaseOwner(lease) && stamp && now >= stamp && now - stamp < NTK_LEASE_TTL_MS;
}
static inline bool NTKAckMatches(uint64_t lease, uint64_t ack, uint64_t started, uint64_t now) {
    return NTKLeaseIsFresh(lease, now) && NTKLeaseIsFresh(ack, now) &&
        NTKLeaseOwner(lease) == NTKLeaseOwner(ack) && NTKLeaseTime(ack) >= started;
}
// Only main-screen docked phone keyboards. Floating/split regions stay native.
static inline bool NTKDockedRegion(double x, double y, double w, double h, double sw, double sh) {
    return isfinite(x) && isfinite(y) && isfinite(w) && isfinite(h) &&
        isfinite(sw) && isfinite(sh) && sw > 0 && sh > 0 && x >= -3 && y >= 0 &&
        w >= sw * 0.8 && x + w <= sw + 3 && h >= 100 && h <= sh * 0.75 &&
        fabs(y + h - sh) <= 3;
}
