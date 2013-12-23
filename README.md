BTScoreboard-iOS
================

iOS scoreboard app with support for Bluetooth key fobs (e.g. TI Sensor Tag or TI Key Fob) for updating scores.
The app has had limited testing and has several known shortcomings.

Operation:
----------------
After launching the app, it will search for a BLE device with the name "TI BLE Sensor Tag" or "TI BLE Keyfob" (these devices do not advertise services).  These tags can be purchased through Texas Instruments or their resellers for about $25.  The app will initially scan for 10 seconds.  If no device is found, scanning stops and must be restarted by pressing the connection indicator (blue circle) in the top left of the screen.

Once a BLE device is found, the two keys can be used to:
- Increase Home Score: left key "click"
- Increase Visitor Score: right key "click"
- Start/Stop Timer: multi-key "click"

A key "click" is the act of depressing and releasing a key(s) in less than 1/2 second (hard coded).

Each operation can also be performed on the iOS device touchscreen by tapping the specific item (score or time).
