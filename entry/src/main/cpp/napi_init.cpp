#include "napi/native_api.h"
#include "arkscale_engine.h"
#include "arkscale_smoke.h"

#include <atomic>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <new>
#include <pthread.h>
#include <stdio.h>
#include <string>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

static pthread_mutex_t vpnProbeMutex = PTHREAD_MUTEX_INITIALIZER;
static int vpnProbeFd = -1;
static pid_t vpnExtensionPid = -1;
static bool vpnProcessProtected = false;
static uint64_t vpnTunGeneration = 0;
static char vpnProbeStatus[128] = "IDLE";

constexpr uint32_t PROBE_CHANNEL_MAGIC = 0x41524b53;
constexpr size_t PROBE_CHANNEL_SLOT_COUNT = 4;
constexpr size_t PROBE_CHANNEL_SLOT_SIZE = 64 * 1024;
// ponytail: 4096 is ample for this client; raise it if observed FD use approaches the ceiling.
constexpr rlim_t PROCESS_FD_SCAN_LIMIT = 4096;

struct ProbeChannelSlot {
    uint32_t sequence;
    uint32_t length;
    char data[PROBE_CHANNEL_SLOT_SIZE];
};

struct ProbeChannelFile {
    uint32_t magic;
    ProbeChannelSlot slots[PROBE_CHANNEL_SLOT_COUNT];
};

static pthread_mutex_t probeChannelMutex = PTHREAD_MUTEX_INITIALIZER;
static int probeChannelFd = -1;
static ProbeChannelFile* probeChannel = nullptr;
static pthread_mutex_t probeChannelWatchMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_t probeChannelWatchThread;
static bool probeChannelWatchStarted = false;
static uint32_t probeChannelWatchMask = 0;
static uint32_t probeChannelSeenSequences[PROBE_CHANNEL_SLOT_COUNT]{};
static std::atomic_bool probeChannelWatchRunning(false);

struct ProbeChannelEvent {
    int32_t key;
    std::string data;
};

static pthread_mutex_t enginePumpMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_t enginePumpThread;
static bool enginePumpThreadStarted = false;
static bool engineStartPending = false;
static std::atomic_bool enginePumpRunning(false);

struct EngineEvent {
    std::string json;
};

struct StartEngineWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    napi_threadsafe_function eventCallback = nullptr;
    std::string configJson;
    int result = ARKSCALE_ERROR_INTERNAL;
    bool pumpStarted = false;
};

struct StopEngineWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    int result = ARKSCALE_ERROR_INTERNAL;
};

struct ProbePeerWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string target;
    std::string eventJson;
    int result = ARKSCALE_ERROR_INTERNAL;
};

static napi_value CreateError(napi_env env, const char* message)
{
    napi_value text;
    napi_value error;
    napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &text);
    napi_create_error(env, nullptr, text, &error);
    return error;
}

static int32_t CountOpenFds()
{
    int32_t count = -1;
    struct rlimit limit{};
    if (getrlimit(RLIMIT_NOFILE, &limit) == 0) {
        count = 0;
        rlim_t maxFd = limit.rlim_cur < PROCESS_FD_SCAN_LIMIT ? limit.rlim_cur : PROCESS_FD_SCAN_LIMIT;
        for (int fd = 0; fd < maxFd; ++fd) {
            errno = 0;
            if (fcntl(fd, F_GETFD) >= 0 || errno != EBADF) {
                ++count;
            }
        }
    }
    return count;
}

static napi_value GetOpenFdCount(napi_env env, napi_callback_info)
{
    int32_t count = CountOpenFds();

    napi_value value;
    napi_create_int32(env, count, &value);
    return value;
}

static napi_value InitProbeChannel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    size_t directoryLength = 0;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
        napi_get_value_string_utf8(env, argv[0], nullptr, 0, &directoryLength) != napi_ok || directoryLength == 0 ||
        directoryLength > 4096) {
        napi_throw_type_error(env, nullptr, "initProbeChannel requires a files directory");
        return nullptr;
    }
    std::string directory(directoryLength + 1, '\0');
    if (napi_get_value_string_utf8(env, argv[0], &directory[0], directory.size(), &directoryLength) != napi_ok) {
        napi_throw_type_error(env, nullptr, "unable to read probe channel directory");
        return nullptr;
    }
    directory.resize(directoryLength);

    pthread_mutex_lock(&probeChannelMutex);
    bool initialized = probeChannel != nullptr;
    if (!initialized) {
        std::string path = directory + "/arkscale-probe-channel-v1";
        int fd = open(path.c_str(), O_RDWR | O_CREAT, 0600);
        if (fd >= 0 && flock(fd, LOCK_EX) == 0) {
            struct stat status{};
            bool reset = fstat(fd, &status) != 0 || status.st_size != sizeof(ProbeChannelFile);
            if ((!reset || ftruncate(fd, sizeof(ProbeChannelFile)) == 0)) {
                void* mapping = mmap(nullptr, sizeof(ProbeChannelFile), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
                if (mapping != MAP_FAILED) {
                    ProbeChannelFile* file = static_cast<ProbeChannelFile*>(mapping);
                    if (reset || file->magic != PROBE_CHANNEL_MAGIC) {
                        memset(file, 0, sizeof(*file));
                        file->magic = PROBE_CHANNEL_MAGIC;
                    }
                    probeChannelFd = fd;
                    probeChannel = file;
                    initialized = true;
                }
            }
            flock(fd, LOCK_UN);
        }
        if (!initialized && fd >= 0) {
            close(fd);
        }
    }
    pthread_mutex_unlock(&probeChannelMutex);

    napi_value value;
    napi_get_boolean(env, initialized, &value);
    return value;
}

static bool WriteProbeChannelSlot(int32_t key, const char* data, size_t length);

static napi_value WriteProbeChannel(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    int32_t key = -1;
    size_t length = 0;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 2 ||
        napi_get_value_int32(env, argv[0], &key) != napi_ok || key < 0 || key >= PROBE_CHANNEL_SLOT_COUNT ||
        napi_get_value_string_utf8(env, argv[1], nullptr, 0, &length) != napi_ok ||
        length == 0 || length > PROBE_CHANNEL_SLOT_SIZE) {
        napi_throw_type_error(env, nullptr, "invalid probe channel write");
        return nullptr;
    }
    std::string data(length + 1, '\0');
    if (napi_get_value_string_utf8(env, argv[1], &data[0], data.size(), &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, "unable to read probe channel payload");
        return nullptr;
    }
    data.resize(length);

    bool written = WriteProbeChannelSlot(key, data.data(), data.size());

    napi_value value;
    napi_get_boolean(env, written, &value);
    return value;
}

static bool ReadProbeChannelSlot(int32_t key, std::string& data, uint32_t& sequence)
{
    data.clear();
    if (probeChannel == nullptr) {
        return false;
    }
    ProbeChannelSlot& slot = probeChannel->slots[key];
    for (int attempt = 0; attempt < 2; ++attempt) {
        uint32_t before = __atomic_load_n(&slot.sequence, __ATOMIC_ACQUIRE);
        uint32_t length = __atomic_load_n(&slot.length, __ATOMIC_RELAXED);
        if ((before & 1U) != 0 || length == 0 || length > PROBE_CHANNEL_SLOT_SIZE) {
            continue;
        }
        data.assign(slot.data, length);
        uint32_t after = __atomic_load_n(&slot.sequence, __ATOMIC_ACQUIRE);
        if (before == after) {
            sequence = after;
            return true;
        }
        data.clear();
    }
    return false;
}

static bool WriteProbeChannelSlot(int32_t key, const char* data, size_t length)
{
    if (key < 0 || key >= PROBE_CHANNEL_SLOT_COUNT || data == nullptr || length == 0 ||
        length > PROBE_CHANNEL_SLOT_SIZE) {
        return false;
    }
    pthread_mutex_lock(&probeChannelMutex);
    bool written = probeChannel != nullptr;
    if (written) {
        ProbeChannelSlot& slot = probeChannel->slots[key];
        uint32_t sequence = __atomic_load_n(&slot.sequence, __ATOMIC_RELAXED);
        if ((sequence & 1U) != 0) {
            ++sequence;
        }
        __atomic_store_n(&slot.sequence, sequence + 1, __ATOMIC_RELEASE);
        memcpy(slot.data, data, length);
        __atomic_store_n(&slot.length, static_cast<uint32_t>(length), __ATOMIC_RELAXED);
        __atomic_store_n(&slot.sequence, sequence + 2, __ATOMIC_RELEASE);
    }
    pthread_mutex_unlock(&probeChannelMutex);
    return written;
}

static void CallProbeChannelEvent(napi_env env, napi_value callback, void*, void* data)
{
    ProbeChannelEvent* event = static_cast<ProbeChannelEvent*>(data);
    if (env != nullptr && callback != nullptr) {
        napi_value undefined;
        napi_value values[2];
        napi_get_undefined(env, &undefined);
        napi_create_int32(env, event->key, &values[0]);
        napi_create_string_utf8(env, event->data.c_str(), event->data.size(), &values[1]);
        napi_call_function(env, undefined, callback, 2, values, nullptr);
    }
    delete event;
}

static void* WatchProbeChannel(void* data)
{
    napi_threadsafe_function callback = static_cast<napi_threadsafe_function>(data);
    while (probeChannelWatchRunning.load()) {
        usleep(250000);
        for (int32_t key = 0; key < PROBE_CHANNEL_SLOT_COUNT && probeChannelWatchRunning.load(); ++key) {
            if ((probeChannelWatchMask & (1U << key)) == 0) {
                continue;
            }
            std::string value;
            uint32_t sequence = 0;
            if (!ReadProbeChannelSlot(key, value, sequence) || sequence == probeChannelSeenSequences[key]) {
                continue;
            }
            probeChannelSeenSequences[key] = sequence;
            ProbeChannelEvent* event = new (std::nothrow) ProbeChannelEvent{key, std::move(value)};
            if (event == nullptr ||
                napi_call_threadsafe_function(callback, event, napi_tsfn_nonblocking) != napi_ok) {
                delete event;
                probeChannelWatchRunning.store(false);
                break;
            }
        }
    }
    napi_release_threadsafe_function(callback, napi_tsfn_release);
    return nullptr;
}

static napi_value StartProbeChannelWatch(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    uint32_t mask = 0;
    napi_valuetype callbackType;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 2 ||
        napi_get_value_uint32(env, argv[0], &mask) != napi_ok || mask == 0 || mask >= (1U << PROBE_CHANNEL_SLOT_COUNT) ||
        napi_typeof(env, argv[1], &callbackType) != napi_ok || callbackType != napi_function) {
        napi_throw_type_error(env, nullptr, "invalid probe channel watcher");
        return nullptr;
    }

    pthread_mutex_lock(&probeChannelWatchMutex);
    bool started = probeChannel != nullptr && !probeChannelWatchStarted;
    if (started) {
        napi_value resourceName;
        napi_threadsafe_function callback = nullptr;
        napi_create_string_utf8(env, "ArkScaleProbeChannel", NAPI_AUTO_LENGTH, &resourceName);
        started = napi_create_threadsafe_function(env, argv[1], nullptr, resourceName, 16, 1, nullptr, nullptr,
            nullptr, CallProbeChannelEvent, &callback) == napi_ok;
        if (started) {
            probeChannelWatchMask = mask;
            for (size_t key = 0; key < PROBE_CHANNEL_SLOT_COUNT; ++key) {
                probeChannelSeenSequences[key] = __atomic_load_n(&probeChannel->slots[key].sequence, __ATOMIC_ACQUIRE);
            }
            probeChannelWatchRunning.store(true);
            started = pthread_create(&probeChannelWatchThread, nullptr, WatchProbeChannel, callback) == 0;
            probeChannelWatchStarted = started;
            if (!started) {
                probeChannelWatchRunning.store(false);
                napi_release_threadsafe_function(callback, napi_tsfn_abort);
            }
        }
    }
    pthread_mutex_unlock(&probeChannelWatchMutex);

    napi_value value;
    napi_get_boolean(env, started, &value);
    return value;
}

static napi_value StopProbeChannelWatch(napi_env env, napi_callback_info)
{
    probeChannelWatchRunning.store(false);
    pthread_mutex_lock(&probeChannelWatchMutex);
    if (probeChannelWatchStarted) {
        pthread_join(probeChannelWatchThread, nullptr);
        probeChannelWatchStarted = false;
    }
    pthread_mutex_unlock(&probeChannelWatchMutex);

    napi_value value;
    napi_get_undefined(env, &value);
    return value;
}

static void CallEngineEvent(napi_env env, napi_value callback, void*, void* data)
{
    EngineEvent* event = static_cast<EngineEvent*>(data);
    if (env != nullptr && callback != nullptr) {
        napi_value undefined;
        napi_value value;
        napi_get_undefined(env, &undefined);
        napi_create_string_utf8(env, event->json.c_str(), event->json.size(), &value);
        napi_call_function(env, undefined, callback, 1, &value, nullptr);
    }
    delete event;
}

static void* PumpEngineEvents(void* data)
{
    napi_threadsafe_function callback = static_cast<napi_threadsafe_function>(data);
    while (enginePumpRunning.load()) {
        char* json = nullptr;
        size_t length = 0;
        if (arkscale_next_event(&json, &length, 500) != ARKSCALE_OK) {
            break;
        }
        if (json == nullptr || length == 0) {
            continue;
        }
        EngineEvent* event = new (std::nothrow) EngineEvent{std::string(json, length)};
        arkscale_free(json);
        if (event == nullptr || napi_call_threadsafe_function(callback, event, napi_tsfn_blocking) != napi_ok) {
            delete event;
            break;
        }
    }
    enginePumpRunning.store(false);
    napi_release_threadsafe_function(callback, napi_tsfn_release);
    return nullptr;
}

static bool StartEventPump(napi_threadsafe_function callback)
{
    pthread_mutex_lock(&enginePumpMutex);
    if (enginePumpThreadStarted) {
        pthread_mutex_unlock(&enginePumpMutex);
        return false;
    }
    enginePumpRunning.store(true);
    int result = pthread_create(&enginePumpThread, nullptr, PumpEngineEvents, callback);
    enginePumpThreadStarted = result == 0;
    if (result != 0) {
        enginePumpRunning.store(false);
    }
    pthread_mutex_unlock(&enginePumpMutex);
    return result == 0;
}

static void StopEventPump()
{
    enginePumpRunning.store(false);
    pthread_mutex_lock(&enginePumpMutex);
    if (enginePumpThreadStarted) {
        pthread_join(enginePumpThread, nullptr);
        enginePumpThreadStarted = false;
    }
    pthread_mutex_unlock(&enginePumpMutex);
}

static void SetEngineStartPending(bool pending)
{
    pthread_mutex_lock(&enginePumpMutex);
    engineStartPending = pending;
    pthread_mutex_unlock(&enginePumpMutex);
}

static napi_value StartEngine(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 2) {
        napi_throw_type_error(env, nullptr, "startEngine requires config JSON and an event callback");
        return nullptr;
    }
    pthread_mutex_lock(&enginePumpMutex);
    bool alreadyStarted = enginePumpThreadStarted || engineStartPending;
    if (!alreadyStarted) {
        engineStartPending = true;
    }
    pthread_mutex_unlock(&enginePumpMutex);
    if (alreadyStarted) {
        napi_throw_error(env, nullptr, "Tailscale backend is already started");
        return nullptr;
    }
    size_t configLength = 0;
    napi_valuetype callbackType;
    if (napi_get_value_string_utf8(env, argv[0], nullptr, 0, &configLength) != napi_ok || configLength == 0 ||
        configLength > 16384 || napi_typeof(env, argv[1], &callbackType) != napi_ok || callbackType != napi_function) {
        SetEngineStartPending(false);
        napi_throw_type_error(env, nullptr, "invalid engine config or callback");
        return nullptr;
    }

    StartEngineWork* context = new (std::nothrow) StartEngineWork;
    if (context == nullptr) {
        SetEngineStartPending(false);
        napi_throw_error(env, nullptr, "unable to allocate engine work");
        return nullptr;
    }
    context->configJson.resize(configLength);
    if (napi_get_value_string_utf8(env, argv[0], &context->configJson[0], configLength + 1, &configLength) != napi_ok) {
        SetEngineStartPending(false);
        delete context;
        napi_throw_type_error(env, nullptr, "unable to read engine config");
        return nullptr;
    }

    napi_value resourceName;
    napi_value promise;
    napi_create_string_utf8(env, "ArkScaleEngineEvents", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_threadsafe_function(env, argv[1], nullptr, resourceName, 64, 1, nullptr, nullptr, nullptr,
        CallEngineEvent, &context->eventCallback) != napi_ok) {
        SetEngineStartPending(false);
        delete context;
        napi_throw_error(env, nullptr, "unable to create engine event bridge");
        return nullptr;
    }
    if (napi_create_promise(env, &context->deferred, &promise) != napi_ok) {
        SetEngineStartPending(false);
        napi_release_threadsafe_function(context->eventCallback, napi_tsfn_abort);
        delete context;
        napi_throw_error(env, nullptr, "unable to create engine promise");
        return nullptr;
    }

    napi_create_string_utf8(env, "ArkScaleStartEngine", NAPI_AUTO_LENGTH, &resourceName);
    napi_status status = napi_create_async_work(env, nullptr, resourceName,
        [](napi_env, void* data) {
            StartEngineWork* work = static_cast<StartEngineWork*>(data);
            work->result = arkscale_start(work->configJson.c_str());
            if (work->result == ARKSCALE_OK) {
                work->pumpStarted = StartEventPump(work->eventCallback);
            }
            if (work->result == ARKSCALE_OK && !work->pumpStarted) {
                arkscale_stop();
                work->result = ARKSCALE_ERROR_INTERNAL;
            }
        },
        [](napi_env env, napi_status status, void* data) {
            StartEngineWork* work = static_cast<StartEngineWork*>(data);
            SetEngineStartPending(false);
            if (status == napi_ok && work->result == ARKSCALE_OK) {
                napi_value value;
                napi_get_boolean(env, true, &value);
                napi_resolve_deferred(env, work->deferred, value);
            } else {
                if (!work->pumpStarted) {
                    napi_release_threadsafe_function(work->eventCallback, napi_tsfn_abort);
                }
                napi_reject_deferred(env, work->deferred, CreateError(env, "unable to start Tailscale backend"));
            }
            napi_delete_async_work(env, work->work);
            delete work;
        }, context, &context->work);
    if (status != napi_ok || napi_queue_async_work(env, context->work) != napi_ok) {
        SetEngineStartPending(false);
        napi_release_threadsafe_function(context->eventCallback, napi_tsfn_abort);
        if (context->work != nullptr) {
            napi_delete_async_work(env, context->work);
        }
        delete context;
        napi_throw_error(env, nullptr, "unable to queue engine start");
        return nullptr;
    }
    return promise;
}

static napi_value StopEngine(napi_env env, napi_callback_info)
{
    StopEngineWork* context = new (std::nothrow) StopEngineWork;
    if (context == nullptr) {
        napi_throw_error(env, nullptr, "unable to allocate engine work");
        return nullptr;
    }
    napi_value promise;
    napi_value resourceName;
    if (napi_create_promise(env, &context->deferred, &promise) != napi_ok) {
        delete context;
        napi_throw_error(env, nullptr, "unable to create engine stop promise");
        return nullptr;
    }
    napi_create_string_utf8(env, "ArkScaleStopEngine", NAPI_AUTO_LENGTH, &resourceName);
    napi_status status = napi_create_async_work(env, nullptr, resourceName,
        [](napi_env, void* data) {
            StopEngineWork* work = static_cast<StopEngineWork*>(data);
            work->result = arkscale_stop();
            StopEventPump();
        },
        [](napi_env env, napi_status status, void* data) {
            StopEngineWork* work = static_cast<StopEngineWork*>(data);
            if (status == napi_ok && work->result == ARKSCALE_OK) {
                napi_value value;
                napi_get_boolean(env, true, &value);
                napi_resolve_deferred(env, work->deferred, value);
            } else {
                napi_reject_deferred(env, work->deferred, CreateError(env, "unable to stop Tailscale backend"));
            }
            napi_delete_async_work(env, work->work);
            delete work;
        }, context, &context->work);
    if (status != napi_ok || napi_queue_async_work(env, context->work) != napi_ok) {
        if (context->work != nullptr) {
            napi_delete_async_work(env, context->work);
        }
        delete context;
        napi_throw_error(env, nullptr, "unable to queue engine stop");
        return nullptr;
    }
    return promise;
}

static napi_value ProbePeer(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    size_t targetLength = 0;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc != 1 ||
        napi_get_value_string_utf8(env, argv[0], nullptr, 0, &targetLength) != napi_ok || targetLength == 0 ||
        targetLength > 128) {
        napi_throw_type_error(env, nullptr, "probePeer requires an IP address");
        return nullptr;
    }

    ProbePeerWork* context = new (std::nothrow) ProbePeerWork;
    if (context == nullptr) {
        napi_throw_error(env, nullptr, "unable to allocate peer probe work");
        return nullptr;
    }
    context->target.resize(targetLength);
    if (napi_get_value_string_utf8(env, argv[0], &context->target[0], targetLength + 1, &targetLength) != napi_ok) {
        delete context;
        napi_throw_type_error(env, nullptr, "unable to read peer IP address");
        return nullptr;
    }

    napi_value promise;
    napi_value resourceName;
    if (napi_create_promise(env, &context->deferred, &promise) != napi_ok) {
        delete context;
        napi_throw_error(env, nullptr, "unable to create peer probe promise");
        return nullptr;
    }
    napi_create_string_utf8(env, "ArkScaleProbePeer", NAPI_AUTO_LENGTH, &resourceName);
    napi_status status = napi_create_async_work(env, nullptr, resourceName,
        [](napi_env, void* data) {
            ProbePeerWork* work = static_cast<ProbePeerWork*>(data);
            char* json = nullptr;
            size_t length = 0;
            work->result = arkscale_probe_peer(work->target.c_str(), &json, &length);
            if (work->result == ARKSCALE_OK && json != nullptr && length > 0) {
                work->eventJson.assign(json, length);
            }
            if (json != nullptr) {
                arkscale_free(json);
            }
        },
        [](napi_env env, napi_status status, void* data) {
            ProbePeerWork* work = static_cast<ProbePeerWork*>(data);
            if (status == napi_ok && work->result == ARKSCALE_OK && !work->eventJson.empty()) {
                napi_value value;
                napi_create_string_utf8(env, work->eventJson.c_str(), work->eventJson.size(), &value);
                napi_resolve_deferred(env, work->deferred, value);
            } else {
                napi_reject_deferred(env, work->deferred, CreateError(env, "peer probe failed"));
            }
            napi_delete_async_work(env, work->work);
            delete work;
        }, context, &context->work);
    if (status != napi_ok || napi_queue_async_work(env, context->work) != napi_ok) {
        if (context->work != nullptr) {
            napi_delete_async_work(env, context->work);
        }
        delete context;
        napi_throw_error(env, nullptr, "unable to queue peer probe");
        return nullptr;
    }
    return promise;
}

static napi_value NetworkChanged(napi_env env, napi_callback_info)
{
    arkscale_network_changed();
    napi_value value;
    napi_get_undefined(env, &value);
    return value;
}

static napi_value SuspendVpnTun(napi_env env, napi_callback_info)
{
    bool cleared = arkscale_clear_tun() == ARKSCALE_OK;
    pthread_mutex_lock(&vpnProbeMutex);
    if (vpnProbeFd >= 0) {
        close(vpnProbeFd);
        vpnProbeFd = -1;
    }
    pthread_mutex_unlock(&vpnProbeMutex);
    napi_value value;
    napi_get_boolean(env, cleared, &value);
    return value;
}

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
        {"getOpenFdCount", nullptr, GetOpenFdCount, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"initProbeChannel", nullptr, InitProbeChannel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"writeProbeChannel", nullptr, WriteProbeChannel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startProbeChannelWatch", nullptr, StartProbeChannelWatch, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopProbeChannelWatch", nullptr, StopProbeChannelWatch, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startEngine", nullptr, StartEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopEngine", nullptr, StopEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"networkChanged", nullptr, NetworkChanged, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"suspendVpnTun", nullptr, SuspendVpnTun, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probePeer", nullptr, ProbePeer, nullptr, nullptr, nullptr, napi_default, nullptr},
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
