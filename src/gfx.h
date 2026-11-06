#ifndef GFX_H
#define GFX_H

#include <stdint.h>

int gfx_write32(uint64_t address, uint32_t value);
int gfx_write64(uint64_t address, uint64_t value);

#endif
