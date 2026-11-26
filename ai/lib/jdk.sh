#!/usr/bin/env bash
# Shared JDK >= 21 discovery for Ghidra / REA / coding agents.
# Avoids Android's JAVA_HOME=17 by scanning /usr/lib/jvm/java-*-openjdk with javac.
# shellcheck shell=bash

pick_jdk21() {
  local jvm_root="${JDK_JVM_DIR:-/usr/lib/jvm}"
  local best="" best_ver=0 cand ver
  shopt -s nullglob
  for cand in "$jvm_root"/java-*-openjdk; do
    [[ -x "$cand/bin/javac" ]] || continue
    ver="${cand##*/java-}"
    ver="${ver%%-*}"
    [[ "$ver" =~ ^[0-9]+$ ]] || continue
    (( ver >= 21 )) || continue
    if (( ver > best_ver )); then
      best=$cand
      best_ver=$ver
    fi
  done
  shopt -u nullglob
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}
