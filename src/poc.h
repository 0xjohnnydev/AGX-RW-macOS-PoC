#ifndef POC_H
#define POC_H

#include <IOKit/IOKitLib.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PAGE_SIZE_16K 0x4000ULL

struct PocContext {
    io_connect_t connection;
    uint64_t task;
    uint64_t ipc_space;
    uint64_t device;
    uint64_t gpu_task;
    uint64_t namespace_address;

    uint64_t iogpu;
    uint64_t drop_map;
    uint64_t firmware_task;
    uint64_t mdsid_table;
    uint8_t mdsid_table_saved[0x20];
    uint32_t gpu_offset;
    uint32_t command_argument_size;
    uint32_t new_queue_argument_size;

    uint32_t queue_id;
    void *read_output_address;
    uint64_t read_output_gpu_address;
    size_t read_output_size;
    uint64_t marker_cpu_address;
    uint64_t marker_gpu_address;
    uint64_t marker_saved;
    bool marker_dirty;
    uint32_t command_buffer_ids[2];
    void *command_buffer_addresses[2];
};

extern struct PocContext gPoc;

int poc_init(void);
int poc_init_neo(void);
int poc_init_client(void);
int poc_run(void);
void poc_deinit(void);

#endif
