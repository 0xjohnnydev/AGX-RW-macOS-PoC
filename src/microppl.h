#ifndef MICROPPL_H
#define MICROPPL_H

#include <stdbool.h>

int microppl_run(unsigned selection);
int microppl_map_41410000(bool touch);
int microppl_unmap(void);
int microppl_cleanup(void);

#endif
