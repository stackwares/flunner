cask "flunner" do
  version "1.0.0"
  sha256 "d94029751ea7e1084c8a408e2b5278354c8dfb46318520a3c92521c3a1324d2c"

  url "https://github.com/stackwares/flunner/releases/download/v#{version}/Flunner.dmg"
  name "Flunner"
  desc "Native Flutter workbench with in-app MCP for AI agents"
  homepage "https://github.com/stackwares/flunner"

  depends_on macos: :sequoia

  app "Flunner.app"

  zap trash: [
    "~/Library/Application Support/Flunner",
    "~/Library/Caches/com.flunner.app",
    "~/Library/Preferences/com.flunner.app.plist",
    "~/Library/Saved Application State/com.flunner.app.savedState",
  ]
end
