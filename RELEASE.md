# Release Process

ShotBarApp releases are built by GitHub Actions from a version tag. The repository can stay public because signing and notarization credentials live only in GitHub encrypted secrets, scoped to the `release` environment. The workflow does not run on pull requests.

## Required GitHub Secrets

Create a GitHub environment named `release`, enable required reviewers for that environment if you want manual approval before signing runs, then add these environment secrets:

- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`: base64 text for the exported Developer ID Application `.p12`.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`: password used when exporting that `.p12`.
- `APPLE_ID`: Apple ID email used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for the Apple ID.
- `APPLE_TEAM_ID`: Apple Developer Team ID.

Do not reuse any password that was pasted into chat or committed anywhere. Generate a fresh app-specific password, set it as the GitHub secret, and revoke the exposed one.

## Export Signing Certificate

On the Mac that has the Developer ID certificate:

1. Open Keychain Access.
2. Select the Developer ID Application certificate and its private key.
3. Export as a `.p12` with a strong password.
4. Convert it to base64 and store it in GitHub:

```bash
base64 -i DeveloperIDApplication.p12 | gh secret set DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64 --env release --repo aneesahammed/shotbar
gh secret set DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD --env release --repo aneesahammed/shotbar
gh secret set APPLE_ID --env release --repo aneesahammed/shotbar
gh secret set APPLE_APP_SPECIFIC_PASSWORD --env release --repo aneesahammed/shotbar
gh secret set APPLE_TEAM_ID --env release --repo aneesahammed/shotbar
```

Never commit the `.p12`, app-specific password, notary profile, or keychain files.

## Cut A Release

1. Update `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and any docs.
2. Commit the release changes.
3. Tag and push:

```bash
git tag v1.1.0
git push origin HEAD
git push origin v1.1.0
```

The workflow builds the Release app, signs it with Developer ID, creates `ShotBarApp-v1.1.0.dmg`, notarizes and staples it, verifies Gatekeeper acceptance, then publishes the DMG to GitHub Releases.

You can also run the workflow manually from GitHub Actions with version `1.1.0`; it still checks that the requested version matches the Xcode project version before publishing.
