#include "napi/native_api.h"
#include "arkscale_smoke.h"

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
