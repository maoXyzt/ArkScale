#include "napi/native_api.h"
#include "arkscale_engine.h"
#include "arkscale_smoke.h"

#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static pthread_mutex_t vpnProbeMutex = PTHREAD_MUTEX_INITIALIZER;
static int vpnProbeFd = -1;
static pid_t vpnExtensionPid = -1;
static bool vpnProcessProtected = false;
static uint64_t vpnTunGeneration = 0;
static char vpnProbeStatus[128] = "IDLE";

static napi_value GetVersion(napi_env env, napi_callback_info)
{
    napi_value value;
    napi_create_string_utf8(env, "ArkScale bridge 0.1.0", NAPI_AUTO_LENGTH, &value);
    return value;
}

static napi_value RunGoSmoke(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    uint32_t rounds;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
        napi_get_value_uint32(env, argv[0], &rounds) != napi_ok) {
        napi_throw_type_error(env, nullptr, "rounds must be a number");
        return nullptr;
    }

    napi_value value;
    napi_get_boolean(env, arkscale_smoke_version() == 1 && arkscale_smoke_run(rounds) == ARKSCALE_SMOKE_OK, &value);
    return value;
}

static napi_value RunGoLifecycle(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    uint32_t cycles;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
        napi_get_value_uint32(env, argv[0], &cycles) != napi_ok) {
        napi_throw_type_error(env, nullptr, "cycles must be a number");
        return nullptr;
    }

    bool passed = cycles > 0 && cycles <= 1000;
    for (uint32_t i = 0; passed && i < cycles; ++i) {
        passed = arkscale_smoke_start() == ARKSCALE_SMOKE_OK && arkscale_smoke_stop() == ARKSCALE_SMOKE_OK;
    }

    napi_value value;
    napi_get_boolean(env, passed, &value);
    return value;
}

static napi_value StartGoSmoke(napi_env env, napi_callback_info)
{
    napi_value value;
    napi_get_boolean(env, arkscale_smoke_start() == ARKSCALE_SMOKE_OK, &value);
    return value;
}

static napi_value StopGoSmoke(napi_env env, napi_callback_info)
{
    napi_value value;
    napi_get_boolean(env, arkscale_smoke_stop() == ARKSCALE_SMOKE_OK, &value);
    return value;
}

static napi_value GetGoSmokeTicks(napi_env env, napi_callback_info)
{
    napi_value value;
    napi_create_int64(env, static_cast<int64_t>(arkscale_smoke_ticks()), &value);
    return value;
}

static napi_value BeginVpnProbe(napi_env env, napi_callback_info)
{
    arkscale_stop();
    pthread_mutex_lock(&vpnProbeMutex);
    if (vpnProbeFd >= 0) {
        close(vpnProbeFd);
        vpnProbeFd = -1;
    }
    vpnExtensionPid = getpid();
    vpnProcessProtected = false;
    snprintf(vpnProbeStatus, sizeof(vpnProbeStatus), "PROTECTING pid=%d", vpnExtensionPid);
    pthread_mutex_unlock(&vpnProbeMutex);

    napi_value value;
    napi_get_boolean(env, true, &value);
    return value;
}

static napi_value MarkVpnProtected(napi_env env, napi_callback_info)
{
    pthread_mutex_lock(&vpnProbeMutex);
    vpnProcessProtected = true;
    snprintf(vpnProbeStatus, sizeof(vpnProbeStatus), "CREATING TUN pid=%d", vpnExtensionPid);
    pthread_mutex_unlock(&vpnProbeMutex);

    napi_value value;
    napi_get_boolean(env, true, &value);
    return value;
}

static napi_value AttachVpnTun(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    int32_t tunFd;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
        napi_get_value_int32(env, argv[0], &tunFd) != napi_ok || tunFd < 0) {
        napi_throw_type_error(env, nullptr, "tunFd must be a valid file descriptor");
        return nullptr;
    }

    int duplicatedFd = dup(tunFd);
    int engineFd = dup(tunFd);
    bool valid = duplicatedFd >= 0 && fcntl(duplicatedFd, F_GETFD) >= 0 &&
        engineFd >= 0 && fcntl(engineFd, F_GETFD) >= 0;
    if (valid && arkscale_set_tun(engineFd, ++vpnTunGeneration) != ARKSCALE_OK) {
        close(engineFd);
        valid = false;
    }
    pthread_mutex_lock(&vpnProbeMutex);
    if (valid) {
        if (vpnProbeFd >= 0) {
            close(vpnProbeFd);
        }
        vpnProbeFd = duplicatedFd;
        snprintf(vpnProbeStatus, sizeof(vpnProbeStatus), "READY protected=%s tunDup=PASS engineTun=PASS pid=%d",
            vpnProcessProtected ? "PASS" : "FAIL", vpnExtensionPid);
    } else {
        if (duplicatedFd >= 0) {
            close(duplicatedFd);
        }
        if (engineFd >= 0 && fcntl(engineFd, F_GETFD) >= 0) {
            close(engineFd);
        }
        snprintf(vpnProbeStatus, sizeof(vpnProbeStatus), "FAIL tunAttach");
    }
    pthread_mutex_unlock(&vpnProbeMutex);

    napi_value value;
    napi_get_boolean(env, valid && vpnProcessProtected, &value);
    return value;
}

static napi_value FailVpnProbe(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    int32_t errorCode;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
        napi_get_value_int32(env, argv[0], &errorCode) != napi_ok) {
        napi_throw_type_error(env, nullptr, "errorCode must be a number");
        return nullptr;
    }

    pthread_mutex_lock(&vpnProbeMutex);
    snprintf(vpnProbeStatus, sizeof(vpnProbeStatus), "FAIL code=%d", errorCode);
    pthread_mutex_unlock(&vpnProbeMutex);

    napi_value value;
    napi_get_boolean(env, true, &value);
    return value;
}

static napi_value StopVpnProbe(napi_env env, napi_callback_info)
{
    bool engineStopped = arkscale_stop() == ARKSCALE_OK;
    pthread_mutex_lock(&vpnProbeMutex);
    bool ownershipValid = vpnProbeFd >= 0 && fcntl(vpnProbeFd, F_GETFD) >= 0;
    if (vpnProbeFd >= 0) {
        close(vpnProbeFd);
        vpnProbeFd = -1;
    }
    snprintf(vpnProbeStatus, sizeof(vpnProbeStatus), "STOPPED dupOwnership=%s engineTun=%s",
        ownershipValid ? "PASS" : "N/A", engineStopped ? "PASS" : "FAIL");
    pthread_mutex_unlock(&vpnProbeMutex);

    napi_value value;
    napi_get_boolean(env, ownershipValid && engineStopped, &value);
    return value;
}

static napi_value GetVpnProbeStatus(napi_env env, napi_callback_info)
{
    char status[192];
    pthread_mutex_lock(&vpnProbeMutex);
    bool sameProcess = vpnExtensionPid > 0 && vpnExtensionPid == getpid();
    snprintf(status, sizeof(status), "%s sameProcess=%s", vpnProbeStatus, sameProcess ? "PASS" : "N/A");
    pthread_mutex_unlock(&vpnProbeMutex);

    napi_value value;
    napi_create_string_utf8(env, status, NAPI_AUTO_LENGTH, &value);
    return value;
}

static napi_value GetCurrentPid(napi_env env, napi_callback_info)
{
    napi_value value;
    napi_create_int32(env, getpid(), &value);
    return value;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"runGoSmoke", nullptr, RunGoSmoke, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"runGoLifecycle", nullptr, RunGoLifecycle, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startGoSmoke", nullptr, StartGoSmoke, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopGoSmoke", nullptr, StopGoSmoke, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getGoSmokeTicks", nullptr, GetGoSmokeTicks, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"beginVpnProbe", nullptr, BeginVpnProbe, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"markVpnProtected", nullptr, MarkVpnProtected, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"attachVpnTun", nullptr, AttachVpnTun, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"failVpnProbe", nullptr, FailVpnProbe, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopVpnProbe", nullptr, StopVpnProbe, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVpnProbeStatus", nullptr, GetVpnProbeStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCurrentPid", nullptr, GetCurrentPid, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}
EXTERN_C_END

static napi_module module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "arkscale_bridge",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

extern "C" __attribute__((constructor)) void RegisterArkScaleBridgeModule()
{
    napi_module_register(&module);
}
