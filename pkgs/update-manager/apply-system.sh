#!/bin/sh
# Privileged half of stewos-update-manager, run as root via run0. The
# transient service it runs in has a scrubbed environment and PATH, so
# everything here is an absolute path substituted at build time.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: stewos-apply-system <switch|boot> <nixos-system-store-path>" >&2
  exit 1
fi

action="$1"
system="$2"

case "$action" in
  switch | boot) ;;
  *)
    echo "stewos-apply-system: unknown action '$action'" >&2
    exit 1
    ;;
esac

case "$system" in
  /nix/store/*-nixos-system-*) ;;
  *)
    echo "stewos-apply-system: refusing to activate '$system'" >&2
    exit 1
    ;;
esac

@nix@/bin/nix-env --profile /nix/var/nix/profiles/system --set "$system"
exec "$system/bin/switch-to-configuration" "$action"
