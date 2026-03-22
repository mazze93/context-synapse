# Release Checklist

## 1. Pre-tag verification

- [ ] Working tree is clean and all intended changes are committed.
- [ ] `main` is the source branch for the release commit.
- [ ] Local branch is rebased or merged cleanly onto `origin/main`.
- [ ] `swift package resolve` completes without unexpected dependency changes.
- [ ] `swift build -c release` succeeds locally.
- [ ] `swift test` succeeds locally.
- [ ] The CLI binary name is still `contextsynapse` or the workflow configuration block was updated to match.
- [ ] `default_config.json`, `README.md`, `INSTALL.md`, `SECURITY.md`, and `LICENSE` are present and current.
- [ ] No local-only files, archives, caches, or operator artifacts are staged for release.

## 2. Branch and repository state checks

- [ ] Required GitHub checks are green on the release commit:
- [ ] CI
- [ ] CodeQL
- [ ] Branch protection on `main` requires pull requests and passing status checks.
- [ ] Release tags follow the `v*` pattern.
- [ ] The intended tag points to a commit reachable from `main`.
- [ ] Any release notes or changelog content has been reviewed for accuracy.

## 3. Versioning checks

- [ ] The release version is final and consistent anywhere it is surfaced.
- [ ] The Git tag matches the intended public version exactly.
- [ ] The release title and generated notes do not contradict the tag or branch state.
- [ ] Any user-facing installation instructions still match the release artifact names.

## 4. Signing and notarization readiness

- [ ] Repository variables are set:
- [ ] `MACOS_SIGNING_IDENTITY`
- [ ] `APPLE_TEAM_ID`
- [ ] Repository secrets are set and valid:
- [ ] `APPLE_DEVELOPER_ID_APP_CERT_BASE64`
- [ ] `APPLE_DEVELOPER_ID_APP_CERT_PASSWORD`
- [ ] `APPLE_KEYCHAIN_PASSWORD`
- [ ] `APPLE_NOTARY_KEY_ID`
- [ ] `APPLE_NOTARY_ISSUER_ID`
- [ ] `APPLE_NOTARY_PRIVATE_KEY_BASE64`
- [ ] The Developer ID certificate is current and exportable as a `.p12`.
- [ ] The notary key is active and scoped correctly.
- [ ] If an Xcode workspace/project with the configured app scheme is present, production release must sign and notarize the app artifact successfully.
- [ ] If no Xcode workspace/project with the configured app scheme is present, the CLI-only release path remains acceptable for this tag.

## 5. SBOM, checksum, and provenance expectations

- [ ] The release workflow generated an SPDX JSON SBOM.
- [ ] `SHA256SUMS.txt` exists and covers every published release asset.
- [ ] Checksums were generated from the final packaged artifacts, not intermediate build products.
- [ ] If provenance attestations are enabled later, they must cover the final release assets and not only ephemeral workflow artifacts.

## 6. Safe test paths before production tag

- [ ] Run `workflow_dispatch` dry-run against the intended ref before cutting a production tag.
- [ ] Confirm the dry-run uploads workflow artifacts only and does not publish a GitHub Release.
- [ ] Review the packaged CLI archive contents from the dry-run.
- [ ] If app packaging is detected in dry-run, confirm the unsigned app packaging path works before relying on production signing.

## 7. Production release execution

- [ ] Create the annotated tag from the intended commit on `main`.
- [ ] Push the tag.
- [ ] Confirm the release workflow is triggered by the tag event, not manually.
- [ ] Confirm the workflow built the CLI artifact and uploaded checksums and SBOM.
- [ ] If app packaging was detected, confirm signing, notarization, and stapling all passed.
- [ ] Confirm the GitHub Release exists and all expected assets are attached.

## 8. Post-release verification

- [ ] Download release assets from GitHub Releases on a clean machine.
- [ ] Verify checksums using `shasum -a 256 -c SHA256SUMS.txt`.
- [ ] Inspect the SBOM for the expected package identity and release version.
- [ ] Verify the CLI archive extracts cleanly and the binary runs.
- [ ] If an app artifact was published, verify Gatekeeper acceptance and launch behavior on a clean macOS system.
- [ ] Confirm release notes match the actual asset set.

## 9. Rollback and revoke guidance

- [ ] If the release is broken but not security-relevant, mark the release clearly as withdrawn and cut a fixed follow-up release.
- [ ] If signing credentials are suspected compromised:
- [ ] Revoke affected certificates or keys immediately.
- [ ] Remove trust instructions from documentation until replacement material is issued.
- [ ] Publish a security advisory.
- [ ] If the artifact set is incomplete or incorrect, delete or replace affected assets and document the correction in release notes.
- [ ] If the tag was cut from the wrong commit, delete the GitHub Release, delete the tag remotely, and re-cut from the correct commit only after root-cause review.

## 10. Incident response hooks for a bad release

- [ ] Open an incident issue or internal incident record immediately.
- [ ] Preserve workflow logs, checksums, SBOM, and any notarization output.
- [ ] Classify the failure:
- [ ] build integrity
- [ ] packaging drift
- [ ] signing/notarization failure
- [ ] release publication error
- [ ] post-install verification failure
- [ ] Decide whether the event is a security incident, release engineering defect, or both.
- [ ] Notify downstream users if integrity, signing, or trust signals were affected.
- [ ] Record remediation steps before the next tag is cut.
