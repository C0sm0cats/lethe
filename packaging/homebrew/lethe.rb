# Homebrew formula, for a tap: copy to Formula/lethe.rb in a repository named
# homebrew-tap, then `brew install c0sm0cats/tap/lethe`. On a new release,
# update url and sha256 (curl -fsSL <url> | shasum -a 256).
class Lethe < Formula
  desc "Browse, resume and forget your Claude Code and Codex sessions"
  homepage "https://github.com/C0sm0cats/lethe"
  url "https://github.com/C0sm0cats/lethe/archive/refs/tags/v0.7.3.tar.gz"
  sha256 "cd38b98101b09967a7d504f519a6d253d741ca2df2e13b28a12d4a83ecde8caf"
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
