# The upstream caelestia-shell (from the flake input, injected into the scope by
# overlays/default.nix) with pam_gnome_keyring added to the locker's PAM stack.
#
# These hosts autologin, so greetd never collects a password and the
# pam_gnome_keyring lines in /etc/pam.d/login have no authtok to work with -- the
# login keyring stays locked for the whole session. The lock screen is the only
# place a password is actually typed, so it is where the keyring gets unlocked.
#
# Caelestia's locker reads its PAM stack from inside the package rather than
# /etc/pam.d (modules/lock/Pam.qml sets the Quickshell PamContext's
# configDirectory to shellDir + "/assets/pam.d"), which is what makes this a
# packaging change instead of an upstream patch.
#
# Quickshell calls only pam_start_confdir/pam_authenticate/pam_end -- there is no
# pam_setcred and no session phase. That would defeat a module doing its work in
# pam_sm_setcred, but pam_gnome_keyring calls unlock_keyring from
# pam_sm_authenticate itself (its pam_sm_setcred is a stub that returns
# success), so the auth line alone is enough.
#
# The upstream package only exists for Linux systems, so the injected value is
# null elsewhere; flake.nix's packages filter drops the null.
{
  caelestia-shell-upstream,
  gnome-keyring,
}:
if caelestia-shell-upstream == null then
  null
else
  caelestia-shell-upstream.overrideAttrs (old: {
    # Appended, never inserted. The stack upstream ships is:
    #
    #   auth required                pam_faillock.so preauth
    #   auth [success=1 default=bad] pam_unix.so nullok
    #   auth [default=die]           pam_faillock.so authfail
    #   auth required                pam_faillock.so authsucc
    #
    # "success=1" counts modules, so adding a line anywhere above authsucc makes
    # pam_unix jump over the wrong one. Appending is also what we want
    # semantically: "default=die" means the new line is only ever reached after
    # a successful authentication.
    #
    # postPatch rather than prePatch because upstream's nix/default.nix already
    # uses prePatch to substituteInPlace assets/pam.d/{fprint,howdy}; staying on
    # the other hook keeps this from colliding if that grows.
    #
    # The module is referenced by store path. Upstream points fprint and howdy at
    # /run/current-system/sw/lib/security, which does resolve here, but the store
    # path always resolves and gnome-keyring is in the system closure regardless.
    postPatch = (old.postPatch or "") + ''
      echo 'auth    optional                    ${gnome-keyring}/lib/security/pam_gnome_keyring.so' >> assets/pam.d/passwd
    '';
  })
