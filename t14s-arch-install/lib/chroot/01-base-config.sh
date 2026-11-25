# 01-base-config.sh — part of HelllGuest/t14s-arch-install
# shellcheck shell=bash
# Chroot stage 0-4 %: locale, time, hostname, pacman, pacman cache trim.
# Sourced by 80-chroot-setup.sh inside arch-chroot, at top level and in
# order: shares its helpers, globals, set -e and umask as if inline.

stage 0 4 "locale, time, hostname, pacman"
# time / locale / keymap
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
# Escape BRE metacharacters so en_US.UTF-8 dots are literal in sed.
_loc_esc=$(printf '%s\n' "$LOCALE" | sed 's/[.[\\*^$]/\\&/g')
sed -i "s/^#${_loc_esc} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
grep -qxF "${LOCALE} UTF-8" /etc/locale.gen \
  || echo "${LOCALE} UTF-8" >> /etc/locale.gen
unset -v _loc_esc
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# hostname / hosts: FQDN first, then short label (Debian/Ubuntu convention).
echo "$HOSTNAME" > /etc/hostname
_host_short=${HOSTNAME%%.*}
if [[ $_host_short == "$HOSTNAME" ]]; then
  cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
else
  cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME} ${_host_short}
EOF
fi
unset -v _host_short

# pacman before the UKI stage: a multilib -Syu that upgrades a kernel then
# runs its mkinitcpio hook before our presets exist (no double UKI build).
# pacman: parallel built-in downloader, no download timeout abort, Color/
# ILoveCandy/VerbosePkgLists, optional [multilib] (same helper as the live ISO).
PACMAN_PARALLEL="${PACMAN_PARALLEL:-10}"
pacman_tune /etc/pacman.conf "$PACMAN_PARALLEL" "$(yn_on "${INSTALL_MULTILIB:-N}" && echo Y || echo N)"
if yn_on "${INSTALL_MULTILIB:-N}"; then
  # -Syu, never bare -Sy (partial upgrades); target is fresh so this is cheap.
  pacman -Syu --noconfirm || say "WARN: could not sync [multilib] database"
fi
# makepkg (yay / AUR builds): all cores, no -debug split packages; enable x86-64-v3
# on T14s/P15 or any generic CPU that supports x86-64-v3 (avoid SIGILL on older CPUs).
mkdir -p /etc/makepkg.conf.d
if [[ ${HW_PROFILE:-t14s} != generic ]] || cpu_has_x86_64_v3; then
cat > /etc/makepkg.conf.d/t14s.conf <<'EOF'
# Local/AUR builds: Zen 3+ / x86-64-v3 capable CPU (AVX2/BMI2/FMA).
MAKEFLAGS="-j$(nproc)"
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug lto)
if [[ ${CFLAGS-} == *"-march=x86-64"* && ${CFLAGS-} != *"-march=x86-64-v"* ]]; then
  CFLAGS="${CFLAGS/-march=x86-64/-march=x86-64-v3}"
  CFLAGS="${CFLAGS/-mtune=generic /}"
fi
if [[ ${CXXFLAGS-} == *"-march=x86-64"* && ${CXXFLAGS-} != *"-march=x86-64-v"* ]]; then
  CXXFLAGS="${CXXFLAGS/-march=x86-64/-march=x86-64-v3}"
  CXXFLAGS="${CXXFLAGS/-mtune=generic /}"
fi
case "${RUSTFLAGS-} " in
  *" -C target-cpu="* | *" target-cpu="*) ;;
  *) RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C target-cpu=x86-64-v3" ;;
esac
GOAMD64="${GOAMD64:-v3}"
EOF
else
cat > /etc/makepkg.conf.d/t14s.conf <<'NONV3'
# Local/AUR builds: portable x86-64 (CPU lacks x86-64-v3).
MAKEFLAGS="-j$(nproc)"
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug lto)
NONV3
fi
# Weekly cache trim (keeps 3 versions; pacman-contrib is in the base set).
systemctl enable paccache.timer
