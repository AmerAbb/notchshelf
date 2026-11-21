#!/bin/zsh
# Resolve the code-signing identity into $IDENTITY. Sourced, not run.
#
# Why a real certificate locally: notchshelf reads your Desktop (for Simulator
# screenshots), which macOS gates behind a privacy prompt. TCC remembers the
# grant against the app's designated requirement. With an ad-hoc signature
# that requirement is the code hash, which changes on every rebuild, so macOS
# would ask again after each ./install.sh. A real certificate pins it.
#
# CI builds pass NOTCHSHELF_SIGN_IDENTITY="-" (ad-hoc), like Dictation's.
#
# Order: $NOTCHSHELF_SIGN_IDENTITY → $PREFERRED → any Apple Development → ad-hoc.

# A personal Apple ID, pinned deliberately: `security find-identity` lists an
# employer's team first on this machine, and a personal side project shouldn't
# be signed with a work team.
PREFERRED="${NOTCHSHELF_PREFERRED_IDENTITY:-Apple Development: amer.abboud19@gmail.com (3R792YL69C)}"

_identity_available() {
  security find-identity -v -p codesigning 2>/dev/null | grep -qF -- "$1"
}

IDENTITY="${NOTCHSHELF_SIGN_IDENTITY:-}"

if [[ -z "$IDENTITY" ]] && _identity_available "$PREFERRED"; then
  IDENTITY="$PREFERRED"
fi

if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)".*/\1/')
  [[ -n "$IDENTITY" ]] && echo "note: '$PREFERRED' isn't in the keychain; using '$IDENTITY' instead."
fi

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  echo "note: no Apple Development certificate found; signing ad-hoc."
  echo "      macOS will re-ask for Desktop access after each rebuild."
fi
