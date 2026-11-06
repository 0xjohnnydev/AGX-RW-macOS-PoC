#import <Foundation/Foundation.h>

#include <libkextrw.h>
#include <stdio.h>
#include <string.h>

#include "auth_call.h"
#include "poc.h"

int main(int argc, const char *argv[])
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    if (argc != 2 ||
        (strcmp(argv[1], "check") != 0 &&
         strcmp(argv[1], "control") != 0 &&
         strcmp(argv[1], "treatment") != 0)) {
        fprintf(stderr, "usage: %s check|control|treatment\n", argv[0]);
        return 2;
    }

    @autoreleasepool {
        if (kextrw_init() != 0) {
            fputs("error: kextrw_init\n", stderr);
            return 1;
        }

        int result = 1;
        if (poc_init_neo() != 0) {
            fputs("error: AGX setup\n", stderr);
        } else if (strcmp(argv[1], "check") == 0) {
            result = 0;
        } else {
            result = auth_call_run(strcmp(argv[1], "treatment") == 0);
        }

        poc_deinit();
        kextrw_deinit();
        return result;
    }
}
