#ifndef ARKSCALE_SMOKE_H
#define ARKSCALE_SMOKE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum arkscale_smoke_result {
    ARKSCALE_SMOKE_OK = 0,
    ARKSCALE_SMOKE_ERROR_INVALID_ARGUMENT = 1,
    ARKSCALE_SMOKE_ERROR_INTERNAL = 2,
    ARKSCALE_SMOKE_ERROR_INVALID_STATE = 3,
};

uint32_t arkscale_smoke_version(void);
int arkscale_smoke_run(uint32_t rounds);
int arkscale_smoke_start(void);
int arkscale_smoke_stop(void);
uint64_t arkscale_smoke_ticks(void);

#ifdef __cplusplus
}
#endif

#endif
