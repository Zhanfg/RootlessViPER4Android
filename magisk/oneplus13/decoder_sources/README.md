# Decoder Source Mount Layer

This directory defines optional add-on decoder sources for the OnePlus 13 module.

The layer is separate from JamesDSP. A source may add a new Codec2 component store,
but it must not replace the stock QTI Codec2 service by default.

## Package layout

```text
<id>/
├── source.prop
├── mount.map
├── payload/
├── verify.sh
└── health.sh
```

External sources can be placed under:

```text
/data/adb/jdsp/decoder_sources/<id>/
```

Select one by writing its id to:

```text
/data/adb/jdsp/decoder_source.conf
```

Use `none` to disable the layer.

## source.prop

Example:

```properties
id=example
name=Example Codec2 store
version=1
backend=codec2-service
abi=arm64-v8a
android_min=36
android_max=37
service_instance=example
expected_components=c2.example.flac.decoder,c2.example.alac.decoder
allow_replace=0
```

Supported backends: `codec2-service`, `codec2-apex`, `codec2-library`.

Keep `allow_replace=0` unless a source has been explicitly audited for replacing a
stock file. The normal design is additive: a separate IComponentStore instance.

## mount.map

Each non-comment line:

```text
payload-relative-path|absolute-target-path|mode
```

Targets are restricted to decoder-related vendor/odm bin, lib64, init, VINTF,
seccomp and media_codecs locations.

## FFmpeg Codec2 reference

The first reference adapter targets
`raspberry-vanilla/android_external_ffmpeg_codec2`, which exposes
`android.hardware.media.c2.IComponentStore/ffmpeg` and components such as
`c2.ffmpeg.aac.decoder`, `c2.ffmpeg.ac3.decoder`, `c2.ffmpeg.alac.decoder`,
`c2.ffmpeg.flac.decoder`, `c2.ffmpeg.mp2.decoder`,
`c2.ffmpeg.mp3.decoder`, and `c2.ffmpeg.vorbis.decoder`.

Only metadata is shipped until a PJZ110/API 36 compatible payload is built and verified.
