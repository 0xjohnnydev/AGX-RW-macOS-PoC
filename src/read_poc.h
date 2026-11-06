#ifndef READ_POC_H
#define READ_POC_H

#include <stdbool.h>
#include <stdint.h>

int read_poc_control(void);
int read_poc_read64(uint64_t source, bool seed_marker);
int gfx_read64(uint64_t source, uint64_t *value);

#endif
