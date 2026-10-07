# LiDAR Scan 3D

[![Build unsigned IPA](https://github.com/alconstantin/LidarScan3D/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/alconstantin/LidarScan3D/actions/workflows/build-ipa.yml)

An iPhone app that turns real objects into models for 3D printing using Apple's
LiDAR-guided Object Capture and on-device photogrammetry. Prepare the model at
millimetre scale, inspect its surface, and export 3MF, STL or OBJ.

**Current source version: 1.2.** Local builds identify themselves as 1.2 (3).
GitHub Actions builds use their workflow run number. Tags `v1.1` and `v1.2` have
been pushed; downloadable releases depend on successful tagged builds.

**Status: ready for the next device-testing round.** Local validation passed 65
automated tests, an unsigned iPhoneOS Release build, and independent sample STL/3MF
topology checks. These results do not establish physical-device capture quality,
preview readability, real-scan performance or slicer compatibility for v1.2.

| Need | Guide |
|---|---|
| Install or update on an iPhone | [INSTALL.md](INSTALL.md) |
| Prepare and run the test round | [TESTING.md](TESTING.md) |
| See changes by version | [CHANGELOG.md](CHANGELOG.md) |
| Publish and verify a release | [RELEASING.md](RELEASING.md) |
| Review findings and remaining work | [AUDIT.md](AUDIT.md) |

## Features

- **Guided capture:** bounding-box detection, live lighting/distance/motion feedback,
  photo count, pass count and a warning when photos stop arriving. Capture requires
  at least 20 photos before building; 60 or more varied views usually improve detail.
- **Multiple passes:** change height for better coverage, or pause and flip the
  object when Object Capture expects it can align the underside.
- **On-device reconstruction and recovery:** interrupted scans remain visible.
  Retry reconstruction when enough photos are saved, or explicitly delete them.
- **Print preparation:** square the footprint to X/Y, choose the bed-facing side,
  remove proposed support surfaces or tiny isolated fragments, apply reversible
  smoothing, and cut/cap a flat base.
- **Saved edits:** orientation, scale, cleanup, smoothing and trim are saved with
  each scan. Reset preparation returns to the original mesh.
- **Calibration:** match a measured width, depth, height or longest side with a
  uniform scale between 10% and 500%. Invalid/out-of-range input is reported.
- **Surface inspection:** check edge usage, winding, shell volume and non-neighbour
  triangle intersections. Optional orange edge/red face overlays locate warnings;
  generated previews show X/Y/Z markers. Compare with the original scan.
- **Printer fit:** presets for Bambu A1 mini, A1, P1/P2/X1 and H2D, plus custom
  width/depth/height and scale-to-fit.
- **Scan library:** rename scans, browse thumbnails, inspect storage usage and
  optionally delete source photos while keeping models, preparation and exports.
- **Exports:** millimetre 3MF, binary STL and OBJ; original textured USDZ for AR/viewing.
  Share through the system share sheet or find exports in Files.
- **Bundled sample:** a vase on a foot ring lets you test preparation without LiDAR.

## Requirements and installation

Scanning requires an iPhone Pro with LiDAR, iOS 17 or later, camera permission,
and runtime Object Capture/scene-depth support. The app checks capabilities;
a specific device model still needs physical validation. On supported iOS devices
without LiDAR, scanning is disabled and the sample remains available.

The app is designed for iPhone portrait mode. iPad behavior requires validation.
To build, use macOS, Xcode 16 or later (local checks used Xcode 27), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

Download an unsigned IPA from [GitHub Releases](https://github.com/alconstantin/LidarScan3D/releases).
Choose the intended version and verify its asset exists. A pushed tag alone does
not mean its build or release succeeded. Successful main-branch builds also offer
artifacts in [GitHub Actions](https://github.com/alconstantin/LidarScan3D/actions).
IPAs need signing before installation; follow [INSTALL.md](INSTALL.md).

## Using the app

1. **Scan:** tap *New Scan*, aim at the object, tap *Continue*, then fit the box
   tightly around it. Reset detection if it selects the table. Tap *Start capture*
   and walk slowly around the object. Take another pass at a different height;
   use a flip pass only when offered. Finish after enough varied photos exist.
2. **Reconstruct:** keep the app open while it works. Cancel remains available
   during preparation and processing. Saved input from interrupted reconstruction
   can be retried from *Interrupted scans*. Explicitly cancelling capture discards
   that capture; it is different from cancelling reconstruction.
3. **Prepare:** inspect the original and dimensions. Remove a support surface only
   if it is visibly part of the table/stand. Fragment cleanup removes parts only
   below both 0.5% of the main surface and 25 mm². Start smoothing at *Light*.
   Choose orientation, enable *Flat base*, and release its slider to rebuild.
4. **Calibrate:** measure the same side named in *Match real size…*. Calibration
   applies uniform scaling; it cannot correct shape distortion. Reopening restores
   the preparation, including scale. Resetting clears edits, not exported files.
5. **Inspect:** select a printer, read surface warnings, and enable highlights.
   Orange marks holes/inconsistent edges; red marks intersections/inward shells.
   Highlights show through surfaces and are bounded on damaged meshes. Comparing
   the original changes only the preview; exports always use prepared geometry.
6. **Export:** choose 3MF, STL or OBJ. USDZ sharing sends the original textured
   reconstruction, without preparation edits. Inspect dimensions, placement and
   sliced layers in the slicer before printing.

Exports are in **Files → On My iPhone → LiDAR Scan 3D → Scans → scan folder → Exports**.
Before updating or uninstalling, copy important scan folders and exports elsewhere.

## Capture tips

Use bright diffuse light, matte textured objects and a non-reflective support
that contrasts with the object. Keep free space around it and move steadily.
Shiny, transparent, thin or plain symmetric objects are difficult to reconstruct.
Objects smaller than roughly 5 cm commonly lose detail. Repeat scans with the
same object and lighting to distinguish capture variation from app changes.

Historical device work used a 40 mm cube captured from 30 photos. Face-plane
measurements were about 40.4 × 40.8 × 41.7 mm, while the raw bounding box was much
larger due to heading and bulge. Automatic squaring corrected heading, but did
not remove reconstruction distortion. This is an earlier observation, not a
v1.2 accuracy guarantee. Use [TESTING.md](TESTING.md) for new measurements.

## Build and automated checks

```sh
brew install xcodegen
xcodegen generate
open LidarScan3D.xcodeproj
```

`project.yml` is the source of truth. The Xcode project and generated Info.plist
are ignored. Regeneration resets signing settings; choose your development team
and connected device again before running. A free signing account commonly needs
renewal after seven days; preserve the signing identity/bundle ID when updating.

The run scheme disables Metal API Validation because previous Xcode 27 runs
aborted in RealityKit's shadow shader as the capture box appeared. CI checks this
scheme setting. Validate actual capture on a physical phone.

```sh
swift test
xcodebuild -project LidarScan3D.xcodeproj -scheme LidarScan3D \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

The Swift package compiles geometry and scan storage, without UIKit. Tests cover
cuts, caps, orientation, cleanup, smoothing, preparation persistence, cancellation
helpers and inspection reports. They do not drive the actual camera/session UI.
See [TESTING.md](TESTING.md) for export checks and the full hardware matrix.

## Data and geometry

A scan lives in `Documents/Scans/<stable folder>/`:

| Item | Purpose |
|---|---|
| `Images/` | Capture input; retained until explicit deletion |
| `Checkpoints/` | Reconstruction state; removed after success |
| `reconstruction.usdz` | Temporary output; promoted to `model.usdz` on success |
| `model.usdz` | Original textured model (metres, Y-up) |
| `model.obj` | Bundled sample copied into its own scan folder |
| `preparation.json` | Versioned orientation/scale/cleanup/smoothing/trim recipe |
| `capture-quality.json` | Recorded warnings, photo/pass counts when capture finishes |
| `name.json` | Display name; renaming leaves folder URLs stable |
| `thumbnail.jpg` | Cached model image; source photo is a fallback |
| `Exports/` | Unique prepared exports; previous exports are not overwritten |

The processing convention is **millimetres, Z-up, centred on X/Y, seated on Z=0**.
Mesh loading welds texture-seam duplicates and compacts surviving surface vertices.
Preparation order is orientation → support removal → fragment removal → smoothing
→ flat-base cut. Preview, dimensions, reports and prepared exports use this result.
The serial worker caches unchanged stages and cancels superseded work.

Flat-base cutting splits triangles at a plane, chains closed rim loops and
triangulates outer loops with nested holes. It preserves features such as a foot
ring instead of filling every loop independently. It is not general mesh repair.

## Limitations and next work

- Surface checks are bounded and exclude triangle pairs sharing a welded vertex.
  Passing checks does not establish wall thickness, support requirements or complete
  geometric validity. Inward shells may be intentional cavities and need review.
- LiDAR scale and photogrammetry shape are approximate. One measured dimension
  cannot correct bulging or missing detail. No precision claim replaces device tests.
- Smoothing does not repair holes, decimate, hollow or remove self-intersections.
  Flat-base cutting cannot reliably repair arbitrary damaged scans.
- Quarter turns and footprint squaring do not correct an arbitrary lean.
- Thumbnail rendering, overlays, accessibility, background interruptions and
  large-scan memory/thermal behavior still need physical-device verification.
- The app icon remains a placeholder. Automatic repair, thickness analysis and
  arbitrary tilt adjustment should follow validated scans and measured requirements.

## Project layout

| Path | Responsibility |
|---|---|
| `Sources/AppModel.swift` | Capture/reconstruction lifecycle and permission handling |
| `Sources/LidarScan3DApp.swift` | Phase routing |
| `Sources/CaptureView.swift`, `ReconstructionView.swift` | Capture guidance/progress |
| `Sources/HomeView.swift`, `ScanRow.swift` | Scan library and thumbnails |
| `Sources/ResultView.swift`, `MeshDataPreview.swift` | Preparation UI and inspection preview |
| `Sources/ScanFolder.swift` | Stable scan folders, naming, storage and recovery input |
| `Sources/Diagnostics.swift` | Device capability and capture logging |
| `Sources/Geometry/MeshData.swift`, `CapTriangulation.swift` | Loading, cleanup, smoothing, cutting and STL/OBJ export |
| `Sources/Geometry/Preparation.swift`, `CancellationGate.swift` | Saved recipes, serial processing and cancellation helpers |
| `Sources/Geometry/PrintReport.swift`, `BuildVolume.swift`, `ThreeMF.swift` | Surface checks, fit calculations and 3MF export |
| `Tests/GeometryTests/`, `Package.swift` | Platform-neutral regression suite |
| `tools/check_stl.py`, `tools/make_sample.py` | Independent export audit and sample generation |
| `Resources/`, `project.yml` | Bundled assets/privacy manifest and XcodeGen specification |
| `.github/workflows/build-ipa.yml` | Tests, unsigned IPA build and tagged releases |

## Privacy and distribution

Capture and reconstruction run on the device. There is no app telemetry or
server upload. Sharing/exporting sends files to destinations selected by the user.
Source photos and models can contain private surroundings; include only the files
you intend to share in a bug report.

The bundle includes an icon, privacy manifest and encryption declaration, checked
in CI. This is not App Store approval. Publishing requires the developer's signing
team/bundle ID, current App Store metadata/screenshots, support/privacy-policy URLs,
and review of the actual privacy questionnaire. See [RELEASING.md](RELEASING.md).

## License

Proprietary — all rights reserved. See [LICENSE](LICENSE). No use, copying or
distribution is permitted without written agreement from the copyright holder.
Apple frameworks remain subject to Apple's terms.
