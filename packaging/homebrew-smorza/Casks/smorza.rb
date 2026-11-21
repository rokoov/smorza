cask "smorza" do
  version "0.4.0"
  sha256 "REPLACE_WITH_SHA256_OF_THE_DMG"

  url "https://github.com/rokoov/smorza/releases/download/v#{version}/Smorza-#{version}.dmg"
  name "Smorza"
  desc "Per-app volume, mute and output device from the menu bar"
  homepage "https://smorza.app/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Smorza updates itself with Sparkle.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Smorza.app"

  uninstall quit: "com.rokoov.smorza"

  zap trash: [
    "~/Library/Caches/com.rokoov.smorza",
    "~/Library/HTTPStorages/com.rokoov.smorza",
    "~/Library/Preferences/com.rokoov.smorza.plist",
  ]

  caveats <<~EOS
    Smorza is not notarized by Apple, so its first launch needs one extra step.
    macOS 15 and later: open Smorza once and close the warning, then go to
    System Settings > Privacy & Security and click Open Anyway.
    macOS 14: right-click Smorza in Applications, choose Open, then Open again.
  EOS
end
