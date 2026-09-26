# OnePlus Android 16 JamesDSP integration

This branch targets the OnePlus sdm845 Android 16 / LineageOS 23.2 audio stack.

## Architecture

The device remains on the Qualcomm/OnePlus HIDL 6.0 audio and audio-effect HAL.
JamesDSP is therefore integrated as an additive legacy AudioEffect shared library:

```
app audio session
  -> AudioFlinger / effect chain
  -> JamesDSP (vendor/lib*/soundfx/libjamesdsp.so)
  -> existing OnePlus/QCOM audio HAL
  -> speaker / wired / Bluetooth / USB
```

The stock effect factory, `audio_effects.xml`, Dirac GEF, QCOM post-processing,
voice preprocessors, audio policy and mixer paths are not replaced.

## Android 16 fixes in this branch

- Source-built vendor soundfx module via `Android.bp`.
- No `-Ofast` / fast-math in DSP code.
- `SET_CONFIG` no longer reinitializes the whole DSP engine.
- Sample-rate/route changes preserve EQ, convolver, limiter and gain state.
- PCM float, 16-bit, 24-bit packed, 8.24 and 32-bit stereo paths.
- WRITE and ACCUMULATE effect-buffer modes.
- `INSERT_LAST` preference so the final JamesDSP output limiter is not
  unnecessarily followed by another software insert effect.

## Route acceptance matrix

Before merge, validate at minimum:

- Speaker: 44.1/48 kHz, repeated pause/resume and volume changes.
- Bluetooth: SBC, AAC and LDAC where supported; connect/disconnect during playback.
- USB DAC: 44.1/48/96/192 kHz where the DAC exposes them.
- Wired output when available.
- App/session open-close storms and rapid player switching.
- EQ / convolver / bass / compander / limiter individually and combined.
- Dirac enabled and disabled.
- Screen off/on, phone sleep/wake and AudioFlinger restart.
- Long playback plus rapid route changes.

For compressed offload, JamesDSP remains a non-offloadable software effect.
AudioFlinger should invalidate an active offload track when the effect is enabled
and reopen a software-processing path. Explicit DIRECT / bit-perfect outputs are
a separate bypass class and must be reported rather than silently claimed as
processed.
