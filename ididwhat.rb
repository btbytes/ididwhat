class IDidWhat < Formula
  desc "Personal Activity Tracker for macOS"
  homepage "https://github.com/btbytes/ididwhat"
  url "https://github.com/btbytes/ididwhat/archive/v0.1.0.tar.gz"
  sha256 "replace_with_actual_sha256_after_release"
  license "MIT"

  depends_on "nim"
  depends_on "sqlite3"

  def install
    system "nimble", "build", "--accept"
    bin.install "ididwhat"
  end

  test do
    system "#{bin}/ididwhat", "--version"
  end
end
