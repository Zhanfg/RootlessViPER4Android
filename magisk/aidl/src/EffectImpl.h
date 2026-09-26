#pragma once

#include <aidl/android/hardware/audio/effect/BnEffect.h>
#include <aidl/android/hardware/audio/effect/DefaultExtension.h>
#include <android-base/logging.h>
#include <fmq/AidlMessageQueue.h>
#include <hardware/audio_effect.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <optional>
#include <thread>
#include <vector>

#include "EffectParams.h"

extern "C" {
#include "jdsp_header.h"
}

/* Legacy EEL headers export min/max as preprocessor macros. They break C++
 * standard-library calls such as std::min and std::max in the AIDL wrapper.
 * Keep the legacy macros contained to the DSP C sources. */
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

namespace aidl::android::hardware::audio::effect {

using ::android::AidlMessageQueue;
using ::aidl::android::hardware::common::fmq::SynchronizedReadWrite;
using ::aidl::android::media::audio::common::AudioChannelLayout;
using ::aidl::android::media::audio::common::AudioUuid;
using ::aidl::android::media::audio::common::PcmType;

static const AudioUuid kEffectUuid = {
    static_cast<int32_t>(0xf27317f4), 0xc984, 0x4de6, 0x9a90,
    {0x54, 0x57, 0x59, 0x49, 0x5b, 0xf2}};
static const AudioUuid kEffectType = {
    static_cast<int32_t>(0xf98765f4), 0xc321, 0x5de6, 0x9a45,
    {0x12, 0x34, 0x59, 0x49, 0x5a, 0xb2}};

static constexpr int kBlock = 4096;

static int channelCount(const AudioChannelLayout& layout) {
    int32_t mask = 0;
    switch (layout.getTag()) {
        case AudioChannelLayout::indexMask:
            mask = layout.get<AudioChannelLayout::indexMask>();
            break;
        case AudioChannelLayout::layoutMask:
            mask = layout.get<AudioChannelLayout::layoutMask>();
            break;
        case AudioChannelLayout::voiceMask:
            mask = layout.get<AudioChannelLayout::voiceMask>();
            break;
        default:
            return 0;
    }
    return __builtin_popcount(static_cast<uint32_t>(mask));
}

class Rv4aEffect : public BnEffect {
  public:
    Rv4aEffect() {
        static std::once_flag globalOnce;
        std::call_once(globalOnce, [] { JamesDSPGlobalMemoryAllocation(); });
        JamesDSPInit(&mDsp, kBlock, 48000);
    }

    ~Rv4aEffect() override {
        stopWorker();
        std::lock_guard dspLock(mDspMutex);
        JamesDSPFree(&mDsp);
    }

    static Descriptor descriptor() {
        Descriptor d;
        d.common.id.type = kEffectType;
        d.common.id.uuid = kEffectUuid;
        d.common.name = "JamesDSP OnePlus13 AIDL";
        d.common.implementor = "JamesDSP / OnePlus13 integration";
        d.common.flags.type = Flags::Type::INSERT;
        // Keep the output limiter as late as the framework permits so a stock
        // software insert is less likely to re-amplify a limited signal.
        d.common.flags.insert = Flags::Insert::LAST;
        return d;
    }

    ndk::ScopedAStatus open(const Parameter::Common& common,
                            const std::optional<Parameter::Specific>&,
                            OpenEffectReturn* ret) override {
        std::lock_guard lock(mMutex);
        if (mState != State::INIT) return ok();

        if (common.input.base.sampleRate <= 0 ||
            common.input.base.sampleRate != common.output.base.sampleRate) {
            LOG(ERROR) << "jdsp-o13: invalid/mismatched sample rate "
                       << common.input.base.sampleRate << " -> "
                       << common.output.base.sampleRate;
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }

        if (common.input.base.format.pcm != PcmType::FLOAT_32_BIT ||
            common.output.base.format.pcm != PcmType::FLOAT_32_BIT) {
            LOG(ERROR) << "jdsp-o13: AIDL effect FMQ must be FLOAT_32_BIT";
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }

        const int inputChannels = channelCount(common.input.base.channelMask);
        const int outputChannels = channelCount(common.output.base.channelMask);
        if (inputChannels != 2 || outputChannels != 2) {
            // JamesDSP is a stereo engine. Never reinterpret 5.1/7.1/spatial
            // buffers as stereo: rejecting is safer than corrupting the frame
            // stride and producing a burst of full-scale noise.
            LOG(WARNING) << "jdsp-o13: refusing non-stereo effect context in="
                         << inputChannels << " out=" << outputChannels;
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }

        const int nextRate = common.input.base.sampleRate;
        {
            std::lock_guard dspLock(mDspMutex);
            if (nextRate != mSampleRate) {
                // Do not JamesDSPInit() here. Re-open and route changes must
                // preserve EQ/convolver/limiter state already sent by the app.
                JamesDSPSetSampleRate(&mDsp, static_cast<float>(nextRate), 0);
                mSampleRate = nextRate;
            }
        }

        mChannels = inputChannels;
        const size_t frames = common.input.frameCount > 0
                                  ? common.input.frameCount : kBlock;
        const size_t samples = frames * mChannels;

        mStatusMQ = std::make_shared<StatusMQ>(1, true);
        mInputMQ = std::make_shared<DataMQ>(samples, true);
        mOutputMQ = std::make_shared<DataMQ>(samples, true);
        if (!mStatusMQ->isValid() || !mInputMQ->isValid() || !mOutputMQ->isValid()) {
            LOG(ERROR) << "jdsp-o13: failed to create effect FMQs";
            mStatusMQ.reset();
            mInputMQ.reset();
            mOutputMQ.reset();
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_STATE);
        }

        ret->statusMQ = mStatusMQ->dupeDesc();
        ret->inputDataMQ = mInputMQ->dupeDesc();
        ret->outputDataMQ = mOutputMQ->dupeDesc();

        mState = State::IDLE;
        LOG(INFO) << "jdsp-o13: open " << mSampleRate << " Hz, " << frames << " frames";
        return ok();
    }

    ndk::ScopedAStatus close() override {
        stopWorker();
        std::lock_guard lock(mMutex);
        mStatusMQ.reset();
        mInputMQ.reset();
        mOutputMQ.reset();
        mState = State::INIT;
        return ok();
    }

    ndk::ScopedAStatus getDescriptor(Descriptor* desc) override {
        if (!desc) return ndk::ScopedAStatus::fromExceptionCode(EX_NULL_POINTER);
        *desc = descriptor();
        return ok();
    }

    ndk::ScopedAStatus command(CommandId id) override {
        switch (id) {
            case CommandId::START: startWorker(); break;
            case CommandId::STOP:
            case CommandId::RESET: stopWorker(); break;
            default: break;
        }
        return ok();
    }

    ndk::ScopedAStatus getState(State* state) override {
        if (!state) return ndk::ScopedAStatus::fromExceptionCode(EX_NULL_POINTER);
        *state = mState;
        return ok();
    }

    ndk::ScopedAStatus setParameter(const Parameter& param) override {
        if (!applyVendorParameter(param)) {
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }
        return ok();
    }

    ndk::ScopedAStatus getParameter(const Parameter::Id& id, Parameter* result) override {
        if (!result || id.getTag() != Parameter::Id::vendorEffectTag) {
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }

        const auto& extId = id.get<Parameter::Id::vendorEffectTag>();
        std::optional<DefaultExtension> request;
        if (extId.extension.getParcelable(&request) != STATUS_OK || !request.has_value()) {
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }

        DefaultExtension response = *request;
        auto& bytes = response.bytes;
        if (bytes.size() < sizeof(effect_param_t)) {
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }

        auto* p = reinterpret_cast<effect_param_t*>(bytes.data());
        if (p->psize != sizeof(int32_t)) {
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }
        const size_t valueOffset = sizeof(effect_param_t) + ((p->psize + 3u) & ~3u);
        if (p->vsize < sizeof(int32_t) || bytes.size() < valueOffset + sizeof(int32_t)) {
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }

        const int32_t query = *reinterpret_cast<const int32_t*>(p->data);
        int32_t value = 0;
        {
            std::lock_guard dspLock(mDspMutex);
            switch (query) {
                case 19998: value = static_cast<int32_t>(mParamCommits); break;
                case 19999: value = kBlock; break;
                case 20000: value = static_cast<int32_t>(mDsp.blockSizeMax); break;
                case 20001: value = mSampleRate; break;
                case 20002: value = static_cast<int32_t>(getpid()); break;
                case 30000:
                case 30001:
                case 30002:
                case 30003: value = mHashSlot[query - 30000]; break;
                default:
                    return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
            }
        }

        p->status = 0;
        std::memcpy(bytes.data() + valueOffset, &value, sizeof(value));

        VendorExtension extension;
        if (extension.extension.setParcelable(response) != STATUS_OK) {
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }
        Parameter::Specific specific;
        specific.set<Parameter::Specific::vendorEffect>(extension);
        result->set<Parameter::specific>(specific);
        return ok();
    }

    ndk::ScopedAStatus reopen(OpenEffectReturn* ret) override {
        std::lock_guard lock(mMutex);
        if (!mStatusMQ || !mInputMQ || !mOutputMQ) {
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_STATE);
        }
        ret->statusMQ = mStatusMQ->dupeDesc();
        ret->inputDataMQ = mInputMQ->dupeDesc();
        ret->outputDataMQ = mOutputMQ->dupeDesc();
        return ok();
    }

  private:
    using StatusMQ = AidlMessageQueue<IEffect::Status, SynchronizedReadWrite>;
    using DataMQ = AidlMessageQueue<float, SynchronizedReadWrite>;

    static ndk::ScopedAStatus ok() { return ndk::ScopedAStatus::ok(); }

    void startWorker() {
        if (mRunning.exchange(true)) return;
        mState = State::PROCESSING;
        mWorker = std::thread([this] { workerLoop(); });
    }

    void stopWorker() {
        if (!mRunning.exchange(false)) return;
        if (mWorker.joinable()) mWorker.join();
        if (mState == State::PROCESSING) mState = State::IDLE;
    }

    void workerLoop() {
        std::vector<float> in;
        std::vector<float> out;

        while (mRunning.load()) {
            if (!mInputMQ || !mOutputMQ || !mStatusMQ) break;

            size_t samples = std::min(mInputMQ->availableToRead(),
                                      mOutputMQ->availableToWrite());
            samples -= samples % static_cast<size_t>(mChannels);
            if (samples == 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                continue;
            }

            in.resize(samples);
            out.resize(samples);
            if (!mInputMQ->read(in.data(), samples)) continue;

            const size_t frames = samples / static_cast<size_t>(mChannels);
            {
                std::lock_guard dspLock(mDspMutex);
                for (size_t off = 0; off < frames; off += kBlock) {
                    const size_t n = std::min<size_t>(kBlock, frames - off);
                    mDsp.processFloatMultiplexd(&mDsp,
                        in.data() + off * mChannels,
                        out.data() + off * mChannels,
                        n);
                }
            }

            const bool wrote = mOutputMQ->write(out.data(), samples);
            IEffect::Status st{wrote ? STATUS_OK : STATUS_INVALID_OPERATION,
                               static_cast<int>(samples),
                               static_cast<int>(wrote ? samples : 0)};
            // A full one-entry status queue means the framework has not yet
            // consumed the previous result. Give it a bounded chance instead
            // of silently dropping the status and desynchronising FMQ pacing.
            if (!mStatusMQ->writeBlocking(&st, 1, 20'000'000 /* 20 ms */)) {
                LOG(WARNING) << "jdsp-o13: status FMQ blocked; stopping worker";
                mRunning.store(false);
                break;
            }
        }
    }

    bool handleBufferedPayload(int32_t id, const void* val, uint32_t vsize) {
        switch (id) {
            case 8888: {
                if (vsize < 2 * sizeof(int32_t)) return true;
                const int32_t* v = static_cast<const int32_t*>(val);
                const int64_t parts = v[0], per = v[1];
                mStringBuf.clear();
                mStringIndex = 0;
                if (parts <= 0 || per <= 0 || parts * per > (16 << 20)) return true;
                mStringBuf.assign(static_cast<size_t>(parts * per) + 1u, 0);
                return true;
            }
            case 12001: {
                if (mStringBuf.empty() || vsize < 256) return true;
                const size_t off = static_cast<size_t>(mStringIndex) * 256u;
                if (off + 256u <= mStringBuf.size() - 1u) {
                    std::memcpy(mStringBuf.data() + off, val, 256);
                    ++mStringIndex;
                }
                return true;
            }
            case 9999: {
                if (vsize < 4 * sizeof(int32_t)) return true;
                const int32_t* v = static_cast<const int32_t*>(val);
                const int channels = v[1], parts = v[3];
                mIrBuf.clear();
                mIrPartsSeen = 0;
                if (channels <= 0 || channels > 2 || parts <= 0 ||
                    static_cast<int64_t>(parts) * channels * 4096 > (64 << 20)) {
                    return true;
                }
                mIrChannels = channels;
                mIrFrames = channels ? v[0] / channels : 0;
                mIrParts = parts;
                mIrBuf.assign(static_cast<size_t>(4096) * channels * parts, 0.0f);
                return true;
            }
            case 12000: {
                if (mIrBuf.empty() || vsize < 4096u * sizeof(float)) return true;
                const size_t off = static_cast<size_t>(mIrPartsSeen) * 4096u;
                if (off + 4096u <= mIrBuf.size()) {
                    std::memcpy(mIrBuf.data() + off, val, 4096u * sizeof(float));
                    ++mIrPartsSeen;
                }
                return true;
            }
            case 10004: {
                if (!mIrBuf.empty()) {
                    const int rc = Convolver1DLoadImpulseResponse(
                        &mDsp, mIrBuf.data(), static_cast<int16_t>(mIrChannels),
                        mIrFrames, 1);
                    mHaveIr = rc >= 0;
                    mIrBuf.clear();
                    mIrPartsSeen = 0;
                }
                return true;
            }
            case 10006:
            case 10009:
            case 10010: {
                if (!mStringBuf.empty()) {
                    mStringBuf.back() = '\0';
                    if (id == 10006) {
                        ArbitraryResponseEqualizerStringParser(&mDsp, mStringBuf.data());
                        mHaveGraphicEq = true;
                    } else if (id == 10009) {
                        DDCStringParser(&mDsp, mStringBuf.data());
                        mHaveDdc = true;
                    } else {
                        mHaveLiveprog = LiveProgStringParser(&mDsp, mStringBuf.data()) == 0;
                    }
                    mStringBuf.clear();
                }
                mStringIndex = 0;
                return true;
            }
            default:
                return false;
        }
    }

    bool applyVendorParameter(const Parameter& param) {
        if (param.getTag() != Parameter::specific) return false;
        const auto& specific = param.get<Parameter::specific>();
        if (specific.getTag() != Parameter::Specific::vendorEffect) return false;

        std::optional<DefaultExtension> payload;
        if (specific.get<Parameter::Specific::vendorEffect>()
                    .extension.getParcelable(&payload) != STATUS_OK ||
            !payload.has_value()) {
            return false;
        }

        const auto& bytes = payload->bytes;
        if (bytes.size() < sizeof(effect_param_t)) return false;
        auto* p = reinterpret_cast<const effect_param_t*>(bytes.data());
        if (p->psize != sizeof(int32_t)) return false;

        const size_t valueOffset = sizeof(effect_param_t) + ((p->psize + 3u) & ~3u);
        if (bytes.size() < valueOffset + p->vsize) return false;

        const int32_t id = *reinterpret_cast<const int32_t*>(p->data);
        const void* val = bytes.data() + valueOffset;
        const int16_t sv = p->vsize >= sizeof(int16_t)
                               ? *reinterpret_cast<const int16_t*>(val) : 0;

        std::lock_guard dspLock(mDspMutex);
        ++mParamCommits;

        if (handleBufferedPayload(id, val, p->vsize)) return true;

        if (id >= 25000 && id <= 25003) {
            if (p->vsize >= sizeof(int32_t)) {
                mHashSlot[id - 25000] = *reinterpret_cast<const int32_t*>(val);
            }
            return true;
        }

        if ((id == 1205 && sv != 0 && !mHaveIr) ||
            (id == 1210 && sv != 0 && !mHaveGraphicEq) ||
            (id == 1212 && sv != 0 && !mHaveDdc) ||
            (id == 1213 && sv != 0 && !mHaveLiveprog)) {
            return true;
        }

        applyParam(&mDsp, id, sv, sv != 0,
                   reinterpret_cast<const float*>(val),
                   p->vsize / sizeof(float));
        return true;
    }

    JamesDSPLib mDsp{};
    std::mutex mMutex;
    std::mutex mDspMutex;
    std::atomic<bool> mRunning{false};
    std::thread mWorker;
    State mState{State::INIT};
    int mSampleRate{48000};
    int mChannels{2};

    uint32_t mParamCommits{0};
    int32_t mHashSlot[4]{0, 0, 0, 0};

    std::vector<char> mStringBuf;
    int mStringIndex{0};

    std::vector<float> mIrBuf;
    int mIrPartsSeen{0};
    int mIrParts{0};
    int mIrChannels{0};
    int mIrFrames{0};

    bool mHaveIr{false};
    bool mHaveGraphicEq{false};
    bool mHaveDdc{false};
    bool mHaveLiveprog{false};

    std::shared_ptr<StatusMQ> mStatusMQ;
    std::shared_ptr<DataMQ> mInputMQ, mOutputMQ;
};

}  // namespace aidl::android::hardware::audio::effect
