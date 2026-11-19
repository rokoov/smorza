# Releasing

How a Volume Mixer release is signed, notarized and published, and how the app finds out about it.

## How it fits together

- `scripts/release.sh` builds the universal app, signs it and zips it. With `SIGN_IDENTITY` it signs with a
  Developer ID certificate and the hardened runtime; with `NOTARY_PROFILE` as well, Apple notarizes it and the
  ticket is stapled to the app, so a downloaded copy opens with no Gatekeeper warning.
- The app checks `https://rokoov.github.io/volume-mixer/appcast.xml` once a day (Sparkle). GitHub Pages serves
  that file from `docs/` on `main`, so a release reaches users when its release PR is merged. Keeping the feed in
  `docs/` rather than on a `gh-pages` branch means it changes in the same PR as the version it announces, and the
  feed can never announce a version `main` does not have. `docs/.nojekyll` makes Pages serve the folder as plain
  files, with no Jekyll build that could fail and hold the feed back.
- `scripts/appcast.sh` signs the release zip with the Sparkle EdDSA key and adds it to `docs/appcast.xml`. The
  app only installs an update whose signature matches the public key in its `Info.plist`.

No entitlements file: process taps are allowed by the System Audio Recording permission
(`NSAudioCaptureUsageDescription`), not by a hardened runtime entitlement. A hardened runtime build was checked on
macOS 27: the capture check passed and a turned-down app was heard through its route. The app never opens the
microphone, so it does not ask for `com.apple.security.device.audio-input` either.

Sparkle.framework is re-signed with the same certificate as the app, so the hardened runtime's library validation
accepts it. Ad hoc builds leave the hardened runtime off for that reason.

## One-time setup

1. **Apple Developer Program.** Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/)
   (99 USD a year). An individual membership is enough.
2. **Developer ID Application certificate.** In Xcode: Settings → Accounts → your team → Manage Certificates →
   **+** → Developer ID Application. Only the account holder can create one. Check that it is there:

   ```sh
   security find-identity -v -p codesigning
   # 1) 0123…  "Developer ID Application: Your Name (TEAMID1234)"
   ```

   Export it with its private key from Keychain Access (a `.p12` with a password) and keep that copy somewhere
   safe, off this Mac.
3. **Notary credentials.** Create an app-specific password at [account.apple.com](https://account.apple.com)
   (Sign-In and Security → App-Specific Passwords), then save it in the keychain under a profile name:

   ```sh
   xcrun notarytool store-credentials volume-mixer --apple-id you@example.com --team-id TEAMID1234
   xcrun notarytool history --keychain-profile volume-mixer   # proves the profile works
   ```

4. **Sparkle signing key.** Generate the EdDSA key pair. The private key stays in the login keychain; the command
   prints the public key:

   ```sh
   "$(scripts/sparkle-tools.sh)/generate_keys"
   ```

   Put the public key in `Resources/Info.plist` as `SUPublicEDKey`, in place of `REPLACE_WITH_YOUR_PUBLIC_ED_KEY`.
   Until then the updater stays off. Back up the private key with
   `"$(scripts/sparkle-tools.sh)/generate_keys" -x <file>`, store the file in a password manager and delete it.
   Never commit it. Losing the key means every installed copy has to be updated by hand once.
5. **GitHub Pages.** The repository has to be public. GitHub Pages on a private repository needs a paid plan, and
   Sparkle cannot download release assets from a private repository at all. Then: Settings → Pages → Build and
   deployment → Deploy from a branch → `main`, `/docs`. Check it:

   ```sh
   curl -fsS https://rokoov.github.io/volume-mixer/appcast.xml | head -3
   ```

## Each release

1. On `dev`, raise `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
   `CFBundleVersion` must go up with every release: it is the number Sparkle compares.
2. Build, sign and notarize:

   ```sh
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" NOTARY_PROFILE=volume-mixer scripts/release.sh
   ```

   It ends with `spctl` reporting `source=Notarized Developer ID` and prints the zip's SHA-256.
3. Write the release notes as plain text (`build/notes-<version>.txt`): the update window shows them as they are.
4. Add the release to the feed and commit it on `dev`:

   ```sh
   scripts/appcast.sh build/VolumeMixer-<version>.zip build/notes-<version>.txt
   ```

   The entry carries the signature of that exact zip. Build again after this and the signature no longer matches:
   remove the entry from `docs/appcast.xml` and run `appcast.sh` on the new zip.
5. Open the release PR from `dev` into `main` and merge it. If GitHub deletes `dev` after the merge, push it back:
   `git switch dev && git merge --ff-only origin/main && git push -u origin dev`.
6. Right after the merge, tag `main` and publish the GitHub Release with the same zip. Pages publishes the feed
   within minutes of the merge, and until the release exists the feed points at a missing file.

   ```sh
   git switch main && git pull
   git tag -a v<version> -m "Volume Mixer <version>" && git push origin v<version>
   gh release create v<version> build/VolumeMixer-<version>.zip --verify-tag \
       --title "Volume Mixer <version>" --notes-file build/notes-<version>.txt
   ```

7. Check: the feed lists the new version, and an older copy finds it with **Check for Updates…** and relaunches
   as the new version.

## When something fails

- `Notarization failed: Invalid`: the script prints Apple's log, which names each file and the problem. The usual
  causes are a file signed without the hardened runtime or without a timestamp.
- Gatekeeper still warns about a downloaded copy: `xcrun stapler validate VolumeMixer.app` and
  `spctl --assess --type execute --verbose=2 VolumeMixer.app` show whether the ticket is in the app.
- An update downloads but does not install: the zip changed after `appcast.sh` signed it, or `SUPublicEDKey` does
  not match the key that signed it. `"$(scripts/sparkle-tools.sh)/sign_update" --verify <zip> <signature>` checks
  one against the other.
