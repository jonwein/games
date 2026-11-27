# Daily Games for iOS

A native SwiftUI version of the web page in `../index.html`. It has the same list, matching, and combined message, but games open inside the app. When a game shares or copies its result, the app catches it, closes the game, and adds the result, so there's nothing to copy and paste. Paste is still there for games played somewhere else.

## Run it

1. `open ios/DailyGames.xcodeproj` (Xcode 26).
2. Pick your iPhone as the destination and press Run. The team is set to 9S7P8G455A in `project.yml`, and the bundle ID is `com.jonwein.dailygames`.

It runs on iOS 17 and later, iPhone only, in portrait.

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or moving files, run `xcodegen generate` in `ios/`.

## How it's put together

- `DailyGames/Model/Matching.swift` is a function-for-function port of the matching in `index.html`: which game a result is from, guessing a new game's name and link, and stripping links for the message. `JS.swift` reproduces the bits of JavaScript regex and URL behavior that logic relies on.
- `DailyGames/Model/Store.swift` holds the list and today's results, the equivalent of `handleText`, `add`, `addNew` and friends. Everything is saved in UserDefaults on the device, separately from the website's list.
- `DailyGames/Views/GameBrowser.swift` is the in-app browser. `Resources/Capture.js` runs in every game page before the game's own scripts. It hooks `navigator.share`, `navigator.clipboard` and `document.execCommand("copy")`, and passes what the game shares or copies back to the app. A share that doesn't look like a result (no number or emoji) goes to the normal share sheet.
- `DailyGames/Views/ContentView.swift` is the main list, Edit mode, and the Paste/Send bar. Paste uses the system paste control, so iOS doesn't ask "Allow Paste?" each time.

## Keeping the matching in step with the web version

The matching logic now lives in two places. To check they still agree after changing `index.html`:

```sh
node ios/Tools/make_fixtures.mjs     # runs the web version's matching over sample results
swift test --package-path ios        # checks the Swift port gives the same answers (no simulator needed)
```

`make_fixtures.mjs` writes `DailyGamesTests/Fixtures/parity.json`. ParityTests fails on any sample result the two versions read differently. To cover a new case, add a sample to `TEXTS` or `scenarios` in the script.

## Tests

- `swift test --package-path ios` runs the model tests (ParityTests, StoreTests) on the Mac in a second or two.
- ⌘U in Xcode runs those plus CaptureTests, which loads pages in a real web view and checks each way of sharing and copying is caught, and PlayFlowTests, a UI test that taps a game, taps Share in it, and checks the result lands on the list.

In Debug builds, a few launch environment variables help tests and screenshots: `DAILYGAMES_TEST_GAMES` (a JSON game list to start from, kept apart from the real one), `DAILYGAMES_TEST_OPEN` (a game ID to open at launch), and `DAILYGAMES_TEST_EDIT` (start in Edit).

`swift ios/Tools/make_icon.swift <path>` redraws the app icon from the touch icon's design.
