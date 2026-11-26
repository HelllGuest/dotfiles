---
name: ghidra-cli-host
description: >
  Arch/dotfiles host wiring for akiselev ghidra-cli. Use with ghidra-cli skill
  when running reverse engineering on this machine: paths, JDK, GUI alias,
  unreliable exit codes, import program naming.
---

# ghidra-cli host notes (this machine)

## Binaries

* CLI: `~/.cargo/bin/ghidra` (first on PATH; shadows Arch `/usr/bin/ghidra`)
* GUI: `ghidra-gui` alias → `/opt/ghidra/ghidraRun`
* Install/reinstall: `bash ~/dotfiles/ai/scripts/install-ghidra-cli.sh` (builds v0.2.2 from a pinned commit,
  patched for Ghidra 12.2: `DataTypeManager.remove(DataType, TaskMonitor)` was removed upstream in Ghidra;
  without the patch every command fails with "GhidraCliBridge not found")

## Env / config

* `GHIDRA_INSTALL_DIR=/opt/ghidra`
* `GHIDRA_CLI_JAVA_HOME` = newest `/usr/lib/jvm/java-*-openjdk` with `javac` and version ≥ 21
* Config file: `~/.config/ghidra-cli/config.yaml`
* Do **not** run `ghidra config set java_home` (upstream rejects the key). Install script upserts only `ghidra_install_dir` and `java_home`; other keys kept.
* Never set `ghidra_install_dir` to a JDK path.

## Agent footguns

1. **Exit codes are unreliable.** Logical failures often still exit 0. Prefer `--json` and check `"status":"success"`, or grep stderr for `Error:`.
2. **Import program name is basename.** `ghidra import /path/to/foo --program bar` still stores program as `foo` (or copy name). After import, `ghidra program list --project P` then use that name.
3. **Android sets `JAVA_HOME` to 17.** Rely on `GHIDRA_CLI_JAVA_HOME` / config `java_home`, not `JAVA_HOME`.
4. Projects live under `~/ghidra-cli-projects` (Ghidra 12.1+ rejects `~/.cache/...`).

## Minimal verify

```bash
ghidra doctor
ghidra import /usr/bin/true --project smoke --no-analyze
ghidra program list --project smoke
ghidra project delete smoke
```
