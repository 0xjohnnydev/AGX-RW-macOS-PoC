#include "target.h"

#include <libkextrw.h>
#include <mach/kern_return.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>

#define DROP_COMMAND_WORDS 6U
#define DROP_COMMAND_TYPE 20U
#define COPYOUT_COMMAND_TYPE 32U
#define TARGET_BUILD "26A434"

struct TargetBinding {
    const char *model;
    const struct TargetProfile *profile;
};

static const uint32_t drop_g16[] = {
    UINT32_C(0x8b14081c), UINT32_C(0xb94592b5),
    UINT32_C(0xb9404b68), UINT32_C(0xf9001be8),
    UINT32_C(0xb9400368), UINT32_C(0xf90017e8),
};

static const uint32_t drop_g17g[] = {
    UINT32_C(0x8b14081c), UINT32_C(0xb945a2bb),
    UINT32_C(0xb9404b48), UINT32_C(0xf9001be8),
    UINT32_C(0xb9400356), UINT32_C(0xf9400728),
};

static const struct TargetProfile g16x_26a434 = {
    .family = "g16x",
    .proc_hash_table = UINT64_C(0xfffffe000cb63a58),
    .iomachport_vtable = UINT64_C(0xfffffe0007f40200),
    .agx_userclient_vtable = UINT64_C(0xfffffe0007f92308),
    .drop_command = UINT64_C(0xfffffe0008b78d64),
    .drop_command_words = drop_g16,
    .agx_firmware_vtable = UINT64_C(0xfffffe0007f952d0),
    .device_control_ring_vtable = UINT64_C(0xfffffe0007f94338),
    .command_role_table = 0,
    .apple_ascwrap_v6_inbox = UINT64_C(0xfffffe0008c2ec64),
    .gfx_copyout_table = UINT64_C(0xfffffc000006f540),
    .accelerator_firmware = UINT64_C(0x598),
    .dsids_supported = UINT64_C(0x10a1c),
    .drop_state = UINT64_C(0x138e0),
    .drop_counter = UINT64_C(0x19948),
    .drop_gpu_offset = UINT64_C(0x590),
    .drop_owner = UINT64_C(0x1a4c8),
    .firmware_device_ring_base = UINT64_C(0x878),
    .firmware_channel_base = UINT64_C(0x1610),
};

static const struct TargetProfile g17g_26a434 = {
    .family = "g17g",
    .proc_hash_table = UINT64_C(0xfffffe000cc68fc8),
    .iomachport_vtable = UINT64_C(0xfffffe0007f593f8),
    .agx_userclient_vtable = UINT64_C(0xfffffe0007faa1e0),
    .drop_command = UINT64_C(0xfffffe0008b7c8e4),
    .drop_command_words = drop_g17g,
    .agx_firmware_vtable = UINT64_C(0xfffffe0007fad1c0),
    .device_control_ring_vtable = UINT64_C(0xfffffe0007fac210),
    .command_role_table = UINT64_C(0xfffffe000714fa40),
    .apple_ascwrap_v6_inbox = UINT64_C(0xfffffe0008c371d4),
    .gfx_copyout_table = UINT64_C(0xfffffc000005b7a0),
    .accelerator_firmware = UINT64_C(0x5a8),
    .dsids_supported = UINT64_C(0x10a2c),
    .drop_state = UINT64_C(0x139d8),
    .drop_counter = UINT64_C(0x19a40),
    .drop_gpu_offset = UINT64_C(0x5a0),
    .drop_owner = UINT64_C(0x1a5c0),
    .firmware_device_ring_base = UINT64_C(0xac0),
    .firmware_channel_base = UINT64_C(0x19c8),
};

static const struct TargetProfile g17p_26a434 = {
    .family = "g17p",
    .neo = true,
    .proc_hash_table = UINT64_C(0xfffffe000c829bb8),
    .iomachport_vtable = UINT64_C(0xfffffe0007e83ad8),
    .agx_userclient_vtable = UINT64_C(0xfffffe0007ed6310),
    .drop_command = UINT64_C(0xfffffe0008a50930),
    .drop_command_words = drop_g16,
    .agx_firmware_vtable = UINT64_C(0xfffffe0007ed92e8),
    .device_control_ring_vtable = UINT64_C(0xfffffe0007ed8340),
    .command_role_table = UINT64_C(0xfffffe000714fa50),
    .apple_ascwrap_v6_inbox = UINT64_C(0xfffffe0008b08a64),
    .gfx_copyout_table = UINT64_C(0xfffffc000005b7a0),
    .accelerator_firmware = UINT64_C(0x598),
    .dsids_supported = UINT64_C(0x10a1c),
    .drop_state = UINT64_C(0x139a0),
    .drop_counter = UINT64_C(0x19a08),
    .drop_gpu_offset = UINT64_C(0x590),
    .drop_owner = UINT64_C(0x1a588),
    .firmware_device_ring_base = UINT64_C(0xab8),
    .firmware_channel_base = UINT64_C(0x1980),
};

static const struct TargetBinding bindings[] = {
    {"Mac16,5", &g16x_26a434},
    {"Mac16,6", &g16x_26a434},
    {"Mac16,9", &g16x_26a434},
    {"Mac16,7", &g16x_26a434},
    {"Mac16,8", &g16x_26a434},
    {"Mac16,11", &g16x_26a434},
    {"Mac17,2", &g17g_26a434},
    {"Mac17,3", &g17g_26a434},
    {"Mac17,4", &g17g_26a434},
    {"Mac17,5", &g17p_26a434},
};

const struct TargetProfile *gTarget;

static bool read_sysctl_string(const char *name, char *value, size_t capacity)
{
    size_t size = capacity;
    if (capacity == 0 || sysctlbyname(name, value, &size, NULL, 0) != 0 ||
        size == 0 || size > capacity || value[size - 1] != '\0') {
        return false;
    }
    return true;
}

static const struct TargetProfile *find_profile(const char *model)
{
    for (size_t i = 0; i < sizeof(bindings) / sizeof(bindings[0]); i++) {
        if (strcmp(model, bindings[i].model) == 0) return bindings[i].profile;
    }
    return NULL;
}

static bool validate_profile(const struct TargetProfile *profile)
{
    uint32_t words[DROP_COMMAND_WORDS] = {0};
    if (get_kernel_base() == 0 ||
        kreadbuf(kslide(profile->drop_command), words, sizeof(words)) !=
            KERN_SUCCESS ||
        memcmp(words, profile->drop_command_words, sizeof(words)) != 0) {
        return false;
    }

    if (profile->command_role_table != 0) {
        uint64_t roles = kslide(profile->command_role_table);
        if (kread32(roles + DROP_COMMAND_TYPE * sizeof(uint32_t)) != 0 ||
            kread32(roles + COPYOUT_COMMAND_TYPE * sizeof(uint32_t)) != 0) {
            return false;
        }
    }
    return true;
}

int target_init(bool neo_only)
{
    if (gTarget != NULL) return neo_only && !gTarget->neo ? -1 : 0;

    char model[64] = {0};
    char build[64] = {0};
    if (!read_sysctl_string("hw.model", model, sizeof(model)) ||
        !read_sysctl_string("kern.osversion", build, sizeof(build))) {
        fputs("target   failure=sysctl\n", stderr);
        return -1;
    }

    const struct TargetProfile *profile = find_profile(model);
    if (strcmp(build, TARGET_BUILD) != 0 || profile == NULL ||
        (neo_only && !profile->neo)) {
        fprintf(stderr, "target   model=%s build=%s failure=unsupported\n",
                model, build);
        return -1;
    }
    if (!validate_profile(profile)) {
        fprintf(stderr, "target   model=%s build=%s failure=validation\n",
                model, build);
        return -1;
    }

    gTarget = profile;
    printf("target   model=%s build=%s family=%s\n",
           model, build, profile->family);
    return 0;
}
