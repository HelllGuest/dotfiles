# 09-identity.sh — part of HelllGuest/dotfiles (stage-a)
# shellcheck shell=bash
# Wizard step 7/11: hostname, user, passwords, locale, timezone, keymap.
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

# ── 4. identity (validated before wipe / LUKS at step 11) ───
ui_step 7 Identity
if (( NONINTERACTIVE )); then
  [[ -n ${HOSTNAME:-} ]] || die "NONINTERACTIVE needs HOSTNAME in answers"
  valid_hostname "$HOSTNAME" || die "invalid hostname (DNS labels only): ${HOSTNAME}"
  [[ -n ${TIMEZONE:-} ]] || die "NONINTERACTIVE needs TIMEZONE in answers"
  valid_timezone "$TIMEZONE" || die "NONINTERACTIVE needs valid TIMEZONE in answers"
  ok "timezone from answers: $TIMEZONE"
  [[ -n ${LOCALE:-} ]] || die "NONINTERACTIVE needs LOCALE in answers"
  valid_locale "$LOCALE" || die "NONINTERACTIVE needs valid LOCALE in answers"
  ok "locale: $LOCALE"
  [[ -n ${KEYMAP:-} ]] || die "NONINTERACTIVE needs KEYMAP in answers"
  valid_keymap "$KEYMAP" || die "NONINTERACTIVE needs valid KEYMAP in answers"
  ok "keymap: $KEYMAP"
  if (( ! DRYRUN )) && command -v loadkeys >/dev/null 2>&1; then
    loadkeys "$KEYMAP" 2>/dev/null || warn "loadkeys $KEYMAP failed on live ISO (vconsole still set in target)"
  fi
  [[ -n ${USERNAME:-} ]] || die "NONINTERACTIVE needs USERNAME in answers"
  valid_username "$USERNAME" || die "NONINTERACTIVE needs valid USERNAME in answers"
  ok "username from answers: $USERNAME"
  if (( SECRETS_FROM_FILE )); then
    ok "user/root passwords from T14S_PASS_FILE"
  fi
  if [[ -n ${SSH_PUBKEY:-} ]]; then
    [[ $SSH_PUBKEY != *$'\n'* && $SSH_PUBKEY =~ ^(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] \
      || die "invalid SSH_PUBKEY (expected single-line OpenSSH public key)"
  fi
else
  _id_step=0
  _id_hist=()
  while (( _id_step < 8 )); do
    _id_back=0
    case $_id_step in
      0)
        while :; do
          if (( ${QUICK_VM:-0} )); then _hn_default=arch-vm
          else
            case ${HW_PROFILE:-generic} in
              t14s) _hn_default=thinkpad-t14s ;;
              p15)  _hn_default=p15 ;;
              *)    _hn_default=archlinux ;;
            esac
          fi
          _rc=0; HOSTNAME="$(ui_input "Hostname" "${HOSTNAME:-$_hn_default}")" || _rc=$?
          unset -v _hn_default
          if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc _id_step _id_hist _id_back; WIZARD_BACK=1; return 0; fi
          if (( _rc != 0 )); then die "aborted"; fi
          unset -v _rc
          [[ -n $HOSTNAME ]] || { ui_warn "hostname cannot be empty"; continue; }
          valid_hostname "$HOSTNAME" && break
          ui_error "invalid hostname (DNS labels only; no leading/trailing hyphen)"
        done
        _id_hist+=(0); _id_step=1
        ;;
      1)
        if (( ${QUICK_VM:-0} )); then
          [[ -n ${TIMEZONE:-} ]] || die "NONINTERACTIVE needs TIMEZONE in answers"
          valid_timezone "$TIMEZONE" || die "NONINTERACTIVE needs valid TIMEZONE in answers"
          ok "timezone (Quick VM): $TIMEZONE"
          _id_step=2
        else
          while :; do
            _rc=0; TIMEZONE="$(WIZARD_CAN_BACK=1 pick_timezone)" || _rc=$?
            if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _id_back=1; break; fi
            if (( _rc != 0 )); then die "aborted"; fi
            unset -v _rc
            valid_timezone "$TIMEZONE" && break
            ui_error "Timezone not a TZif zone file: ${TIMEZONE:-<empty>} — pick again."
          done
          if (( ! _id_back )); then _id_hist+=(1); _id_step=2; fi
        fi
        ;;
      2)
        if (( ${QUICK_VM:-0} )); then
          [[ -n ${LOCALE:-} ]] || die "NONINTERACTIVE needs LOCALE in answers"
          valid_locale "$LOCALE" || die "NONINTERACTIVE needs valid LOCALE in answers"
          ok "locale: $LOCALE"
          _id_step=3
        else
          while :; do
            _loc_prev=${LOCALE:-en_US.UTF-8}
            _lu=off; _lg=off; _ld=off; _lf=off; _ls=off; _lo=off
            case $_loc_prev in
              en_GB.UTF-8) _lg=on ;;
              de_DE.UTF-8) _ld=on ;;
              fr_FR.UTF-8) _lf=on ;;
              es_ES.UTF-8) _ls=on ;;
              en_US.UTF-8) _lu=on ;;
              *) _lo=on ;;
            esac
            _rc=0
            LOCALE="$(WIZARD_CAN_BACK=1 ui_radio "System locale" \
              en_US.UTF-8 "English (US)" "$_lu" \
              en_GB.UTF-8 "English (UK)" "$_lg" \
              de_DE.UTF-8 "German" "$_ld" \
              fr_FR.UTF-8 "French" "$_lf" \
              es_ES.UTF-8 "Spanish" "$_ls" \
              other "type a locale (e.g. pt_BR.UTF-8)" "$_lo")" || _rc=$?
            unset -v _lu _lg _ld _lf _ls _lo
            if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc _loc_prev; _id_back=1; break; fi
            if (( _rc != 0 )); then die "aborted"; fi
            unset -v _rc
            if [[ $LOCALE == other ]]; then
              _rc=0; LOCALE="$(WIZARD_CAN_BACK=1 ui_input "Locale" "$_loc_prev")" || _rc=$?
              if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc _loc_prev; continue; fi
              if (( _rc != 0 )); then die "aborted"; fi
              unset -v _rc
            fi
            unset -v _loc_prev
            valid_locale "$LOCALE" && break
            ui_error "locale not in SUPPORTED/locale.gen: ${LOCALE:-<empty>}"
          done
          if (( ! _id_back )); then _id_hist+=(2); _id_step=3; fi
        fi
        ;;
      3)
        if (( ${QUICK_VM:-0} )); then
          [[ -n ${KEYMAP:-} ]] || die "NONINTERACTIVE needs KEYMAP in answers"
          valid_keymap "$KEYMAP" || die "NONINTERACTIVE needs valid KEYMAP in answers"
          ok "keymap: $KEYMAP"
          if (( ! DRYRUN )) && command -v loadkeys >/dev/null 2>&1; then
            loadkeys "$KEYMAP" 2>/dev/null || warn "loadkeys $KEYMAP failed on live ISO (vconsole still set in target)"
          fi
          _id_step=4
        else
          while :; do
            _rc=0; KEYMAP="$(WIZARD_CAN_BACK=1 pick_keymap)" || _rc=$?
            if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _id_back=1; break; fi
            if (( _rc != 0 )); then die "aborted"; fi
            unset -v _rc
            valid_keymap "$KEYMAP" && break
            ui_error "keymap not available: ${KEYMAP:-<empty>} — pick again."
          done
          if (( ! _id_back )); then
            if (( ! DRYRUN )) && command -v loadkeys >/dev/null 2>&1; then
              loadkeys "$KEYMAP" 2>/dev/null || warn "loadkeys $KEYMAP failed on live ISO (vconsole still set in target)"
            fi
            _id_hist+=(3); _id_step=4
          fi
        fi
        ;;
      4)
        _un_def="${USERNAME:-}"
        if (( ${QUICK_VM:-0} )) && [[ -z $_un_def ]]; then _un_def=arch; fi
        while :; do
          _rc=0; USERNAME="$(WIZARD_CAN_BACK=1 ui_input "Username (lowercase POSIX)" "$_un_def")" || _rc=$?
          if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc _un_def; _id_back=1; break; fi
          if (( _rc != 0 )); then die "aborted"; fi
          unset -v _rc
          _un_def="$USERNAME"
          if [[ -z $USERNAME ]]; then
            ui_warn "username cannot be empty"
          elif [[ $USERNAME == root ]]; then
            ui_warn "username cannot be 'root'"
          elif ! valid_username "$USERNAME"; then
            ui_error "invalid username (^[a-z_][a-z0-9_-]*\$, ≤32, not an existing user/group)"
          else
            break
          fi
        done
        unset -v _un_def
        if (( ! _id_back )); then _id_hist+=(4); _id_step=5; fi
        ;;
      5)
        if (( SECRETS_FROM_FILE )); then
          ok "user/root passwords from T14S_PASS_FILE"
          _id_step=7
        elif (( ${QUICK_VM:-0} )); then
          while :; do
            _rc=0; USER_PASS="$(WIZARD_CAN_BACK=1 ui_password "Password for $USERNAME (also used for root)")" || _rc=$?
            if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _id_back=1; break; fi
            if (( _rc != 0 )); then die "aborted"; fi
            _rc=0; USER_PASS2="$(WIZARD_CAN_BACK=1 ui_password "Repeat password for $USERNAME")" || _rc=$?
            if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; continue; fi
            if (( _rc != 0 )); then die "aborted"; fi
            unset -v _rc
            [[ -n $USER_PASS && $USER_PASS == "$USER_PASS2" ]] && break
            ui_warn "Empty or mismatched password — retry."
          done
          if (( ! _id_back )); then ROOT_PASS="$USER_PASS"; _id_hist+=(5); _id_step=7; fi
        else
          while :; do
            _rc=0; USER_PASS="$(WIZARD_CAN_BACK=1 ui_password "Password for $USERNAME")" || _rc=$?
            if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _id_back=1; break; fi
            if (( _rc != 0 )); then die "aborted"; fi
            _rc=0; USER_PASS2="$(WIZARD_CAN_BACK=1 ui_password "Repeat password for $USERNAME")" || _rc=$?
            if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; continue; fi
            if (( _rc != 0 )); then die "aborted"; fi
            unset -v _rc
            [[ -n $USER_PASS && $USER_PASS == "$USER_PASS2" ]] && break
            ui_warn "Empty or mismatched password — retry."
          done
          if (( ! _id_back )); then _id_hist+=(5); _id_step=6; fi
        fi
        ;;
      6)
        while :; do
          _rc=0; ROOT_PASS="$(WIZARD_CAN_BACK=1 ui_password 'Root password')" || _rc=$?
          if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _id_back=1; break; fi
          if (( _rc != 0 )); then die "aborted"; fi
          _rc=0; ROOT_PASS2="$(WIZARD_CAN_BACK=1 ui_password 'Repeat root password')" || _rc=$?
          if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; continue; fi
          if (( _rc != 0 )); then die "aborted"; fi
          unset -v _rc
          [[ -n $ROOT_PASS && $ROOT_PASS == "$ROOT_PASS2" ]] && break
          ui_warn "Empty or mismatched password — retry."
        done
        if (( ! _id_back )); then _id_hist+=(6); _id_step=7; fi
        ;;
      7)
        if (( ${QUICK_VM:-0} )); then
          while :; do
            _rc=0; SSH_PUBKEY="$(WIZARD_CAN_BACK=1 ui_input "Optional SSH public key for $USERNAME (empty=password only)" "${SSH_PUBKEY:-}")" || _rc=$?
            if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _id_back=1; break; fi
            if (( _rc != 0 )); then die "aborted"; fi
            unset -v _rc
            [[ -z $SSH_PUBKEY ]] && break
            if [[ $SSH_PUBKEY != *$'\n'* && $SSH_PUBKEY =~ ^(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
              break
            fi
            ui_error "Invalid SSH public key (expected single-line ssh-ed25519 / ssh-rsa / ecdsa-* / sk-* key)."
          done
          if (( ! _id_back )); then _id_step=8; fi
        else
          if [[ -n ${SSH_PUBKEY:-} ]]; then
            [[ $SSH_PUBKEY != *$'\n'* && $SSH_PUBKEY =~ ^(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] \
              || die "invalid SSH_PUBKEY (expected single-line OpenSSH public key)"
          fi
          _id_step=8
        fi
        ;;
    esac
    if (( _id_back )); then
      _id_step="${_id_hist[${#_id_hist[@]}-1]}"
      unset "_id_hist[${#_id_hist[@]}-1]"
    fi
  done
  unset -v _id_step _id_hist _id_back
fi
unset -v LUKS_PASS2 USER_PASS2 ROOT_PASS2
