#import <Foundation/Foundation.h>

#include <libkextrw.h>
#include <stdio.h>
#include <string.h>

#include "microppl.h"
#include "poc.h"

int main(int argc, const char *argv[])
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    @autoreleasepool {
        if (kextrw_init() != 0) {
            fputs("error: kextrw_init\n", stderr);
            return 1;
        }

        int result = 1;
        if (poc_init_neo() != 0) {
            fputs("error: AGX setup\n", stderr);
        } else if (argc == 1 ||
                   (argc == 2 && strcmp(argv[1], "--page-a") == 0)) {
            result = microppl_run(0);
        } else if (argc == 2 && strcmp(argv[1], "--page-b") == 0) {
            result = microppl_run(1);
        } else if (argc == 2 && strcmp(argv[1], "--map-41410000") == 0) {
            result = microppl_map_41410000(false);
        } else if (argc == 2 && strcmp(argv[1], "--touch-41410000") == 0) {
            result = microppl_map_41410000(true);
        } else if (argc == 2 && strcmp(argv[1], "--unmap") == 0) {
            result = microppl_unmap();
        } else if (argc == 2 && strcmp(argv[1], "--cleanup") == 0) {
            result = microppl_cleanup();
        } else {
            fputs("usage: micro-ppl-ttbr1-probe"
                  " [--page-a|--page-b|--map-41410000|"
                  "--touch-41410000|--unmap|--cleanup]\n", stderr);
        }

        poc_deinit();
        kextrw_deinit();
        return result;
    }
}
