# v1.2 test plan

This plan targets `v1.2` (`0c4fff8`) and later documentation-only commits.
Tags identify source; the installed app version/build and selected Actions run
identify the binary. Do not assume a release asset exists just because its tag does.

## Before testing

1. Confirm the v1.2 Actions run passed and its IPA is present, or build the tag in Xcode.
2. Record the source commit, app version/build, installation method, device identifier
   and iOS version. Use the home-screen version label and Xcode/Console diagnostics.
3. Back up existing scan folders through Files. Use a separate disposable scan for
   deletion, interruption and update tests. Keep the bundle ID/signing identity stable.
4. Prepare a ruler/calipers, a textured object with three known dimensions, a symmetric
   cylinder, a small legitimate detached part and a larger detailed object.
5. Prepare Bambu Studio and a second slicer (PrusaSlicer or OrcaSlicer), recording versions.
6. Agree on acceptable dimensional error for the intended print. Record raw and
   calibrated error; do not replace measured errors with a generic accuracy claim.

## Automated preflight

Run from the repository root in a normal macOS Terminal:

```sh
mkdir -p /private/tmp/lidarscan3d-test-exports
EXPORT_SAMPLES_DIR=/private/tmp/lidarscan3d-test-exports swift test
python3 tools/check_stl.py \
  /private/tmp/lidarscan3d-test-exports/sample-vase-flat.stl \
  /private/tmp/lidarscan3d-test-exports/sample-vase-flat.3mf
xcodegen generate
xcodebuild -project LidarScan3D.xcodeproj -scheme LidarScan3D \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
git diff --check
```

At v1.2, the suite has 65 tests. Independent sample exports should agree at about
77 × 77 × 89 mm after the default 2% trim, sit at Z=0, and have no hole,
over-used or inconsistent edges. The Python audit checks topology, not intersections.
An unsigned build cannot be installed until signed.

Local restricted-agent builds previously needed temporary module caches and a
one-invocation Swift macro sandbox setting. Those settings are not part of the
project/CI and are not proof of a device fault. Prefer the normal Terminal or CI
commands above; report exact build diagnostics if they fail.

## Device matrix

Use a current LiDAR iPhone and, when available, the oldest supported device.
Use a non-LiDAR iPhone for disabled scanning and sample behavior. Simulator
results do not validate capture. Mark missing-device checks as Not run.

| ID | Scenario | Expected result / evidence |
|---|---|---|
| S01 | Open sample, orbit/zoom, highlight, compare original | Preview renders; X/Y/Z match labels; overlays/legend readable; original comparison leaves exports unchanged |
| S02 | Turn, trim, smooth, calibrate, leave and reopen; restart app | Preparation restored; original and existing exports preserved |
| S03 | Reset preparation | All edits reset; exported files retained |
| S04 | Rename, return home, reopen | New title shown; folder/navigation and recipe intact |
| S05 | Remove source photos on disposable completed scan | Confirmation shown; storage decreases; model/recipe/exports remain usable |
| S06 | Delete disposable scan from result and list | Confirmation; returns to list; all owned files removed; cancellation leaves files intact |
| S07 | Custom printer and invalid/valid calibration | Invalid entries explained; valid size correct; 10–500% limits enforced |
| C01 | Deny camera, allow later in Settings | Clear recovery message; capture works after permission restored |
| C02 | No initial photos / stopped photos | Stall guidance after roughly 15 seconds; finish disabled below 20 photos |
| C03 | Multiple-height passes and eligible flip | No crash; pause/resume/detection work; pass count retained after flip |
| C04 | Symmetric object with flip unavailable | Guidance suggests another-height pass; no unsupported flip offered |
| C05 | Cancel capture | Returns home; explicitly cancelled capture discarded |
| R01 | Cancel reconstruction immediately during Preparing and later during processing | Cancellation honored; no permanent spinner; saved photos visible for retry |
| R02 | Retry interrupted reconstruction | Completes from input, or clear error with photos retained |
| R03 | Background, lock and force-close during capture/reconstruction (separate trials) | On reopen, completed model or visible interrupted input; record actual platform behavior |
| E01 | Same prepared scan exported as STL, 3MF, OBJ | Slicer dimensions agree with app within display rounding; orientation/base consistent |
| E02 | Export twice and share USDZ | Unique exports; USDZ remains original textured model; share works |
| E03 | Rectangular custom plate requiring quarter turn | Fit label and actual slicer placement checked; rotate in slicer if necessary |
| P01 | Rapid edits on a large real scan; leave/reopen | Latest result wins; UI responsive; no memory termination; time/peak memory recorded |
| A01 | Largest Dynamic Type, VoiceOver, small screen, light/dark | Controls reachable/readable; text describes problems without relying only on color |
| U01 | Install update over existing app with same identity | Original scans, names and recipes preserved; expected app version/build visible |

## Repeatable accuracy and support-surface trials

Scan the same reference object three times in fixed diffuse light, with at least
60 varied photographs and documented passes. Record actual dimensions, raw app
X/Y/Z, the side used for calibration and calibrated dimensions. Measure again
in both slicers after export. A one-side calibration is uniform scaling, not
proof that the remaining dimensions or reconstructed shape are correct.

Repeat the cylinder on the usual table and on a small matte contrasting support.
Inspect proposed support removal before accepting it. Check a separate small
intentional part survives cleanup. Apply the smallest useful base trim and
record changes in size and surface warnings. Print the reference only after
sliced layers have been inspected; measure the print separately from scan error.

## Record a run

Copy this block into a local test note or an issue. Keep source photos private
unless you deliberately choose to share them.

```text
Date:
Tester:
Source tag/commit:
Installed version/build:
Actions run or local build:
Device identifier / iOS:
Slicer names/versions:
Test ID:
Result: Pass / Fail / Not run
Steps:
Expected / actual:
Capture photos / passes / warnings:
Real / raw app / calibrated app / slicer dimensions (mm):
Reconstruction / preparation / export time:
Memory or thermal observations:
Relevant filenames / logs / screenshots:
```

For crashes, collect the Xcode stack or the app's report under Settings → Privacy
& Security → Analytics & Improvements → Analytics Data. For hangs, pause in
Xcode and capture thread stacks. Capture logs use subsystem
`com.alconstantin.lidarscan3d`; device capability records include model/iOS/support.

## Gate for the next feature round

Resolve crashes, data loss, missed cancellation, lost recipes and dimension/export
mismatches first. Device/slicer checks must be recorded as passed, failed or not
run. Only then select repair or thickness work based on real problem meshes.
No feature is accepted solely because synthetic geometry tests pass.
