#!/usr/bin/env bash
# Shared QEMU / OVMF helpers for Stage A and Stage B VM rehearsal harnesses.
# shellcheck shell=bash

# Populate OVMF_CODE and OVMF_VARS_SRC from standard Arch/Debian edk2 locations.
vm_find_ovmf() {
  local c
  OVMF_CODE=""
  OVMF_VARS_SRC=""
  for c in \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.4m.fd \
    /usr/share/OVMF/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd
  do
    if [[ -f $c && -f ${c/CODE/VARS} ]]; then
      # shellcheck disable=SC2034 # consumed by sourcing callers
      OVMF_CODE="$c"
      # shellcheck disable=SC2034 # consumed by sourcing callers
      OVMF_VARS_SRC="${c/CODE/VARS}"
      return 0
    fi
  done
  return 1
}
