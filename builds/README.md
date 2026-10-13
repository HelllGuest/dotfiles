# builds/

Optional local package sources. Not installed by `./install.sh`.

| Tree | Builder | Notes |
|------|---------|--------|
| `st/` | `scripts/build-st.sh` | Riced suckless st (PKGBUILD + patches). `src/`, `pkg/`, and `*.pkg.tar.zst` are gitignored. |

Keep each package self-contained under `builds/<name>/`.
