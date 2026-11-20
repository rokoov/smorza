# Security Policy

## Supported versions

Only the latest release of Smorza gets security fixes. Smorza updates itself through Sparkle, so the fix reaches everyone on the next update check.

| Version | Supported |
| ------- | --------- |
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

Please don't open a public issue for a security problem.

- **Preferred:** use GitHub's private reporting. Open the **Security** tab of this repository and click **Report a vulnerability**.
- **Or email:** rokoodev@gmail.com with "Smorza security" in the subject.

Include what you found, the steps to reproduce it, the Smorza and macOS versions, and what an attacker could do with it. A proof of concept helps a lot.

You can expect a first reply within a few days. Once the problem is confirmed, I'll work on a fix, ship it in a new release and credit you in the release notes, unless you'd rather stay anonymous. Please give me a reasonable time to release the fix before you disclose it publicly.

## Scope

In scope:

- The Smorza app and its code in this repository
- The update path: the appcast at `smorza.app/appcast.xml`, the release downloads and their EdDSA signatures
- The website smorza.app

Out of scope: problems in macOS itself or in Sparkle (please report those to Apple or to the Sparkle project), and reports that need an attacker who already controls your Mac.

## How Smorza handles your audio

Smorza asks for the System Audio Recording permission so it can change each app's volume. Audio is processed in memory only and is never recorded, saved or sent anywhere. The app has no analytics and no account. Its only network request is the update check, and it installs only updates signed with the developer's EdDSA key.
