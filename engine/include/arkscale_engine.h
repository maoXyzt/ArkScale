#ifndef ARKSCALE_ENGINE_H
#define ARKSCALE_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum arkscale_result {
    ARKSCALE_OK = 0,
    ARKSCALE_ERROR_INVALID_ARGUMENT = 1,
    ARKSCALE_ERROR_NOT_IMPLEMENTED = 2,
};

int arkscale_start(const char *config_json);
int arkscale_next_event(char **json, size_t *len, uint32_t timeout_ms);
void arkscale_free(void *ptr);
int arkscale_set_tun(int dup_fd, uint64_t generation);
void arkscale_network_changed(void);
int arkscale_stop(void);

#ifdef __cplusplus
}
#endif

#endif
