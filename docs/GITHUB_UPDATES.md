# GitHub Updates and Releases

SayIt ships directly from GitHub Releases without an Apple Developer account.
Sparkle 2 checks and installs updates; GitHub Actions creates each release from
a version tag.

## Trust model

Every release uses:

- A stable Sparkle EdDSA key that signs the update archive and the complete
  `appcast.xml`.
- A stable self-signed macOS code-signing identity named
  `SayIt GitHub Release Signing` that seals the app and its embedded Sparkle
  components and keeps the app's designated requirement stable between builds.

The public EdDSA key is embedded in `Info.plist`. It is the update chain's
authenticity check. The stable macOS signing identity lets macOS associate
updates with the same app, so privacy grants such as Microphone and
Accessibility can survive an in-place update.

This protects the update path from a replaced archive or feed, but it does not
make the self-signed certificate Apple-trusted, notarize the app, or provide a
Developer ID identity. The first installation must therefore be approved
manually in macOS. Once 1.6.1 or later is installed, Sparkle can update it in
place while retaining the same local code identity.

## Required GitHub secrets

The repository requires three Actions secrets:

- `SPARKLE_EDDSA_PRIVATE_KEY`
- `SAYIT_SIGNING_CERTIFICATE_P12` (the signing identity exported as a `.p12`
  and base64-encoded)
- `SAYIT_SIGNING_CERTIFICATE_PASSWORD`

Never print, commit, or attach these values to an issue or release. GitHub
secrets cannot be downloaded later, so keep separate encrypted offline backups
of both the EdDSA private key and the signing identity.

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
3. Imports the stable self-signed identity into an ephemeral CI keychain.
4. Archives an Apple-silicon Release build with that identity.
5. Verifies the complete nested code signature and stable designated
   requirement.
6. Creates `SayIt-v<version>-arm64.zip`.
7. Generates and verifies a signed Sparkle `appcast.xml`.
8. Publishes both files in the GitHub Release.

The stable in-app feed URL is:

`https://github.com/Keith-CY/sayit/releases/latest/download/appcast.xml`

Do not upload an Actions preview artifact as a GitHub Release asset. Preview
artifacts are not signed by the Sparkle EdDSA key and are not part of the
supported update chain.

## First release and recovery

Version 1.6.0 introduced Sparkle. Version 1.6.1 introduces the stable macOS code
identity. A 1.6.0 installation can update through Sparkle, but users may need to
approve privacy permissions once more after that identity transition. Fresh
installs should start with 1.6.1 or later. Validate the next release by updating
from 1.6.1 through the app and confirming that privacy permissions persist
before calling the chain production-ready.

Do not casually rotate either identity. Losing or replacing the EdDSA private
key requires a manual reinstall with a build containing a new public key.
Replacing the macOS signing identity can also require users to re-approve
privacy permissions. Because there is no Developer ID signature as a fallback,
keep more than one encrypted offline backup of both identities.

If the update feed is temporarily unavailable, the installed app continues to
work. Users can always use **View Releases** and install a verified manual
download.
