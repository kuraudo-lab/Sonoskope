#!/bin/bash
# Shared by packaging scripts; never enable shell tracing around signing secrets.
distribution="${SONOSKOPE_DISTRIBUTION:-preview}"
case "$distribution" in
  preview|developer-id) ;;
  *) echo 'SONOSKOPE_DISTRIBUTION must be preview or developer-id.' >&2; exit 1 ;;
esac
signing_keychain=()
notary_keychain=()
if [[ -n "${SONOSKOPE_SIGNING_KEYCHAIN:-}" ]]; then
  signing_keychain=(--keychain "$SONOSKOPE_SIGNING_KEYCHAIN")
fi
if [[ -n "${SONOSKOPE_NOTARY_KEYCHAIN:-}" ]]; then
  notary_keychain=(--keychain "$SONOSKOPE_NOTARY_KEYCHAIN")
fi
require_distribution_credentials() {
  [[ "${SONOSKOPE_APPLICATION_IDENTITY:-}" == 'Developer ID Application: '* ]] || {
    echo 'Set SONOSKOPE_APPLICATION_IDENTITY to a Developer ID Application certificate name.' >&2; return 1;
  }
  [[ "${SONOSKOPE_INSTALLER_IDENTITY:-}" == 'Developer ID Installer: '* ]] || {
    echo 'Set SONOSKOPE_INSTALLER_IDENTITY to a Developer ID Installer certificate name.' >&2; return 1;
  }
  [[ -n "${SONOSKOPE_NOTARY_PROFILE:-}" ]] || {
    echo 'Set SONOSKOPE_NOTARY_PROFILE to a stored notarytool keychain profile.' >&2; return 1;
  }
}
