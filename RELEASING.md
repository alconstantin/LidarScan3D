# Release and version guide

## Three different identifiers

| Identifier | Meaning |
|---|---|
| `MARKETING_VERSION` in `project.yml` | App version for builds from that source, currently 1.2 |
| `CURRENT_PROJECT_VERSION` | Local app build, currently 3; CI overrides with its run number |
| Git tag `v1.2` / GitHub release | Named source snapshot / downloadable assets produced by its successful workflow |

Changing the app version does not create a tag. Pushing main does not create a
release. Pushing a `v*` tag starts a workflow; publication happens after its tests,
export audit, build and packaging succeed. Current workflow derives tagged app
versions from the tag. Older tags use the workflow stored in their own commit.

Existing tags are `v1.0`, `v1.1` (`473068a`) and `v1.2` (`0c4fff8`). Their remote
publication was confirmed from Terminal output on 7 October 2026. Tagged CI
completion and release asset availability have not been independently confirmed
in this documentation update.

## Before publishing a new version

- Complete automated preflight in [TESTING.md](TESTING.md), review the diff and
  ensure no source photos, local signing credentials or generated builds are staged.
- Update `MARKETING_VERSION` and increment the local build in `project.yml` for a
  new app version. Update [CHANGELOG.md](CHANGELOG.md) and relevant user/test guides.
- Record hardware/slicer tests accurately; mark untested behavior explicitly.
- Commit and push the intended source. Confirm the tag name does not already exist.

For a future version, replace `vX.Y.Z` below with the chosen unused version:

```sh
git status --short --branch
git diff --check
git add -A
git commit -m "Describe the release changes"
git push origin main
git tag -a vX.Y.Z HEAD -m "Describe the release"
git push origin vX.Y.Z
git ls-remote --tags origin
```

Do not move or force-update published tags. Documentation-only changes after v1.2
can stay on main; the existing v1.2 tag remains its original source snapshot.
If a tagged build fails, inspect that tag's Actions run. Fix source/workflow on main
and create an appropriate new version if the published source must change.

## Verify the result

1. Open [Actions](https://github.com/alconstantin/LidarScan3D/actions) and select the
   intended tag, not merely the newest run. Confirm tests/export audit/build passed.
2. Open [Releases](https://github.com/alconstantin/LidarScan3D/releases); confirm the
   matching release contains `LidarScan3D.ipa`. Artifact-only main builds are different.
3. Sign/install through [INSTALL.md](INSTALL.md). Record the installed version/build
   and the Actions run. Verify existing data and sample preparation before scanning.
4. Run the device/slicer matrix before describing the release as device-validated.

The IPA is unsigned. Releasing it on GitHub does not submit it to TestFlight or
the App Store. Those require Apple signing, provisioning and distribution setup.

## App Store preparation

Use the publishing account's bundle ID/team in `project.yml`, regenerate and archive.
Review current App Store screenshot/metadata, support and privacy-policy requirements
in App Store Connect. The repository has a privacy manifest, icon and encryption
statement; these do not establish review acceptance. Describe LiDAR requirements
and the sample path for reviewers on unsupported hardware.

## Restricted agent environments

If Git writes fail with `.git/index.lock: Operation not permitted`, run the approved
Git steps in the user's own Terminal. If elevated execution fails with the gateway's
approval-model `403`, the configured gateway/approval routing needs administrator
attention. A sandbox DNS failure while Terminal reaches GitHub is separate from
GitHub authentication. Do not change GitHub passwords or share tokens to fix it.
