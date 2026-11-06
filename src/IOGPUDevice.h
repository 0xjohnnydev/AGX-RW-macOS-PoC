#ifndef IOGPUDEVICE_H
#define IOGPUDEVICE_H

#include <stdint.h>

int IOGPU_setup_command_buffers(void);
int IOGPU_setup_mdsid_table(void);
int IOGPU_submit_command_buffers(void);
int IOGPU_set_submit_pair(unsigned first, unsigned second);
int IOGPU_wait_device_control_idle(unsigned stable_milliseconds);
int IOGPU_create_shared_page(void **address);
int IOGPU_find_read_output(void);
int IOGPU_resolve_firmware_cpu_alias(uint64_t gpu_address,
                                     uint64_t *cpu_address);

#endif
