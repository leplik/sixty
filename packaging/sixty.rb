cask "sixty" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/leplik/sixty/releases/download/v#{version}/Sixty-#{version}.dmg"
  name "Sixty"
  desc "Locks the screen for a 60-second stand-up break every hour, but never in a call"
  homepage "https://leplik.github.io/sixty/"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Sixty.app"

  uninstall launchctl: "pro.saac.sixty.agent",
            quit:      "pro.saac.sixty"

  zap trash: [
    "~/Library/Application Support/Sixty",
    "~/Library/Preferences/pro.saac.sixty.plist",
  ]
end
