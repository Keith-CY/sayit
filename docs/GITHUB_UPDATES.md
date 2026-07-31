# GitHub Updates and Releases

SayIt ships directly from GitHub Releases without an Apple Developer account.
Sparkle 2 checks and installs updates; GitHub Actions creates each release from
a version tag.

## Trust model

Every release uses:

- A stable Sparkle EdDSA key that signs the update archive and the complete
  `appcast.xml`.
- An ad-hoc macOS code signature that seals the app and its embedded Sparkle
  components against accidental packaging corruption.

The public EdDSA key is embedded in `Info.plist`. It is the update chain's
identity and authenticity check. Sparkle accepts a valid archive signature even
though each ad-hoc app signature has a different designated requirement.

This protects the update path from a replaced archive or feed, but it does not
make the app notarized or give it an Apple-issued identity. The first
installation must therefore be approved manually in macOS. Once 1.6.0 or later
is installed, Sparkle can update it in place.

## Required GitHub secrets

The repository requires one Actions secret:

- `SPARKLE_EDDSA_PRIVATE_KEY`

Never print, commit, or attach this value to an issue or release. GitHub secrets
cannot be downloaded later, so keep a separate encrypted offline backup of the
EdDSA private key.

The EdDSA Keychain account used on the maintainer Mac is
`com.sayit.github-updates`.

## Publish a release

1. Merge all release changes into `main`.
2. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in both SayIt target
   build configurations.
3. Confirm `Info.plist` still uses the Xcode version placeholders.
4. Run the normal build and test workflow.
5. Create and push a tag that exactly matches the marketing version, such as
   `v1.6.0`.

The `Publish GitHub Release` workflow then:

1. Verifies the tag and bundle versions match.
2. Runs lint and tests.
3. Archives an Apple-silicon Release build using an ad-hoc signature.
4. Verifies the complete nested code signature and confirms the app is ad-hoc
   signed.
5. Creates `SayIt-v<version>-arm64.zip`.
6. Generates and verifies a signed Sparkle `appcast.xml`.
7. Publishes both files in the GitHub Release.

The stable in-app feed URL is:

`https://github.com/Keith-CY/sayit/releases/latest/download/appcast.xml`

Do not upload an Actions preview artifact as a GitHub Release asset. Preview
artifacts are not signed by the Sparkle EdDSA key and are not part of the
supported update chain.

## First release and recovery

Version 1.6.0 is the bootstrap release. Older builds do not contain Sparkle, so
install 1.6.0 manually from GitHub Releases. Validate the next release by
updating from 1.6.0 through the app before calling the chain production-ready.

Do not casually rotate the EdDSA identity. Losing or replacing the private key
requires a manual reinstall with a build containing a new public key. Because
there is no Developer ID signature as a fallback, keep more than one encrypted
offline backup.

If the update feed is temporarily unavailable, the installed app continues to
work. Users can always use **View Releases** and install a verified manual
download.
