#!/bin/sh
# Install lethe: curl -fsSL https://raw.githubusercontent.com/C0sm0cats/lethe/main/install.sh | sh
#
# Downloads lethe to ~/.local/bin (or $LETHE_BIN), adds that directory to your
# PATH if needed, and tells you exactly how to install anything missing.
# LETHE_VERSION=v0.7.7 installs a given release instead of the latest code.
set -eu

bin=${LETHE_BIN:-$HOME/.local/bin}
ref=${LETHE_VERSION:-main}
url="https://raw.githubusercontent.com/C0sm0cats/lethe/$ref/lethe"

say() { printf '%s\n' "$*"; }

mkdir -p "$bin"
if ! curl -fsSL -o "$bin/lethe.tmp" "$url"; then
    rm -f "$bin/lethe.tmp"
    say "Could not download $url"
    exit 1
fi
chmod +x "$bin/lethe.tmp"
mv "$bin/lethe.tmp" "$bin/lethe"
say "✓ lethe installed in $bin/lethe"

# PATH: add the directory to the startup file of the user's shell.
case ":$PATH:" in
    *":$bin:"*) ;;
    *)
        shell=${SHELL:-}
        case ${shell##*/} in
            # zsh reads $ZDOTDIR/.zshrc; ZDOTDIR is often set in ~/.zshenv only.
            zsh) rc=$(zsh -c 'printf %s "${ZDOTDIR:-$HOME}"' 2>/dev/null || printf %s "${ZDOTDIR:-$HOME}")/.zshrc ;;
            bash) if [ "$(uname -s)" = Darwin ]; then rc=$HOME/.bash_profile; else rc=$HOME/.bashrc; fi ;;
            fish) rc="" ;;
            *) rc=$HOME/.profile ;;
        esac
        if [ -z "$rc" ]; then
            fish -c "fish_add_path $bin" 2>/dev/null || true
            say "✓ $bin added to your PATH (fish)"
        elif ! grep -qsF "export PATH=\"$bin:\$PATH\"" "$rc"; then
            # shellcheck disable=SC2016 # $PATH is written literally, for the shell to expand
            printf '\n# Added by the lethe installer\nexport PATH="%s:$PATH"\n' "$bin" >>"$rc"
            say "✓ $bin added to your PATH in $rc"
        fi
        say "  Open a new terminal (or run: export PATH=\"$bin:\$PATH\") to use lethe."
        ;;
esac

# Dependencies: bash 4.4+, fzf, jq, sqlite3; zstd reads the transcripts Codex compresses.
missing=""
for tool in fzf jq sqlite3; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
# Distributions can ship an fzf too old for the picker (Debian 12: 0.38).
fzf_old=""
if command -v fzf >/dev/null 2>&1; then
    fzf_minor=$(fzf --version 2>/dev/null </dev/null | sed -n 's/^0\.\([0-9]*\).*/\1/p')
    if [ -n "$fzf_minor" ] && [ "$fzf_minor" -lt 45 ]; then
        fzf_old=$(fzf --version 2>/dev/null </dev/null | cut -d ' ' -f 1)
        missing="$missing fzf-0.45+"
    fi
fi
bash_ok=$(bash -c 'if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))); then echo yes; fi' 2>/dev/null || true)
if [ -n "$missing" ] || [ "$bash_ok" != yes ]; then
    say ""
    say "lethe also needs:$missing$([ "$bash_ok" = yes ] || printf ' bash 4.4+')"
    if [ "$(uname -s)" = Darwin ]; then
        if command -v brew >/dev/null 2>&1; then
            say "  brew install bash fzf jq sqlite zstd"
        else
            say "  Install Homebrew first (https://brew.sh), then: brew install bash fzf jq sqlite zstd"
        fi
    elif command -v apt-get >/dev/null 2>&1; then
        say "  sudo apt install fzf jq sqlite3 zstd"
    elif command -v dnf >/dev/null 2>&1; then
        say "  sudo dnf install fzf jq sqlite zstd"
    elif command -v pacman >/dev/null 2>&1; then
        say "  sudo pacman -S fzf jq sqlite zstd"
    elif command -v zypper >/dev/null 2>&1; then
        say "  sudo zypper install fzf jq sqlite3 zstd"
    elif command -v apk >/dev/null 2>&1; then
        say "  sudo apk add bash fzf jq sqlite zstd"
    else
        say "  Install them with your package manager."
    fi
    if [ -n "$fzf_old" ]; then
        say "  Your fzf is $fzf_old and the picker needs 0.45+. If your package manager has nothing newer:"
        say "  https://github.com/junegunn/fzf/releases (lethe list, delete and the others work without it)"
    fi
    say "Then run: lethe"
else
    say "✓ fzf, jq, sqlite3 and bash 4.4+ found. Run: lethe"
fi
if ! command -v zstd >/dev/null 2>&1; then
    say "  Optional: zstd, to read the old transcripts that Codex compresses (same package manager)."
fi
