tell application "Finder"
    tell disk "Azathoth's Whisper"
        open
        delay 1
        set targetWindow to container window
        tell targetWindow
            set current view to icon view
            set the bounds to {100, 100, 800, 520}
            set viewOptions to the icon view options of it
        end tell
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 160
        delay 1
        set bgPath to file "dmg_background.png"
        set background picture of viewOptions to bgPath
        set position of item "Azathoth's Whisper.app" of targetWindow to {170, 230}
        set position of item "Applications" of targetWindow to {520, 230}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
