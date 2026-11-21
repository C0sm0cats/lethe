# Homebrew formula, for a tap: copy to Formula/lethe.rb in a repository named
# homebrew-tap, then `brew install c0sm0cats/tap/lethe`. On a new release,
# update url and sha256 (curl -fsSL <url> | shasum -a 256).
class Lethe < Formula
  desc "Browse, resume and forget your Claude Code and Codex sessions"
  homepage "https://github.com/C0sm0cats/lethe"
  url "https://github.com/C0sm0cats/lethe/archive/refs/tags/v0.8.3.tar.gz"
  sha256 "af563e876f5e8bbdd34d9e247cd6db593028d0a430f0d5f7bb69d1e714e540d8"
  license "MIT"

  depends_on "bash"
  depends_on "fzf"
  depends_on "jq"
  depends_on "sqlite"
  depends_on "zstd"

  def install
    bin.install "lethe"
    (bash_completion/"lethe").write Utils.safe_popen_read(bin/"lethe", "completion", "bash")
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lethe --version")
  end
end
