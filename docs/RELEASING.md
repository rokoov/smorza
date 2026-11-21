# Releasing

How a Smorza release is built, signed and published, and how the app finds out about it.

## How it fits together

- `scripts/release.sh` builds the universal app, signs it ad hoc, zips it and puts it in a disk image. It needs
  Xcode, not only the Command Line Tools: Xcode's tools add the Shortcuts actions and the translations, and the
  script stops without them. Smorza has
  no Apple Developer ID, so a downloaded copy needs **Open Anyway** once (the README explains it). What protects
  updates is Sparkle's own signature, not Apple's.
- The zip is for Sparkle and the disk image is for people: the website's Download button picks the `.dmg` from
  the latest GitHub Release by itself.
- The app checks `https://smorza.app/appcast.xml` once a day (Sparkle). The feed itself is `docs/appcast.xml` in
  this repository, and smorza.app serves it from `main` (setup below). A release therefore reaches users when its
  release PR is merged, and the feed can never announce a version that `main` does not have.
- `scripts/appcast.sh` signs the release zip with the Sparkle EdDSA key and adds it to `docs/appcast.xml`. The app
  only installs an update whose signature matches the public key in its `Info.plist`.
- The zip itself is downloaded from the GitHub Release, which is why the repository has to be public.

No entitlements file: process taps are allowed by the System Audio Recording permission
(`NSAudioCaptureUsageDescription`), not by a hardened runtime entitlement. A hardened runtime build was checked on
macOS 27: the capture check passed and a turned-down app was heard through its route. The app never opens the
microphone, so it does not ask for `com.apple.security.device.audio-input` either.

## One-time setup

1. **Sparkle signing key.** Generate the EdDSA key pair. The private key stays in the login keychain; the command
   prints the public key:

   ```sh
   "$(scripts/sparkle-tools.sh)/generate_keys"
   ```

   Put the public key in `Resources/Info.plist` as `SUPublicEDKey`, in place of `REPLACE_WITH_YOUR_PUBLIC_ED_KEY`.
   Until then the updater stays off. Back up the private key with
   `"$(scripts/sparkle-tools.sh)/generate_keys" -x <file>`, keep the file in a password manager and delete it.
   Never commit it. Losing the key means every installed copy has to be updated by hand once.
2. **The feed on smorza.app.** `https://smorza.app/appcast.xml` has to return `docs/appcast.xml` from `main`. The
   simplest way is a permanent redirect, set once in the site's hosting, to
   `https://raw.githubusercontent.com/rokoov/smorza/main/docs/appcast.xml`. A copy of the file deployed with the
   site works too, but then every release needs a site deploy. Check it:

   ```sh
   curl -fsSL https://smorza.app/appcast.xml | head -3
   ```

3. **A public repository.** Sparkle cannot download release assets from a private repository.

## Each release

1. On `dev`, raise `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
   `CFBundleVersion` must go up with every release: it is the number Sparkle compares. Give the version's
   heading in `CHANGELOG.md` the release date.
2. Build: `scripts/release.sh` makes `build/Smorza-<version>.zip` and `build/Smorza-<version>.dmg` and prints the
   SHA-256 of both.
3. Write the release notes as plain text (`build/notes-<version>.txt`): the update window shows them as they are.
4. Add the release to the feed and commit it on `dev`:

   ```sh
   scripts/appcast.sh build/Smorza-<version>.zip build/notes-<version>.txt
   ```

   The entry carries the signature of that exact zip. Build again after this and the signature no longer matches:
   remove the entry from `docs/appcast.xml` and run `appcast.sh` on the new zip.
5. Open the release PR from `dev` into `main` and merge it. If GitHub deletes `dev` after the merge, push it back:
   `git switch dev && git merge --ff-only origin/main && git push -u origin dev`.
6. Right after the merge, tag `main` and publish the GitHub Release with the same zip and the disk image. Once
   `main` has the new feed, apps that check find the update, and until the release exists the feed points at a
   missing file.

   ```sh
   git switch main && git pull
   git tag -a v<version> -m "Smorza <version>" && git push origin v<version>
   gh release create v<version> build/Smorza-<version>.zip build/Smorza-<version>.dmg --verify-tag \
       --title "Smorza <version>" --notes-file build/notes-<version>.txt
   ```

   A file left out can be added later with `gh release upload v<version> build/Smorza-<version>.dmg`.

7. Check: `https://smorza.app/appcast.xml` lists the new version, and an older copy finds it with
   **Check for Updates…** and relaunches as the new version.
8. Homebrew: in the tap repository (`rokoov/homebrew-smorza`, made from `packaging/homebrew-smorza`), set
   `version` and `sha256` in `Casks/smorza.rb` to the new release and its disk image, then commit and push:

   ```sh
   shasum -a 256 build/Smorza-<version>.dmg
   ```

## With a Developer ID

The scripts also support a paid Apple Developer ID, should Smorza ever get one: `SIGN_IDENTITY="Developer ID
Application: <name> (<team>)"` signs every part with the hardened runtime and a timestamp, and
`NOTARY_PROFILE=<profile>` (saved with `xcrun notarytool store-credentials`) has Apple notarize the zip, then
staples the ticket and zips again. The disk image gets the same: it is signed with the identity, notarized and
stapled. Sparkle.framework is re-signed with the same certificate, so the hardened
runtime's library validation accepts it.

## When something fails

- An update downloads but does not install: the zip changed after `appcast.sh` signed it, or `SUPublicEDKey` does
  not match the key that signed it. `"$(scripts/sparkle-tools.sh)/sign_update" --verify <zip> <signature>` checks
  one against the other.
- The app never finds an update: `curl -fsSL https://smorza.app/appcast.xml` should print the feed with the new
  version, and the zip's address in it should download.
