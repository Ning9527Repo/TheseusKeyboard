#include "../src/NTKLeasePolicy.h"
#include <assert.h>
#include <stdio.h>
#include <limits.h>
static unsigned checks;
#define CHECK(x) do { ++checks; assert(x); } while (0)
int main(void) {
    CHECK(!NTKLeaseIsFresh(0, 10000));
    CHECK(!NTKMakeLease(0, 42));
    CHECK(!NTKMakeLease(100, 0));
    CHECK(!NTKMakeLease(100, UINT32_MAX));
    CHECK(!NTKMakeLease(UINT64_MAX, 1));
    uint64_t starts[] = {1, 1000, 10000000, UINT64_C(4294967296)};
    for (unsigned s = 0; s < sizeof(starts)/sizeof(*starts); ++s) {
        for (uint32_t owner = 1; owner < 64; ++owner) {
            uint64_t began = starts[s], lease = NTKMakeLease(began, owner);
            CHECK(NTKLeaseOwner(lease) == owner);
            CHECK(NTKLeaseTime(lease) == began);
            CHECK(NTKLeaseIsFresh(lease, began));
            CHECK(!NTKLeaseIsFresh(lease, began - 1));
            CHECK(NTKLeaseIsFresh(lease, began + NTK_LEASE_TTL_MS - 1));
            CHECK(!NTKLeaseIsFresh(lease, began + NTK_LEASE_TTL_MS));
            CHECK(!NTKLeaseIsFresh(lease, began + NTK_LEASE_TTL_MS + 1));
            for (uint64_t delay = 0; delay < 2100; delay += 7) {
                uint64_t ack = NTKMakeLease(began + delay, owner);
                CHECK(NTKAckMatches(lease, ack, began, began + delay) == (delay < NTK_LEASE_TTL_MS));
                CHECK(!NTKAckMatches(lease, NTKMakeLease(began + delay, owner + 1), began, began + delay));
                CHECK(!NTKAckMatches(lease, ack, began + delay + 1, began + delay));
                CHECK(!NTKAckMatches(0, ack, began, began + delay));
            }
        }
    }
    CHECK(NTKDockedRegion(0, 500, 430, 432, 430, 932));
    CHECK(NTKDockedRegion(0, 180, 932, 250, 932, 430));
    CHECK(!NTKDockedRegion(80, 400, 280, 250, 430, 932));
    CHECK(!NTKDockedRegion(0, 500, 210, 432, 430, 932));
    CHECK(!NTKDockedRegion(0, 0, 430, 932, 430, 932));
    CHECK(!NTKDockedRegion(0, 500, 430, 20, 430, 932));
    CHECK(!NTKDockedRegion(0, 500, 430, 432, 0, 932));
    CHECK(!NTKDockedRegion(NAN, 500, 430, 432, 430, 932));
    CHECK(!NTKDockedRegion(0, INFINITY, 430, 432, 430, 932));
    CHECK(!NTKDockedRegion(0, 500, INFINITY, 432, 430, 932));
    printf("LEASE_GEOMETRY_OK %u assertions\n", checks);
    return 0;
}
