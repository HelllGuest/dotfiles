#!/usr/bin/env bash
# lab-re entry — verify RE backends; never touches host JDK/Ghidra.
set -euo pipefail

if [[ -z "${JAVA_HOME:-}" || ! -x "${JAVA_HOME}/bin/javac" ]]; then
  for cand in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-*-openjdk; do
    if [[ -x "${cand}/bin/javac" ]]; then
      export JAVA_HOME=$cand
      break
    fi
  done
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${PATH}"

if [[ ! -d "${GHIDRA_INSTALL_DIR:-}" ]]; then
  for d in /opt/ghidra /usr/lib/ghidra /usr/share/ghidra; do
    if [[ -d $d ]]; then
      export GHIDRA_INSTALL_DIR=$d
      break
    fi
  done
fi
# Arch package ships /opt/ghidra/ghidraRun + /usr/bin/ghidra wrapper.
if [[ -x "${GHIDRA_INSTALL_DIR:-}/ghidraRun" ]]; then
  export PATH="${GHIDRA_INSTALL_DIR}:${PATH}"
fi

if [[ "${1:-}" == "--check" ]]; then
  echo "JAVA_HOME=${JAVA_HOME:-missing}"
  java -version 2>&1 | head -1 || true
  echo "GHIDRA_INSTALL_DIR=${GHIDRA_INSTALL_DIR:-missing}"
  if [[ -x "${GHIDRA_INSTALL_DIR:-}/ghidraRun" ]]; then
    echo "ghidra: ${GHIDRA_INSTALL_DIR}/ghidraRun"
  elif command -v ghidra >/dev/null; then
    echo "ghidra: $(command -v ghidra)"
  else
    echo "ghidra: missing"
  fi
  command -v rizin >/dev/null && echo "rizin: $(rizin -v 2>&1 | head -1)" || echo "rizin: missing"
  command -v jadx >/dev/null && echo "jadx: $(jadx --version 2>&1 | head -1)" || echo "jadx: missing"
  if command -v rea >/dev/null; then
    echo "rea: $(rea --version 2>&1 | head -1)"
  else
    npm ls -g rea-agents 2>/dev/null | head -3 || echo "rea-agents: missing"
  fi
  exit 0
fi


exec "$@"
