#include "EffectImpl.h"

#include <android-base/logging.h>

using aidl::android::hardware::audio::effect::Descriptor;
using aidl::android::hardware::audio::effect::IEffect;
using aidl::android::hardware::audio::effect::Rv4aEffect;
using aidl::android::hardware::audio::effect::State;
using aidl::android::hardware::audio::effect::kEffectUuid;
using aidl::android::media::audio::common::AudioUuid;

#define JDSP_EFFECT_EXPORT extern "C" __attribute__((visibility("default")))

JDSP_EFFECT_EXPORT binder_exception_t createEffect(
        const AudioUuid* inImplUuid, std::shared_ptr<IEffect>* instance) {
    if (!inImplUuid || !instance || *inImplUuid != kEffectUuid) {
        LOG(ERROR) << "jdsp-o13: createEffect unsupported/null uuid";
        return EX_ILLEGAL_ARGUMENT;
    }

    *instance = ndk::SharedRefBase::make<Rv4aEffect>();
    if (!*instance) {
        LOG(ERROR) << "jdsp-o13: createEffect allocation failed";
        return EX_ILLEGAL_STATE;
    }

    LOG(DEBUG) << "jdsp-o13: effect instance created " << instance->get();
    return EX_NONE;
}

JDSP_EFFECT_EXPORT binder_exception_t queryEffect(
        const AudioUuid* inImplUuid, Descriptor* descriptor) {
    if (!inImplUuid || !descriptor || *inImplUuid != kEffectUuid) {
        return EX_ILLEGAL_ARGUMENT;
    }

    *descriptor = Rv4aEffect::descriptor();
    return EX_NONE;
}

JDSP_EFFECT_EXPORT binder_exception_t destroyEffect(
        const std::shared_ptr<IEffect>& instance) {
    if (!instance) {
        return EX_ILLEGAL_ARGUMENT;
    }

    Descriptor descriptor;
    auto status = instance->getDescriptor(&descriptor);
    if (!status.isOk() || descriptor.common.id.uuid != kEffectUuid) {
        LOG(ERROR) << "jdsp-o13: destroyEffect received foreign/invalid effect";
        return EX_ILLEGAL_ARGUMENT;
    }

    State state = State::INIT;
    status = instance->getState(&state);
    if (!status.isOk()) {
        return EX_ILLEGAL_STATE;
    }

    // Be tolerant of vendor factories which destroy without an explicit close.
    // AOSP's newer effect implementation also supports destroy from non-INIT
    // states. Stop processing before closing so no FMQ worker survives dl refs.
    if (state == State::PROCESSING) {
        status = instance->command(aidl::android::hardware::audio::effect::CommandId::STOP);
        if (!status.isOk()) {
            LOG(WARNING) << "jdsp-o13: STOP during destroy failed: "
                         << status.getDescription();
        }
    }

    instance->getState(&state);
    if (state != State::INIT) {
        status = instance->close();
        if (!status.isOk()) {
            LOG(ERROR) << "jdsp-o13: close during destroy failed: "
                       << status.getDescription();
            return EX_ILLEGAL_STATE;
        }
    }

    LOG(DEBUG) << "jdsp-o13: effect instance destroyed " << instance.get();
    return EX_NONE;
}
