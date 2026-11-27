# 08-luks.sh — part of HelllGuest/dotfiles (stage-a)
# shellcheck shell=bash
# Wizard step 6/11: LUKS passphrase and optional mapper wipe.
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

# ── 3. luks passphrase + optional mapper wipe (archfi-style) ─
ui_step 6 LUKS
if ! yn_on "${ENCRYPT_ROOT:-Y}"; then
  LUKS_WIPE=none
  WIZARD_SKIPPED_STEP=1
  ok "root encryption skipped (ENCRYPT_ROOT=N)"
else
if (( NONINTERACTIVE )); then
  [[ -n ${LUKS_PASS:-} ]] \
    || die "T14S_PASS_FILE must set LUKS_PASS when ENCRYPT_ROOT=Y"
fi
while :; do
  if (( SECRETS_FROM_FILE )); then
    ok "LUKS passphrase from T14S_PASS_FILE"
  else
    while :; do
      _rc=0; LUKS_PASS="$(ui_password 'LUKS passphrase')" || _rc=$?
      if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; WIZARD_BACK=1; return 0; fi
      if (( _rc != 0 )); then die "aborted"; fi
      _rc=0; LUKS_PASS2="$(WIZARD_CAN_BACK=1 ui_password 'Repeat LUKS passphrase')" || _rc=$?
      if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; continue; fi
      if (( _rc != 0 )); then die "aborted"; fi
      unset -v _rc
      [[ -n $LUKS_PASS && $LUKS_PASS == "$LUKS_PASS2" ]] && break
      ui_warn "Empty or mismatched LUKS passphrase — retry."
    done
  fi
  if (( NONINTERACTIVE )); then
    [[ ${LUKS_WIPE:-none} =~ ^(none|fast|normal)$ ]] \
      || die "NONINTERACTIVE needs LUKS_WIPE=none|fast|normal in answers"
    LUKS_WIPE=${LUKS_WIPE:-none}
    break
  else
    _wn=off; _wf=off; _wo=off
    case ${LUKS_WIPE:-none} in
      fast) _wf=on ;;
      normal) _wo=on ;;
      *) _wn=on; LUKS_WIPE=none ;;
    esac
    _luks_can_back=${WIZARD_CAN_BACK:-0}
    (( ! SECRETS_FROM_FILE )) && _luks_can_back=1
    _rc=0
    LUKS_WIPE="$(WIZARD_CAN_BACK=$_luks_can_back ui_radio "Wipe LUKS mapper before mkfs? (paranoia; slow on large disks)" \
      none "skip — mkfs only (default)" "$_wn" \
      fast "dd zeros bs=64M until full" "$_wf" \
      normal "dd zeros (slow, thorough)" "$_wo")" || _rc=$?
    unset -v _wn _wf _wo _luks_can_back
    if (( _rc == ${T14S_RC_BACK:-10} )); then
      unset -v _rc
      if (( ! SECRETS_FROM_FILE )); then continue; fi
      WIZARD_BACK=1; return 0
    elif (( _rc != 0 )); then
      die "aborted"
    fi
    unset -v _rc
    break
  fi
done
fi
