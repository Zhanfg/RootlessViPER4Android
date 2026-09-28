package me.timschneeberger.rootlessjamesdsp.utils

import android.content.Context
import me.timschneeberger.rootlessjamesdsp.R

/**
 * Compatibility wrapper around the app's three DSP modes.
 *
 * The project used to expose a single "ViPER4Android only" boolean. Keep that
 * key readable for existing installs, but make the canonical state explicit:
 * JamesDSP, ViPER4Android or Hybrid.
 */
object V4aMode {
    const val KEY = "v4a_only_mode"
    const val MODE_KEY = "dsp_mode"

    enum class DspMode(val value: String) {
        HYBRID("hybrid"),
        JAMESDSP("jamesdsp"),
        VIPER("viper");

        companion object {
            fun fromValue(raw: String?): DspMode =
                entries.firstOrNull { it.value == raw } ?: HYBRID
        }
    }

    @Volatile
    private var cachedMode: DspMode? = null

    fun currentMode(ctx: Context): DspMode {
        cachedMode?.let { return it }

        val prefs = ctx.getSharedPreferences(Constants.PREF_APP, Context.MODE_PRIVATE)
        val stored = prefs.getString(MODE_KEY, null)
        val mode = if (stored != null) {
            DspMode.fromValue(stored)
        } else if (prefs.getBoolean(KEY, false)) {
            DspMode.VIPER
        } else {
            DspMode.HYBRID
        }

        // One-way migration: old installs keep their previous V4A-only choice.
        // The legacy boolean is still mirrored by setMode() for downgrade safety.
        if (stored == null) {
            prefs.edit().putString(MODE_KEY, mode.value).apply()
        }

        cachedMode = mode
        return mode
    }

    /** Existing engine code uses this to select V4A-specific processing rules. */
    fun isOn(ctx: Context): Boolean = currentMode(ctx) == DspMode.VIPER

    fun invalidate() {
        cachedMode = null
    }

    fun setMode(ctx: Context, mode: DspMode) {
        ctx.getSharedPreferences(Constants.PREF_APP, Context.MODE_PRIVATE)
            .edit()
            .putString(MODE_KEY, mode.value)
            .putBoolean(KEY, mode == DspMode.VIPER)
            .apply()
        cachedMode = mode

        when (mode) {
            DspMode.JAMESDSP -> disableNonJamesEffects(ctx)
            DspMode.VIPER -> disableNonV4aEffects(ctx)
            DspMode.HYBRID -> Unit
        }
    }

    /**
     * Effects that were not part of upstream RootlessJamesDSP. JamesDSP mode
     * keeps the upstream app/engine surface intact and switches every fork-only
     * effect off so hidden engines do not continue consuming audio resources.
     */
    private fun nonJames(ctx: Context) = listOf(
        Constants.PREF_BASSEX to R.string.key_bassex_enable,
        Constants.PREF_SPECTRUMEXT to R.string.key_spectrumext_enable,
        Constants.PREF_VDYNBASS to R.string.key_vdynbass_enable,
        Constants.PREF_DIFFSURROUND to R.string.key_diffsurround_enable,
        Constants.PREF_CLARITY to R.string.key_clarity_enable,
        Constants.PREF_FIELDSURROUND to R.string.key_fieldsurround_enable,
        Constants.PREF_AGC to R.string.key_agc_enable,
        Constants.PREF_HPSURROUND to R.string.key_hpsurround_enable,
        Constants.PREF_FETCOMP to R.string.key_fetcomp_enable,
        Constants.PREF_CURE to R.string.key_cure_enable,
        Constants.PREF_VIPERBASS to R.string.key_viperbass_enable,
        Constants.PREF_VREVERB to R.string.key_vreverb_enable,
        Constants.PREF_SPEAKEROPT to R.string.key_speakeropt_enable,
        Constants.PREF_PITCHSHIFT to R.string.key_pitchshift_enable,
        Constants.PREF_ECHODELAY to R.string.key_echo_enable,
        Constants.PREF_MULTIBANDDIST to R.string.key_mbd_enable,
        Constants.PREF_MAXIMIZER to R.string.key_maxr_enable,
        Constants.PREF_DYNAMICEQ to R.string.key_dyneq_enable,
        Constants.PREF_IMAGING to R.string.key_imaging_enable,
        Constants.PREF_TRANSIENT to R.string.key_transient_enable,
        Constants.PREF_LOWEND to R.string.key_lowend_enable,
        Constants.PREF_EXCITER to R.string.key_exciter_enable,
        Constants.PREF_TAPE to R.string.key_tape_enable,
        Constants.PREF_VINYL to R.string.key_vinyl_enable,
        Constants.PREF_BALANCE to R.string.key_balance_enable,
        Constants.PREF_LIVEPROG2 to R.string.key_liveprog2_enable,
        Constants.PREF_LIVEPROG3 to R.string.key_liveprog3_enable,
        Constants.PREF_LIVEPROG4 to R.string.key_liveprog4_enable,
    )

    /** Effects the original ViPER4Android did not have. */
    private fun nonV4a(ctx: Context) = listOf(
        Constants.PREF_COMPANDER to R.string.key_compander_enable,
        Constants.PREF_BASS to R.string.key_bass_enable,
        Constants.PREF_BASSEX to R.string.key_bassex_enable,
        Constants.PREF_PITCHSHIFT to R.string.key_pitchshift_enable,
        Constants.PREF_ECHODELAY to R.string.key_echo_enable,
        Constants.PREF_MULTIBANDDIST to R.string.key_mbd_enable,
        Constants.PREF_MAXIMIZER to R.string.key_maxr_enable,
        Constants.PREF_DYNAMICEQ to R.string.key_dyneq_enable,
        Constants.PREF_IMAGING to R.string.key_imaging_enable,
        Constants.PREF_TRANSIENT to R.string.key_transient_enable,
        Constants.PREF_LOWEND to R.string.key_lowend_enable,
        Constants.PREF_EXCITER to R.string.key_exciter_enable,
        Constants.PREF_TAPE to R.string.key_tape_enable,
        Constants.PREF_VINYL to R.string.key_vinyl_enable,
        Constants.PREF_BALANCE to R.string.key_balance_enable,
        Constants.PREF_GEQ to R.string.key_geq_enable,
        Constants.PREF_PEQ to R.string.key_peq_enable,
        Constants.PREF_LIVEPROG to R.string.key_liveprog_enable,
        Constants.PREF_LIVEPROG2 to R.string.key_liveprog2_enable,
        Constants.PREF_LIVEPROG3 to R.string.key_liveprog3_enable,
        Constants.PREF_LIVEPROG4 to R.string.key_liveprog4_enable,
        Constants.PREF_STEREOWIDE to R.string.key_stereowide_enable,
        Constants.PREF_CROSSFEED to R.string.key_crossfeed_enable,
        Constants.PREF_REVERB to R.string.key_reverb_enable,
    )

    private val viperHiddenCardIds = intArrayOf(
        R.id.card_compressor, R.id.card_bass, R.id.card_bassex,
        R.id.card_pitchshift, R.id.card_echo, R.id.card_mbd, R.id.card_maxr,
        R.id.card_dyneq, R.id.card_imaging, R.id.card_transient,
        R.id.card_lowend, R.id.card_exciter, R.id.card_tape, R.id.card_vinyl,
        R.id.card_balance, R.id.card_geq, R.id.card_peq, R.id.card_liveprog,
        R.id.card_liveprog2, R.id.card_liveprog3, R.id.card_liveprog4,
        R.id.card_stereowide, R.id.card_crossfeed, R.id.card_reverb,
    )

    /**
     * Everything absent from upstream RootlessJamesDSP. This list is purposely
     * based on the upstream card set rather than names containing "ViPER": the
     * fork also has non-ViPER studio effects, and pure JamesDSP mode excludes
     * those too.
     */
    private val jamesHiddenCardIds = intArrayOf(
        R.id.card_bassex, R.id.card_vdynbass, R.id.card_diffsurround,
        R.id.card_clarity, R.id.card_fieldsurround, R.id.card_hpsurround,
        R.id.card_fetcomp, R.id.card_cure, R.id.card_viperbass,
        R.id.card_vreverb, R.id.card_speakeropt, R.id.card_pitchshift,
        R.id.card_echo, R.id.card_mbd, R.id.card_maxr, R.id.card_dyneq,
        R.id.card_imaging, R.id.card_transient, R.id.card_lowend,
        R.id.card_exciter, R.id.card_tape, R.id.card_vinyl, R.id.card_balance,
        R.id.card_liveprog2, R.id.card_liveprog3, R.id.card_liveprog4,
        R.id.card_agc, R.id.card_spectrumext,
    )

    /** Legacy property kept for existing callers; it means V4A-only hidden cards. */
    val hiddenCardIds: IntArray
        get() = viperHiddenCardIds

    fun hiddenCardIdsFor(ctx: Context): IntArray = when (currentMode(ctx)) {
        DspMode.HYBRID -> intArrayOf()
        DspMode.JAMESDSP -> jamesHiddenCardIds
        DspMode.VIPER -> viperHiddenCardIds
    }

    /**
     * Original ViPER4Android processing order, taken from ViPER.cpp in the
     * ViPERFX_RE decompilation. The output limiter remains last in the engine.
     */
    val v4aChainOrder = intArrayOf(
        11, // JDSP_EFX_CONVOLVER
        21, // JDSP_EFX_HPSURROUND
        12, // JDSP_EFX_DDC
        22, // JDSP_EFX_SPECTRUMEXT
        9,  // JDSP_EFX_EQUALIZER
        20, // JDSP_EFX_FIELDSURROUND
        4,  // JDSP_EFX_DIFFSURROUND
        27, // JDSP_EFX_VREVERB
        25, // JDSP_EFX_SPEAKEROPT
        24, // JDSP_EFX_AGC
        3,  // JDSP_EFX_FETCOMP
        6,  // JDSP_EFX_VDYNBASS
        7,  // JDSP_EFX_VIPERBASS
        23, // JDSP_EFX_CLARITY
        18, // JDSP_EFX_CURE
        0,  // JDSP_EFX_TUBE
    )

    fun disableNonV4aEffects(ctx: Context) = disable(ctx, nonV4a(ctx))

    fun disableNonJamesEffects(ctx: Context) = disable(ctx, nonJames(ctx))

    /**
     * Reassert the selected mode before every engine preference sync. This is
     * what keeps a preset import or backup restore from silently re-enabling an
     * effect that the active mode promises is absent.
     */
    fun enforceCurrentMode(ctx: Context) {
        when (currentMode(ctx)) {
            DspMode.JAMESDSP -> disableNonJamesEffects(ctx)
            DspMode.VIPER -> disableNonV4aEffects(ctx)
            DspMode.HYBRID -> Unit
        }
    }

    private fun disable(ctx: Context, effects: List<Pair<String, Int>>) {
        effects.forEach { (namespace, keyRes) ->
            val prefs = ctx.getSharedPreferences(namespace, Context.MODE_MULTI_PROCESS)
            val key = ctx.getString(keyRes)
            if (prefs.getBoolean(key, false)) {
                prefs.edit().putBoolean(key, false).apply()
            }
        }
    }
}
