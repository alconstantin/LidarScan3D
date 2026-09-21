# LiDAR Scan 3D

[![Build unsigned IPA](https://github.com/alconstantin/LidarScan3D/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/alconstantin/LidarScan3D/actions/workflows/build-ipa.yml)

An iPhone app that scans real objects with the LiDAR sensor and turns them into
3D-printable models. It wraps Apple's Object Capture — LiDAR-guided capture plus
on-device photogrammetry — and adds the parts a printing workflow actually needs:
true millimetre scale, a flat base, and STL export.

> **Status:** the scanning, geometry and export code builds and is verified against
> synthetic meshes, but has not yet been run on a device. See
> [Known limitations](#known-limitations) before relying on it.

## What it does

- **Guided scanning.** Apple's capture UI with a bounding box, coverage dial and
  live feedback ("move closer", "slow down", "too dark"), plus a flip pass so the
  underside gets photographed too.
- **On-device reconstruction.** Photogrammetry runs on the phone; nothing is uploaded.
- **True scale.** LiDAR gives real dimensions, usually within a few millimetres. A
  "Match real size" control rescales the model from one caliper measurement if you
  need an exact fit.
- **Orientation.** Quarter turns put any of the six sides against the print bed.
- **Flat base.** Slices the ragged underside off and caps it flat, so the print
  adheres to the bed and stands straight.
- **Export.** Binary STL and OBJ in millimetres for your slicer, or the textured
  USDZ for viewing and AR. Share by AirDrop, save to Files, or open straight in a
  slicer app.

## Requirements

- An iPhone or iPad **Pro** with a LiDAR sensor, running **iOS 17 or later**.
  Object Capture needs the depth sensor; the app disables scanning and says so on
  hardware that lacks it.
- To build: macOS with Xcode 16 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Getting the app

### Prebuilt

Every push to `main` builds an unsigned `.ipa`. Open the
[latest run](https://github.com/alconstantin/LidarScan3D/actions/workflows/build-ipa.yml?query=branch%3Amain),
scroll to **Artifacts**, and download `LidarScan3D-ipa`. Unzip it once to get
`LidarScan3D.ipa`. You must be signed in to GitHub to download artifacts, and they
expire 90 days after the build.

The `.ipa` is unsigned, so it needs signing before it will install:

- **On a Mac** — open the project in Xcode, sign in with your Apple ID under
  Settings → Accounts, pick your device and run. Simplest path if you have one.
- **On Windows** — [Sideloadly](https://sideloadly.io) with your Apple ID. Install
  iTunes and iCloud from Apple's site rather than the Microsoft Store, or the device
  drivers will be missing. Afterwards trust the certificate on the phone under
  Settings → General → VPN & Device Management.

A free Apple ID signs apps for **7 days**, after which the app stops launching and
must be re-installed; a paid developer account extends that to a year.

### Building from source

```sh
brew install xcodegen
xcodegen generate
open LidarScan3D.xcodeproj
```

`project.yml` is the source of truth — the `.xcodeproj` is generated and not
committed. To reproduce the CI build from the command line:

```sh
xcodebuild -project LidarScan3D.xcodeproj -scheme LidarScan3D \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

## Using it

**Scan.** Tap *New Scan*, aim at the object and tap *Continue*. Adjust the box so it
tightly surrounds the object, then *Start capture* and walk slowly around it. When
the pass completes you can flip the object to capture its underside, scan again from
a different height, or finish and build the model. Reconstruction takes a few minutes
and keeps the screen awake.

**Prepare.** Open the scan to get a 3D preview with its real dimensions. Turn the
model until the side you want to print on faces the grey bed. Enable *Flat base* and
raise the trim until the ragged underside is gone — the preview shows the actual cut.
Set the scale, or tap *Match real size* and enter a measured dimension.

**Export.** *Export STL* writes a binary STL in millimetres, ready for a slicer. Files
land in `Exports` inside the scan's folder and are reachable from the Files app under
**On My iPhone → LiDAR Scan 3D**.

## Tips for good scans

- Bright, even, diffuse light. Hard shadows confuse photogrammetry.
- Matte, textured objects work best. Shiny, transparent or plain single-colour
  objects need a matte spray or powder to reconstruct at all.
- Put the object on a plain, non-reflective surface with free space all around it.
- Objects from mug size to chair size work well. Below roughly 5 cm, detail is lost.

## How it works

Object Capture writes a textured **USDZ** in metres, Y-up. Everything downstream
works in a single convention: **millimetres, Z-up, centred on X/Y, resting on Z = 0**.
`MeshData.seated(vertices:indices:)` is the one place that establishes it, so every
operation that moves geometry ends there and exports always sit on the bed.

The **flat base** is a plane cut, not a vertex clamp — clamping would smear the lower
silhouette down rather than remove it:

1. Triangles straddling the cut plane are split, with winding preserved by a cyclic
   rotation of their vertices.
2. The rim edges left along the plane are chained into closed loops, and each loop is
   capped by a fan from its own centre. An object that cuts into several pieces — two
   legs, a handle — gets independent caps instead of one bridging them.
3. Cap triangles are forced to face downwards rather than trusting rim direction.
4. A plane landing exactly on an existing vertex collapses triangles onto a line or a
   point. Those slivers and their zero-length rim edges are dropped; leaving them in
   breaks watertightness. Vertices are matched at micron precision, so anything within
   a micron of the cut hits this.

The cut is covered by `Tests/GeometryTests`, which checks that every edge is shared
by exactly two triangles in the same two directions, and that signed volumes match
analytic values. Sphere cuts (including planes landing exactly on vertex rings), a
two-legged object whose caps must stay independent, and an open mesh that the cut must
not make worse all run on every push. Because `Sources/Geometry` carries no UIKit
dependency, the tests compile the app's own source rather than a copy:

```sh
swift test
```

`tools/check_stl.py` runs the same checks against a real exported `.stl`.

**Orientation** is stored as a quaternion and always re-applied to the untouched
original mesh, so repeated turns accumulate in the quaternion and never in the
geometry. Quarter turns about X and Y generate all 24 axis-aligned orientations, so
every side is reachable.

### Project layout

| Path | |
|---|---|
| `Sources/LidarScan3DApp.swift` | App entry point and phase routing |
| `Sources/AppModel.swift` | Capture session, reconstruction, scan lifecycle |
| `Sources/CaptureView.swift` | Guided capture UI and live feedback |
| `Sources/ReconstructionView.swift` | Reconstruction progress |
| `Sources/ResultView.swift` | Preview, orientation, scale, flat base, export |
| `Sources/Geometry/MeshData.swift` | Mesh loading, plane cut, STL/OBJ writers |
| `Sources/MeshDataPreview.swift` | SceneKit preview geometry (the only UIKit part of the mesh code) |
| `Sources/ScanFolder.swift` | On-disk layout of a scan |
| `Tests/GeometryTests/` | Geometry tests, run on macOS by `swift test` |
| `tools/check_stl.py` | Audits an exported STL for printability |
| `project.yml` | XcodeGen spec — edit this, not the `.xcodeproj` |
| `Package.swift` | Builds `Sources/Geometry` alone, so CI can test it |

Each scan lives in `Documents/Scans/<name>/` holding `Images`, `Checkpoints`,
`Exports` and `model.usdz`.

## Known limitations

- **Not yet run on a device.** The geometry is covered by tests and the app compiles,
  but no real scan has been through it. Treat the defaults — particularly the 2%
  starting trim — as untested guesses.
- **Watertightness depends on the input.** The plane cut preserves it, but cannot
  create it: a non-manifold scan produces a non-manifold STL. Object Capture meshes
  are not guaranteed clean, so a slicer may still complain.
- **Orientation is axis-aligned only.** Quarter turns fix a model lying on the wrong
  side, but cannot correct a scan that leans by a few degrees. An automatic levelling
  pass was written and removed: fitting a plane through the lowest slab of the mesh is
  biased, because a horizontal slab preferentially samples the low side of a tilted
  base, and the bias grows with roughness — the exact condition a flat base exists to
  handle. Measured against a rough underside it made things worse rather than better,
  and no fit-quality threshold separated its good results from its bad ones. Judging
  the lean by eye against the bed plane is honest; a fit that silently worsens a print
  is not. A robust method (RANSAC, or the convex hull's largest face) is the way back
  in, chosen against real scan data rather than synthetic noise.
- **No mesh repair, decimation or hollowing.** Meshes are exported at the resolution
  Object Capture produces.
- **iPhone only, portrait only.**

## License

MIT — see [LICENSE](LICENSE).

Object Capture, RealityKit, SceneKit and ModelIO are Apple frameworks, used under
Apple's terms; this licence covers the code in this repository only.
