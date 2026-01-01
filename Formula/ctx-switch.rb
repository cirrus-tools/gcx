# typed: false
# frozen_string_literal: true

class CtxSwitch < Formula
  desc "Quick context switcher for Google Cloud Platform"
  homepage "https://github.com/changename/ctx-switch"
  url "https://github.com/changename/ctx-switch/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"
  head "https://github.com/changename/ctx-switch.git", branch: "main"

  depends_on "yq"
  depends_on "gum"

  def install
    bin.install "bin/ctx-switch.sh" => "ctx-switch"
    bin.install "bin/ctx-switch-setup.sh" => "ctx-switch-setup"
  end

  def caveats
    <<~EOS
      To get started, run:
        ctx-switch-setup

      Dependencies (install separately if needed):
        brew install --cask google-cloud-sdk
        brew install kubectl
    EOS
  end

  test do
    assert_match "ctx-switch", shell_output("#{bin}/ctx-switch --help")
  end
end
