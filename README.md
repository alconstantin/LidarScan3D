# LiDAR Scan 3D

[![Build unsigned IPA](https://github.com/alconstantin/LidarScan3D/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/alconstantin/LidarScan3D/actions/workflows/build-ipa.yml)

An iPhone app that scans real objects with the LiDAR sensor and turns them into
3D-printable models. It wraps Apple's Object Capture — LiDAR-guided capture plus
on-device photogrammetry — and adds the parts a printing workflow actually needs:
true millimetre scale, a flat base, and STL export.

> **Status:** early device testing. The app runs on an iPhone Pro, and a first
> scan of a 40 mm test cube reconstructed within about 2 mm per side (see
> [Device testing](#device-testing)). The geometry and export code is also
> verified against synthetic meshes on every push. Read
> [Known limitations](#known-limitations) before relying on it.

## What it does

- **Guided scanning.** Apple's capture UI with a bounding box, coverage dial and
  live feedback ("move closer", "slow down", "too dark"), plus a flip pass so the
  underside gets photographed too. The flip is not offered when Object Capture
  reports that the object is too plain or symmetric to match up after turning.
- **On-device reconstruction.** Photogrammetry runs on the phone; nothing is uploaded.
- **True scale.** LiDAR gives real dimensions, usually within a few millimetres. A
  "Match real size" control rescales the model from one caliper measurement, taken
  along the side you choose (longest, width, depth or height).
- **Squared up automatically.** Scans come out at whatever heading the capture started
  from, so a box scanned at an angle would measure as its diagonal. On load the model
  is turned about the vertical axis until its sides run along X and Y, so the sizes
  shown are the ones a ruler would give.
- **Orientation.** Quarter turns put any of the six sides against the print bed.
- **Flat base.** Slices the ragged underside off and caps it flat, so the print
  adheres to the bed and stands straight.
- **Ready-to-print check.** Before you export, the app says whether the model is
  watertight (and if not, how many holes and bad edges it has), and whether it fits
  your printer's build volume, with one tap to scale it down if it does not. Bambu
  Lab's A1 mini, A1, P1/P2/X1 and H2D are built in.
- **Sample scan.** A bundled vase lets you try everything after the scan itself on
  any iPhone, with or without LiDAR.
- **Export.** 3MF, Bambu Studio's native format, placed on the chosen printer's plate;
  binary STL and OBJ in millimetres for any slicer, or the textured
  USDZ for viewing and AR. Share by AirDrop, save to Files, or open straight in a
  slicer app.

## Requirements

- An iPhone **Pro** with a LiDAR sensor (iPhone 12 Pro or later), running **iOS 17 or
  later**. Object Capture needs the depth sensor; the app disables scanning and says so
  on hardware that lacks it. The app is built for iPhone; an iPad Pro runs it in
  iPhone compatibility mode.
- To build: macOS with Xcode 16 or later (tested with Xcode 27) and
  [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Getting the app

### Prebuilt

**Step-by-step install guide for testers: [INSTALL.md](INSTALL.md).**

Download `LidarScan3D.ipa` from the
[latest release](https://github.com/alconstantin/LidarScan3D/releases/latest).
Every push to `main` also builds one, available under **Artifacts** of the
[latest run](https://github.com/alconstantin/LidarScan3D/actions/workflows/build-ipa.yml?query=branch%3Amain)
(GitHub sign-in required; expires after 90 days).

The `.ipa` is unsigned, so it needs signing before it will install:

- **On Windows or Mac** — [Sideloadly](https://sideloadly.io) with your Apple ID,
  as described in [INSTALL.md](INSTALL.md).
- **On a Mac with Xcode** — open the project in Xcode, sign in with your Apple ID
  under Settings → Accounts, pick your device and run.

A free Apple ID signs apps for **7 days**, after which the app stops launching and
must be re-installed; a paid developer account extends that to a year.

To publish a new release, push a version tag; CI builds the `.ipa` and attaches it:

```sh
git tag v1.1
git push origin v1.1
```

### Building from source

```sh
brew install xcodegen
xcodegen generate
open LidarScan3D.xcodeproj
```

`project.yml` is the source of truth — the `.xcodeproj` is generated and not
committed. `xcodegen generate` rewrites the project, including the signing team, so
after every generate, pick your team again under the target's *Signing &
Capabilities* before running on a device.

To run on a phone, select it as the run destination and press ⌘R. Scanning means
walking around the object, which a cable makes awkward: once the phone has been
connected by cable, tick *Connect via network* for it under *Window → Devices and
Simulators*, and Xcode will install and debug over Wi-Fi from then on (Mac and
phone on the same network).

The scheme runs with **Metal API Validation off**. With it on, Xcode aborts the
app as soon as the capture box appears, on an assertion inside RealityKit's own
shadow shader (`meshShadowCalculateMip: missing Threadgroup Memory binding`), not
in this app's code. The setting lives in `project.yml`, because a checkbox set in
Xcode would be lost on the next generate, and CI fails if the generated scheme turns
validation back on.

To reproduce the CI build from the command line:

```sh
xcodebuild -project LidarScan3D.xcodeproj -scheme LidarScan3D \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

## Using it

**Scan.** Tap *New Scan*, put the white dot in the middle of the screen on the object
and tap *Continue*: Object Capture places its box around whatever is under the dot.
If the box lands on the table or a stand instead, aim again and tap *Reset box*. Drag
the box's sides and top until it tightly surrounds the object, then *Start capture*
and walk slowly around it, keeping the object in the middle of the frame.

When the pass completes you can flip the object to capture its underside, scan again
from a different height, or finish and build the model. *Flip* pauses the capture
while you turn the object over; tap *Continue* and fit the box around it again for
the second pass. Reconstruction takes a few minutes and keeps the screen awake.

**Prepare.** Open the scan to get a 3D preview with its real dimensions, already
squared up with X and Y. Turn the model until the side you want to print on faces the
grey bed. Enable *Flat base* and raise the trim until the ragged underside is gone —
the preview shows the actual cut. Set the scale, or tap *Match real size*, say which
side you measured, and enter its length.

**Check.** Under *Ready to print?*, pick your printer. A green *Watertight* and *Fits
the build plate* mean the file will open in Bambu Studio without a repair prompt. If it
is too big, *Scale to fit* picks the largest size that fits. Holes in a scan usually
sit in the underside, so if the check finds any, raise the flat-base trim first.

**Export.** *Export 3MF* writes a 3MF package for Bambu Studio, PrusaSlicer or
OrcaSlicer, centred on the chosen printer's plate. *Export STL* writes a binary STL in
millimetres for any slicer. Files
land in `Exports` inside the scan's folder and are reachable from the Files app under
**On My iPhone → LiDAR Scan 3D**.

## Tips for good scans

- Bright, even, diffuse light. Hard shadows confuse photogrammetry.
- Matte, textured objects work best. Shiny, transparent or plain single-colour
  objects need a matte spray or powder to reconstruct at all.
- Put the object on a non-reflective surface that contrasts with it, with free space
  all around it. A grey object on a grey stand gets the stand boxed instead of the
  object.
- Objects from mug size to chair size work well. Below roughly 5 cm, detail is lost,
  and thin objects (a phone, a power bank) are at the limit of what the box
  detection picks up.
- Take plenty of photos: 60 or more. The 40 mm test cube was captured from 30 and its
  faces came out with 2–3 mm of bulge.

## How it works

Object Capture writes a textured **USDZ** in metres, Y-up. Everything downstream
works in a single convention: **millimetres, Z-up, centred on X/Y, resting on Z = 0**.
`MeshData.seated(vertices:indices:)` is the one place that establishes it, so every
operation that moves geometry ends there and exports always sit on the bed.

The **flat base** is a plane cut, not a vertex clamp — clamping would smear the lower
silhouette down rather than remove it:

1. Triangles straddling the cut plane are split, with winding preserved by a cyclic
   rotation of their vertices.
2. The rim edges left along the plane are chained into closed loops. Loops nested
   inside other loops are holes: a bowl or vase on a foot ring cuts into a ring, and
   its centre must stay open. Holes are bridged into the loop around them and the
   result is ear-clipped (`Sources/Geometry/CapTriangulation.swift`), so non-convex
   footprints — a U, a C, a bracket — are capped exactly rather than fanned across. An
   object that cuts into several pieces — two legs, a handle — gets independent caps.
3. Which loops are holes is decided by nesting, and the whole cap is wound to face
   downwards, rather than trusting rim direction.
4. A plane landing exactly on an existing vertex collapses triangles onto a line or a
   point. Those slivers and their zero-length rim edges are dropped; leaving them in
   breaks watertightness. Vertices are matched at micron precision, so anything within
   a micron of the cut hits this.

The cut is covered by `Tests/GeometryTests`, which checks that every edge is shared
by exactly two triangles in the same two directions, and that signed volumes match
analytic values. Sphere cuts (including planes landing exactly on vertex rings), a
two-legged object whose caps must stay independent, a ring whose hole must stay open, a
U-shaped block whose centre lies outside it, and an open mesh that the cut must not make
worse all run on every push. Because `Sources/Geometry` carries no UIKit
dependency, the tests compile the app's own source rather than a copy:

```sh
swift test
```

The app runs the same checks on every model it shows (`Sources/Geometry/PrintReport.swift`),
and `tools/check_stl.py` runs them against an exported `.stl` or `.3mf`. CI exports the
sample in both formats and audits them with it, reading the 3MF with Python's own
`zipfile` and XML parser rather than the app's code. Both compare vertices by
position at micron precision. Meshes are also welded that way on load, because Object
Capture splits a vertex wherever a texture seam runs through it, and those splits would
otherwise count as holes.

**Squaring up** (`MeshData.squaredUp()`) turns the loaded mesh about Z to the heading
with the smallest footprint rectangle. The smallest rectangle around a convex polygon
has one side along one of its edges, so only the directions of the footprint's convex
hull edges are tried. A footprint where no turn saves 1 % of the area (a vase, a
sphere) is left as it is, so round objects are not spun by noise.

**Orientation** is stored as a quaternion and always re-applied to the squared-up
mesh, so repeated turns accumulate in the quaternion and never in the geometry.
Quarter turns about X and Y generate all 24 axis-aligned orientations, so every side
is reachable.

### Releasing to the App Store

The build carries what App Review checks for, and CI fails if any of it goes missing
from the app bundle:

- an app icon (`Resources/Assets.xcassets`, a single 1024 × 1024 opaque PNG)
- a privacy manifest (`Resources/PrivacyInfo.xcprivacy`): no tracking, no collected
  data, and the two required-reason APIs used — reading scan folders' creation dates,
  and UserDefaults to remember the chosen printer
- `ITSAppUsesNonExemptEncryption = NO`, so uploads skip the export compliance question

Still to do under the publishing Apple Developer account:

1. Set `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` in `project.yml` to the
   account's own, then `xcodegen generate` and archive from Xcode.
2. In App Store Connect: screenshots (6.9" and 6.5" iPhone), description, keywords,
   support URL, privacy policy URL, and the privacy questionnaire — answer
   *Data Not Collected*, which matches the manifest.
3. Note for App Review that scanning needs a LiDAR iPhone (12 Pro or later). The app
   says so on other devices rather than failing, and *Try the sample scan* on the
   home screen shows the rest of the app on any iPhone.

### Project layout

| Path | |
|---|---|
| `Sources/LidarScan3DApp.swift` | App entry point and phase routing |
| `Sources/AppModel.swift` | Capture session, reconstruction, scan lifecycle |
| `Sources/CaptureView.swift` | Guided capture UI and live feedback |
| `Sources/ReconstructionView.swift` | Reconstruction progress |
| `Sources/ResultView.swift` | Preview, orientation, scale, flat base, export |
| `Sources/Geometry/MeshData.swift` | Mesh loading, squaring up, plane cut, STL/OBJ writers |
| `Sources/Geometry/CapTriangulation.swift` | Triangulates the flat base, holes included |
| `Sources/Geometry/PrintReport.swift` | Watertightness check shown before export |
| `Sources/Geometry/BuildVolume.swift` | Printer presets and the fit-to-plate calculation |
| `Sources/Geometry/ThreeMF.swift` | 3MF export, with the small ZIP writer it needs |
| `Sources/MeshDataPreview.swift` | SceneKit preview geometry (the only UIKit part of the mesh code) |
| `Sources/ScanFolder.swift` | On-disk layout of a scan |
| `Tests/GeometryTests/` | Geometry tests, run on macOS by `swift test` |
| `tools/check_stl.py` | Audits an exported STL or 3MF for printability |
| `Resources/` | App icon, privacy manifest and the sample scan |
| `tools/make_sample.py` | Generates the sample scan, `Resources/SampleVase.obj` |
| `project.yml` | XcodeGen spec — edit this, not the `.xcodeproj` |
| `Package.swift` | Builds `Sources/Geometry` alone, so CI can test it |

Each scan lives in `Documents/Scans/<name>/` holding `Images`, `Exports` and
`model.usdz`, plus `Checkpoints` while it is being reconstructed. Scans that never
produced a model (a failed or interrupted capture or reconstruction) cannot be resumed,
and are deleted rather than left to fill the device.

## Device testing

The first sessions on an iPhone Pro, with the app run from Xcode 27:

- **Scale is right; the reported size was not.** A 40 mm cube was reported as
  57.9 × 56.8 × 44.0 mm. Planes fitted to its faces measured 40.4 × 40.8 × 41.7 mm,
  and Object Capture's own USDZ had the same bounding box, so the app's processing was
  faithful. The cube simply sat 34° off the capture's heading. The model is now
  squared up on load: the same scan reads 45.7 × 42.5 mm, and what remains is
  surface bulge on a plain, low-texture object captured from 30 photos.
- **Crash when the capture box appeared** under Xcode: Metal API Validation
  rejecting RealityKit's shadow shader. Validation is now off in the scheme (see
  [Building from source](#building-from-source)).
- **Crash on *Flip object & scan the bottom*:** the session only accepts a flip while
  paused. Flip now pauses first. The fix follows the session's own error message and
  still has to be confirmed on the device.

To report a problem from a device, run the app from Xcode. On a crash, Xcode stops on
the failing line; send a screenshot of the stack on the left and the console at the
bottom. For a hang, press *Pause* in Xcode's debug bar first. Without Xcode, crash
reports are under *Settings → Privacy & Security → Analytics & Improvements →
Analytics Data*, as files named `LidarScan3D-…`. The capture state and feedback are
logged under the `com.alconstantin.lidarscan3d` subsystem and can be read in
Console.app with the phone connected.

## Known limitations

- **Early device testing.** A handful of scans have been through the app so far.
  Treat the defaults — particularly the 2% starting trim — as guesses to be tuned.
- **Watertightness depends on the input.** The plane cut preserves it, but cannot
  create it: a non-manifold scan produces a non-manifold STL. Object Capture meshes
  are not guaranteed clean, so a slicer may still complain.
- **Leans are not corrected.** The heading about the vertical axis is squared up
  automatically, and quarter turns fix a model lying on the wrong side, but a scan
  that leans by a few degrees stays leaning. An automatic levelling
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
- **The app icon is a placeholder**, generated rather than designed.

## License

Proprietary — all rights reserved. See [LICENSE](LICENSE). No use, copying or
distribution is permitted without a written agreement with the copyright holder.

Object Capture, RealityKit, SceneKit, ARKit and ModelIO are Apple frameworks, used under
Apple's terms; this notice covers the code and assets in this repository only.
