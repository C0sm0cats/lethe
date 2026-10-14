#!/bin/sh
# Install lethe: curl -fsSL https://raw.githubusercontent.com/C0sm0cats/lethe/main/install.sh | sh
#
# Downloads lethe to ~/.local/bin (or $LETHE_BIN), adds that directory to your
# PATH if needed, and tells you exactly how to install anything missing.
# LETHE_VERSION=v0.6.1 installs a given release instead of the latest code.
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
        case ${SHELL##*/} in
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

# Dependencies: bash 4.4+, fzf, jq, sqlite3.
missing=""
for tool in fzf jq sqlite3; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
bash_ok=$(bash -c 'if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))); then echo yes; fi' 2>/dev/null || true)
if [ -n "$missing" ] || [ "$bash_ok" != yes ]; then
    say ""
    say "lethe also needs:$missing$([ "$bash_ok" = yes ] || printf ' bash 4.4+')"
    if [ "$(uname -s)" = Darwin ]; then
        if command -v brew >/dev/null 2>&1; then
            say "  brew install bash fzf jq sqlite"
        else
            say "  Install Homebrew first (https://brew.sh), then: brew install bash fzf jq sqlite"
        fi
    elif command -v apt-get >/dev/null 2>&1; then
        say "  sudo apt install fzf jq sqlite3"
    elif command -v dnf >/dev/null 2>&1; then
        say "  sudo dnf install fzf jq sqlite"
    elif command -v pacman >/dev/null 2>&1; then
        say "  sudo pacman -S fzf jq sqlite"
    elif command -v zypper >/dev/null 2>&1; then
        say "  sudo zypper install fzf jq sqlite3"
    elif command -v apk >/dev/null 2>&1; then
        say "  sudo apk add bash fzf jq sqlite"
    else
        say "  Install them with your package manager."
    fi
    say "Then run: lethe"
else
    say "✓ fzf, jq, sqlite3 and bash 4.4+ found. Run: lethe"
fi
