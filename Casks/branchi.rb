cask "branchi" do
  # version and sha256 are updated by the release workflow.
  version "0.7.4"
  sha256 "a9d72288603eb14fa15e7f95aad997b6a9e28c6df6bcc5760f5bc424946e9635"

  url "https://github.com/mbpcoder/Branchi/releases/download/v#{version}/branchi-macos.dmg"
  name "Branchi"
  desc "Git client with a Rust core and a Flutter UI"
  homepage "https://github.com/mbpcoder/Branchi"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :catalina"

  app "Branchi.app"

  zap trash: [
    "~/Library/Application Support/com.mbpcoder.branchi",
    "~/Library/Logs/Branchi",
    "~/Library/Preferences/com.mbpcoder.branchi.plist",
    "~/Library/Saved Application State/com.mbpcoder.branchi.savedState",
  ]

  caveats <<~EOS
    Branchi is not signed with an Apple Developer ID yet, so macOS blocks
    the first launch. To allow it, run:
      xattr -dr com.apple.quarantine "#{appdir}/Branchi.app"
  EOS
end
