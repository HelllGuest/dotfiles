#!/usr/bin/env bash
# tui-pty.test.sh — real PTY tests for dialog/whiptail/plain TUIs (Stage B + Stage A).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not installed"; echo "PASS: tui-pty.test.sh"; exit 0; }

python3 - "$ROOT" <<'PY'
import fcntl, os, pty, select, shutil, struct, subprocess, sys, tempfile, termios, time

ROOT = sys.argv[1]

def run_pty(cmd, steps, env=None, rows=24, cols=80, timeout=20):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    e = os.environ.copy()
    e["TERM"] = "xterm-256color"
    e["LINES"] = str(rows)
    e["COLUMNS"] = str(cols)
    e["ESCDELAY"] = "25"
    if env:
        e.update(env)
    proc = subprocess.Popen(
        cmd, stdin=slave, stdout=slave, stderr=slave,
        cwd=ROOT, env=e, preexec_fn=os.setsid, close_fds=True
    )
    os.close(slave)
    out = bytearray()

    def drain(max_wait, wait_for_data=False, quiet_after=0.15):
        end = time.time() + max_wait
        got_data = False
        last_rx = time.time()
        while time.time() < end:
            if proc.poll() is not None:
                break
            rem = end - time.time()
            r, _, _ = select.select([master], [], [], min(0.05, max(0, rem)))
            if r:
                try:
                    chunk = os.read(master, 4096)
                    if not chunk:
                        break
                    out.extend(chunk)
                    got_data = True
                    last_rx = time.time()
                except OSError:
                    break
            elif wait_for_data and got_data and (time.time() - last_rx) >= quiet_after:
                break

    for delay, payload in steps:
        # Wait for the TUI screen to paint (up to max(delay, 3.0)s), then settle briefly.
        drain(max(delay, 3.0), wait_for_data=True, quiet_after=0.15)
        if proc.poll() is None and payload:
            os.write(master, payload)
    deadline = time.time() + timeout
    while proc.poll() is None and time.time() < deadline:
        drain(0.1)
    if proc.poll() is None:
        proc.kill()
        os.close(master)
        return -999, out.decode("utf-8", "replace")
    drain(0.1)
    os.close(master)
    return proc.returncode, out.decode("utf-8", "replace")

failures = []
def check(name, cond, detail=""):
    if cond:
        print(f"ok {name}")
    else:
        print(f"FAIL: {name} :: {detail}", file=sys.stderr)
        failures.append(name)

# 1. Plain PTY tests (always run)
rc, out = run_pty(["bash", "./install.sh", "--plain"], [(0.35, b"8\r")])
check("install.sh --plain PTY quit", rc == 0 and "Installation cancelled." in out, f"rc={rc}")

rc, out = run_pty(["bash", "provision/scripts/configure.sh", "--plain"], [(0.35, b"3\r")])
check("configure.sh --plain PTY quit", rc == 0 and "configure.sh finished" in out, f"rc={rc}")

rc, out = run_pty(
    ["bash", "desktop/scripts/theme-packs.sh", "--plain", "--dry-run"],
    [(0.3, b"4\r"), (0.3, b"6\r")],
)
check("theme-packs.sh --plain PTY status+quit", rc == 0 and "Installed packs:" in out, f"rc={rc}")

# 2. Real whiptail / dialog PTY tests (whichever binaries exist; Ubuntu CI has both)
for backend in ("whiptail", "dialog"):
    if not shutil.which(backend):
        print(f"SKIP: {backend} not installed")
        continue
    cancel_keys = b"\x1b" if backend == "dialog" else b"\t\t\r"

    rc, out = run_pty(
        ["bash", "-euo", "pipefail", "-c", f"""
source provision/lib/ui-menu.sh
ui_init {backend} "PTY Test" TEST_UI
trap ui_theme_cleanup EXIT
ui_theme_init
DEFAULT_MENU_ITEM=second
m="$(ui_menu 'Pick one' first 'First' second 'Second' third 'Third')"
c="$(ui_checklist 'Boxes' A 'Alpha' on B 'Beta' off C 'Gamma' on)"
ui_msg "Done"
printf 'RES=<%s|%s>\\n' "$m" "$(printf '%s' "$c" | tr '\\n' ',')"
"""],
        [(0.4, b"\r"), (0.4, b"\r"), (0.4, b"\r")],
    )
    check(f"ui-menu.sh {backend} PTY (menu+checklist+msg)",
          rc == 0 and "RES=<second|A,C>" in out, f"rc={rc} tail={out[-250:]!r}")

    rc, out = run_pty(
        ["bash", "-euo", "pipefail", "-c", f"""
source provision/lib/ui-menu.sh
ui_init {backend} "PTY Cancel" TEST_UI
trap ui_theme_cleanup EXIT
ui_theme_init
if ui_menu 'Cancel' a 'Alpha' b 'Beta'; then echo 'UNEXPECTED_OK'; else echo 'CANCELLED_OK'; fi
"""],
        [(0.4, cancel_keys)],
    )
    check(f"ui-menu.sh {backend} PTY cancel", rc == 0 and "CANCELLED_OK" in out, f"rc={rc} tail={out[-250:]!r}")

    rc, out = run_pty(
        ["bash", "./install.sh"],
        [(0.5, cancel_keys)],
        env={"INSTALL_UI": backend},
    )
    check(f"install.sh {backend} PTY quit", rc == 0 and "Installation cancelled." in out, f"rc={rc} tail={out[-250:]!r}")

    # Exercise install.sh menu options in a temp stub repo (custom Cancel, check without sudo, configure handoff).
    with tempfile.TemporaryDirectory(prefix="tui-menu-") as _tmp:
        for _d in ("provision/lib", "provision/scripts", "scripts", "bin"):
            os.makedirs(os.path.join(_tmp, _d), exist_ok=True)
        for _f in ("install.sh", "provision/lib/ui-menu.sh", "provision/lib/progress.sh",
                   "provision/lib/dmi.sh", "provision/scripts/configure.sh"):
            shutil.copy(os.path.join(ROOT, _f), os.path.join(_tmp, _f))
        _ran = os.path.join(_tmp, "ran")
        for _s, _t in (("scripts/check.sh", "check"), ("scripts/validate-configs.sh", "validate")):
            _p = os.path.join(_tmp, _s)
            open(_p, "w").write(f"#!/usr/bin/env bash\necho '{_t}' >> '{_ran}'\n")
            os.chmod(_p, 0o755)
        _sp = os.path.join(_tmp, "bin/sudo")
        open(_sp, "w").write(f"#!/usr/bin/env bash\necho SUDO >> '{_ran}'; exit 99\n")
        os.chmod(_sp, 0o755)
        _env = {"INSTALL_UI": backend, "PATH": f"{_tmp}/bin:{os.environ['PATH']}"}
        # custom (Enter) -> Cancel -> returns to menu -> quit (7 downs + Enter)
        rc, out = run_pty(["bash", os.path.join(_tmp, "install.sh")],
                          [(0.4, b"\r"), (0.4, cancel_keys), (0.4, b"\x1b[B"*7 + b"\r")], env=_env)
        check(f"install.sh {backend} PTY custom-cancel+quit",
              rc == 0 and "Installation cancelled." in out and not os.path.exists(_ran), f"rc={rc}")
        # custom -> uncheck all 13 default items -> "No sections selected." -> Enter -> quit
        _uncheck_all = b"".join((b" " if i != 11 else b"") + (b"\x1b[B" if i < 13 else b"") for i in range(14)) + b"\r"
        rc, out = run_pty(["bash", os.path.join(_tmp, "install.sh")],
                          [(0.4, b"\r"), (0.4, _uncheck_all), (0.4, b"\r"), (0.4, b"\x1b[B"*7 + b"\r")],
                          rows=28, cols=110, env=_env)
        check(f"install.sh {backend} PTY custom-empty+quit",
              rc == 0 and "No sections selected." in out and "Installation cancelled." in out and not os.path.exists(_ran),
              f"rc={rc}")
        # custom -> uncheck first 12 defaults, leave ONLY check (item 13) -> runs check+validate, no sudo
        _only_check = b"".join((b" " if i != 11 else b"") + b"\x1b[B" for i in range(13)) + b"\r"
        rc, out = run_pty(["bash", os.path.join(_tmp, "install.sh")],
                          [(0.4, b"\r"), (0.4, _only_check)], rows=28, cols=110, env=_env)
        _got = open(_ran).read().splitlines() if os.path.exists(_ran) else []
        check(f"install.sh {backend} PTY custom-only-check (no sudo)",
              rc == 0 and _got == ["check", "validate"], f"rc={rc} ran={_got}")
        if os.path.exists(_ran): os.unlink(_ran)
        # check (6 downs + Enter) -> runs check+validate, never calls sudo
        rc, out = run_pty(["bash", os.path.join(_tmp, "install.sh")],
                          [(0.4, b"\x1b[B"*6 + b"\r")], env=_env)
        _got = open(_ran).read().splitlines() if os.path.exists(_ran) else []
        check(f"install.sh {backend} PTY check (no sudo)",
              rc == 0 and _got == ["check", "validate"], f"rc={rc} ran={_got}")
        # configure (5 downs + Enter) -> opens configure.sh -> Cancel/Quit
        rc, out = run_pty(["bash", os.path.join(_tmp, "install.sh")],
                          [(0.4, b"\x1b[B"*5 + b"\r"), (0.5, cancel_keys)], env=_env)
        check(f"install.sh {backend} PTY configure handoff",
              rc == 0 and "configure.sh finished" in out, f"rc={rc} tail={out[-200:]!r}")

    rc, out = run_pty(
        ["bash", "provision/scripts/configure.sh"],
        [(0.5, cancel_keys)],
        env={"CONFIGURE_UI": backend},
    )
    check(f"configure.sh {backend} PTY quit", rc == 0 and "configure.sh finished" in out, f"rc={rc} tail={out[-250:]!r}")

    # Stage A TUI screens + gauge in 80x24 PTY
    scroll_keys = b"\t\r" if backend == "whiptail" else b"\r"
    rc, out = run_pty(
        ["bash", "-euo", "pipefail", "-c", f"""
cd stage-a
APP_TITLE="Stage A PTY"
DIALOG_RC="" TUI_TITLE="" TUI_NEWT="" TUI_DIALOGRC=""
TUI_HINT_MENU="Up/Down" TUI_HINT_RADIO="Space" TUI_HINT_CHECK="Space"
LOGGING=0 T14S_DIED=0
source lib/00-common.sh
source lib/10-ui.sh
source lib/11-ui-theme.sh
source lib/12-ui-screens.sh
source lib/13-ui-progress.sh
LOG="$(mktemp /tmp/stagea-pty.XXXXXX.log)"
trap 'rm -f "$LOG"; cleanup_ui' EXIT
UI={backend}; NONINTERACTIVE=0; TUI_STEPS=11
ui_step 2 "Test"
write_dialogrc
ui_info "Short info"
big=$(printf 'line %02d\\n' $(seq 1 30))
ui_info "$big"
yes_rc=0; ui_yesno "Yes?" yes || yes_rc=$?
no_rc=0; ui_yesno "Erase?" no erase || no_rc=$?
inp=$(ui_input "Host" "archbox")
m=$(ui_menu "Pick" a "Alpha" b "Beta")
chk=$(ui_checklist "Extras" x "X" on y "Y" off)
run_gauge "Gauge" 0 100 bash -c 'echo "::STAGE 1/1::Done"; sleep 0.1'
printf 'SA=<%d|%d|%s|%s|%s>\\n' "$yes_rc" "$no_rc" "$inp" "$m" "$(printf '%s' "$chk" | tr '\\n' ',')"
"""],
        [
            (0.35, b"\r"),          # ui_info
            (0.35, scroll_keys),    # overflowing ui_info
            (0.35, b"\r"),          # ui_yesno yes -> 0
            (0.35, b"\r"),          # ui_yesno no (defaultno) -> 1
            (0.35, b"\r"),          # ui_input default
            (0.35, b"\x1b[B\r"),    # ui_menu Down -> b
            (0.35, b"\r"),          # ui_checklist default x
        ],
        rows=24, cols=80,
    )
    check(f"stage-a TUI {backend} PTY 80x24 (screens+scrolltext+gauge)",
          rc == 0 and "SA=<0|1|archbox|b|x>" in out, f"rc={rc} tail={out[-300:]!r}")

sys.exit(1 if failures else 0)
PY

echo "PASS: tui-pty.test.sh"
