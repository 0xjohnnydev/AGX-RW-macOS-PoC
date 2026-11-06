#ifndef TARGET_H
#define TARGET_H

#include <stdbool.h>
#include <stdint.h>

struct TargetProfile {
    const char *family;
    bool neo;

    uint64_t proc_hash_table;
    uint64_t iomachport_vtable;
    uint64_t agx_userclient_vtable;
    uint64_t drop_command;
    const uint32_t *drop_command_words;

    uint64_t agx_firmware_vtable;
    uint64_t device_control_ring_vtable;
    uint64_t command_role_table;
    uint64_t apple_ascwrap_v6_inbox;
    uint64_t gfx_copyout_table;

    uint64_t accelerator_firmware;
    uint64_t dsids_supported;
    uint64_t drop_state;
    uint64_t drop_counter;
    uint64_t drop_gpu_offset;
    uint64_t drop_owner;
    uint64_t firmware_device_ring_base;
    uint64_t firmware_channel_base;
};

extern const struct TargetProfile *gTarget;

int target_init(bool neo_only);

#endif
