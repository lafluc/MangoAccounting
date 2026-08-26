# Building and distributing MangoAccounting

The app is a macOS `.app` handed directly to users, who replace their copy in
place. Their data survives because it lives in the sandbox container keyed by the
bundle identifier — so **never change `PRODUCT_BUNDLE_IDENTIFIER`**
(`bingbangbongVibeCoding.MangoAccounting`). Changing it would orphan every user's
ledger.

## Build

```
./distribution/build-release.sh
```

Picks the best signing you have installed and writes
`build/export/MangoAccounting.app`, as a universal x86_64 + arm64 binary.

## Signing: the two options

| | Developer ID + notarised | Apple Development |
|---|---|---|
| Needs | paid Apple Developer Program | free Apple ID |
| First launch | opens on a double click | Gatekeeper blocks it; user must right-click → Open |
| What has shipped so far | — | this one |

If `security find-identity -v -p codesigning` lists nothing, open
**Xcode → Settings → Accounts**, add your Apple ID, and let Xcode create a
certificate.

## Notarising (Developer ID only)

Store the credential once, so no secret ever appears on a command line:

```
xcrun notarytool store-credentials MangoNotary --apple-id <your-apple-id> --team-id LUR83WQX7W
```

That prompts for an app-specific password, created at appleid.apple.com. Then per
release:

```
ditto -c -k --keepParent build/export/MangoAccounting.app build/MangoAccounting.zip
xcrun notarytool submit build/MangoAccounting.zip --keychain-profile MangoNotary --wait
xcrun stapler staple build/export/MangoAccounting.app
spctl -a -vvv --type execute build/export/MangoAccounting.app
```

The last command should report `accepted`. Send the zip, not the raw `.app`, so
the signature survives the transfer.

## Version numbers

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project for every
release. They sat at `1.0` / `1` across builds, which made a new build
indistinguishable from the old one.

## Before shipping an update

```
xcodebuild test -project MangoAccounting.xcodeproj -scheme MangoAccounting -destination 'platform=macOS,arch=arm64'
```

The suite includes a test that writes a database with the *shipped* data model and
reopens it with the current one, which is the guarantee that an update does not
cost anyone their records. Take that failing as a blocker.
