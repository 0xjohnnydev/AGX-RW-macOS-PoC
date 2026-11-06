#import <Foundation/Foundation.h>

#include <libkextrw.h>
#include <stdio.h>

#include "poc.h"

int main(void)
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
        } else {
            result = poc_run();
        }

        poc_deinit();
        kextrw_deinit();
        return result;
    }
}
