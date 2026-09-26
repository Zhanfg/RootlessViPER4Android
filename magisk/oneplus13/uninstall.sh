#!/system/bin/sh
PKG="com.alienware377.viper4android.rootful"

# The controller belongs to this OnePlus 13 engine package. Remove it with the
# module so an orphaned UI cannot keep claiming that a DSP engine is present.
cmd package uninstall "$PKG" >/dev/null 2>&1 || pm uninstall "$PKG" >/dev/null 2>&1 || true
