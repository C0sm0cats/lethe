# Homebrew formula, for a tap: copy to Formula/lethe.rb in a repository named
# homebrew-tap, then `brew install c0sm0cats/tap/lethe`. On a new release,
# update url and sha256 (curl -fsSL <url> | shasum -a 256).
class Lethe < Formula
  desc "Browse, resume and forget your Claude Code and Codex sessions"
  homepage "https://github.com/C0sm0cats/lethe"
  url "https://github.com/C0sm0cats/lethe/archive/refs/tags/v0.8.1.tar.gz"
  sha256 "d197992ba8753cc327c9362ff60aa13f901c40bfd707fd8a955a7c017d97ca8e"
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
