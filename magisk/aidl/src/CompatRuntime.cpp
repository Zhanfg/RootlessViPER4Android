#include <android/log.h>
#include <cutils/native_handle.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>

namespace android::hardware::details {

void logError(const std::string& message) {
    __android_log_print(ANDROID_LOG_ERROR, "jdsp-fmq", "%s", message.c_str());
}

void errorWriteLog(int tag, const char* message) {
    __android_log_print(ANDROID_LOG_ERROR, "jdsp-fmq",
                        "security-log tag=%d: %s", tag, message ? message : "");
}

void check(bool exp, const char* message) {
    if (exp) return;
    __android_log_print(ANDROID_LOG_FATAL, "jdsp-fmq",
                        "check failed: %s", message ? message : "");
    std::abort();
}

}  // namespace android::hardware::details

extern "C" {

native_handle_t* native_handle_init(char* storage, int numFds, int numInts) {
    if (!storage || numFds < 0 || numInts < 0 ||
        numFds > NATIVE_HANDLE_MAX_FDS || numInts > NATIVE_HANDLE_MAX_INTS) {
        errno = EINVAL;
        return nullptr;
    }
    auto* h = reinterpret_cast<native_handle_t*>(storage);
    h->version = sizeof(native_handle_t);
    h->numFds = numFds;
    h->numInts = numInts;
    return h;
}

native_handle_t* native_handle_create(int numFds, int numInts) {
    if (numFds < 0 || numInts < 0 ||
        numFds > NATIVE_HANDLE_MAX_FDS || numInts > NATIVE_HANDLE_MAX_INTS) {
        errno = EINVAL;
        return nullptr;
    }
    const size_t count = static_cast<size_t>(numFds) + static_cast<size_t>(numInts);
    if (count > (SIZE_MAX - sizeof(native_handle_t)) / sizeof(int)) {
        errno = EOVERFLOW;
        return nullptr;
    }
    const size_t bytes = sizeof(native_handle_t) + count * sizeof(int);
    auto* h = static_cast<native_handle_t*>(std::calloc(1, bytes));
    if (!h) return nullptr;
    h->version = sizeof(native_handle_t);
    h->numFds = numFds;
    h->numInts = numInts;
    return h;
}

int native_handle_close(const native_handle_t* h) {
    if (!h || h->version != sizeof(native_handle_t) ||
        h->numFds < 0 || h->numInts < 0) {
        return -EINVAL;
    }
    int result = 0;
    for (int i = 0; i < h->numFds; ++i) {
        if (h->data[i] >= 0 && close(h->data[i]) != 0 && result == 0) {
            result = -errno;
        }
    }
    return result;
}

int native_handle_close_with_tag(const native_handle_t* h) {
    return native_handle_close(h);
}

int native_handle_delete(native_handle_t* h) {
    if (!h) return 0;
    if (h->version != sizeof(native_handle_t)) return -EINVAL;
    std::free(h);
    return 0;
}

native_handle_t* native_handle_clone(const native_handle_t* source) {
    if (!source || source->version != sizeof(native_handle_t) ||
        source->numFds < 0 || source->numInts < 0) {
        errno = EINVAL;
        return nullptr;
    }

    native_handle_t* out = native_handle_create(source->numFds, source->numInts);
    if (!out) return nullptr;

    int copiedFds = 0;
    for (; copiedFds < source->numFds; ++copiedFds) {
        const int fd = dup(source->data[copiedFds]);
        if (fd < 0) {
            for (int i = 0; i < copiedFds; ++i) close(out->data[i]);
            native_handle_delete(out);
            return nullptr;
        }
        out->data[copiedFds] = fd;
    }

    if (source->numInts > 0) {
        std::memcpy(out->data + source->numFds,
                    source->data + source->numFds,
                    static_cast<size_t>(source->numInts) * sizeof(int));
    }
    return out;
}

// fdsan ownership tagging is a libcutils hardening feature. The standalone
// NDK-built effect does not have libcutils' tag helpers, but FMQ only requires
// correct fd ownership/close semantics here.
void native_handle_set_fdsan_tag(const native_handle_t*) {}
void native_handle_unset_fdsan_tag(const native_handle_t*) {}

}  // extern "C"
