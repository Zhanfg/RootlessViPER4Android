package me.timschneeberger.rootlessjamesdsp.fragment.settings

import android.content.Intent
import android.os.Bundle
import androidx.preference.ListPreference
import androidx.preference.Preference
import me.timschneeberger.rootlessjamesdsp.R
import me.timschneeberger.rootlessjamesdsp.utils.Constants
import me.timschneeberger.rootlessjamesdsp.utils.V4aMode
import me.timschneeberger.rootlessjamesdsp.utils.extensions.ContextExtensions.sendLocalBroadcast
import me.timschneeberger.rootlessjamesdsp.utils.isPlugin
import me.timschneeberger.rootlessjamesdsp.utils.isRootless

class SettingsFragment : SettingsBaseFragment() {

    private val processing by lazy { findPreference<Preference>(getString(R.string.key_audio_format)) }
    private val troubleshooting by lazy { findPreference<Preference>(getString(R.string.key_troubleshooting)) }

    override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
        preferenceManager.sharedPreferencesName = Constants.PREF_APP
        setPreferencesFromResource(R.xml.app_preferences, rootKey)

        findPreference<ListPreference>(getString(R.string.key_dsp_mode))?.apply {
            value = V4aMode.currentMode(requireContext()).value
            setOnPreferenceChangeListener { _, newValue ->
                val mode = V4aMode.DspMode.fromValue(newValue as? String)
                V4aMode.setMode(requireContext(), mode)
                requireContext().sendLocalBroadcast(Intent(Constants.ACTION_PREFERENCES_UPDATED))
                true
            }
        }

        processing?.summary = getString(
            when {
                isRootless() -> R.string.audio_format_summary
                isPlugin() -> R.string.audio_format_summary_plugin
                else -> R.string.audio_format_summary_root
            }
        )
        troubleshooting?.isVisible = isRootless()
    }

    companion object {
        fun newInstance(): SettingsFragment {
            return SettingsFragment()
        }
    }
}
