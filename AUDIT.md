# LidarScan3D audit — 7 October 2026

Reviewed commit: `87c7063e4454844c1703ef0a4bb905078a10f86f`.
Scope: capture/reconstruction state, scan storage, result controls, geometry processing,
STL/OBJ/3MF export, tests and CI. This is a source audit with local executable
geometry probes; physical-device capture and slicer import were not exercised.
The findings below describe the audited baseline. See the remediation status at the end
for the subsequent implementation.

## Findings, in priority order

### 1. High: fragment cleanup removes more than its advertised limits

`Sources/Geometry/MeshData.swift:398` uses `max(largest * 0.005, 25)`.
The UI and comment promise removal only below both 0.5% of the main surface and
25 mm². Using the larger threshold allows removal when only one condition holds.

Executable examples using the current implementation:
- A 100 mm cube plus a separate 4 mm cube: the 4 mm cube has 96 mm² surface area,
  yet cleanup removes all 12 of its triangles.
- A 20 mm cube plus a separate 2 mm cube: the smaller part is 1% of the main
  surface, yet cleanup removes it.

Fix: use the smaller threshold, test both threshold boundaries, and keep removal
reversible. The original scan is preserved today, but an exported model can omit
an intentional part.

### 2. High: the green print-readiness verdict overstates validation

`Sources/Geometry/PrintReport.swift:49` counts edge usage and sums signed volume
across the entire mesh. It does not test triangle intersections or verify the
orientation of each separate closed component. `Sources/ResultView.swift:425`
turns those limited checks into “Watertight: slices without repair”.

Executable examples both returned `isWatertight == true`:
- Two closed cubes whose surfaces intersect.
- A large outward-facing cube plus a spatially separate inward-facing cube.
  The large positive volume hides the smaller negative volume.

Fix: validate orientation by connected shell, add intersection checks with a
spatial acceleration structure, and describe the checks actually performed.
Passing topology checks alone does not guarantee a usable print; thin walls,
overhangs and supports require additional evaluation.

### 3. Medium: unused vertices can corrupt dimensions and calibration

`Sources/Geometry/MeshData.swift:122` retains every welded vertex;
`seated` at line 132 includes them all in the bounding box, even when no triangle
references them. Removed collapsed triangles can also leave unused vertices.

Executable example: a 20 mm cube with one unused vertex at `(500, 500, 500)`
reports `510 × 510 × 500 mm`. The triangle surface remains a 20 mm cube.
This can corrupt centering, automatic orientation, ruler calibration and
scale-to-fit, causing an incorrectly sized print.

Fix: compact vertices against surviving indices before seating and measuring.
Reject a mesh if welding leaves no triangles. Test an unused outlier and
vertices belonging only to collapsed triangles.

### 4. Medium: preparation and calibration disappear when a scan is reopened

`Sources/ResultView.swift:30` onward stores orientation, scale, cleanup,
smoothing and trim in view-local `@State`. There is no saved preparation recipe
or restore step. Returning home and reopening the scan resets these choices.
Previously exported files survive, but the prepared preview cannot be reproduced
without manually repeating the work.

Fix: atomically persist a versioned preparation recipe next to each original
model, restore it on open, and provide an explicit Reset preparation action.

### 5. Medium: Cancel can be lost during reconstruction preparation

The reconstruction screen appears at `Sources/AppModel.swift:182`, before
`PhotogrammetrySession` initialization completes and the session is adopted at
line 207. `SessionBox.cancel()` at line 277 only cancels an existing session.
If the user taps Cancel during initialization, the nil session means the
request is discarded and processing can subsequently begin.

This is established by the source execution order; the timing window has not
been measured on a phone.

Fix: retain cancellation intent through initialization and check it before
processing; reset it per job. Test cancellation before and after adoption.

### 6. Medium: superseded mesh work continues consuming resources

Each edit launches an untracked detached job in `Sources/ResultView.swift:501`.
The generation check at line 522 prevents an older result from replacing a
newer one, but occurs after all processing, scene construction and reports.
Rapid changes can therefore run multiple full mesh pipelines simultaneously,
even after leaving the result view.

The code establishes redundant work; an actual memory termination was not
reproduced.

Fix: use a managed task with cooperative cancellation, debounce rapid edits,
reuse unchanged pipeline stages and stop work when the view leaves. Benchmark
time and peak memory on real scans, especially the oldest supported iPhone.

### 7. Low: flipped capture passes are undercounted

`finishFlip()` increments `scanPasses` and returns to detection for a new box.
The next Start capture action (`Sources/CaptureView.swift:77`) unconditionally
resets the counter to 1. The persisted quality summary loses earlier passes.

Fix: initialize the counter only for the initial pass and preserve it through
flip detection. Test the complete initial-pass → flip → detection → capture flow.

### 8. Medium: the stall warning misses capture with zero photos

`Sources/CaptureView.swift:304` requires `shots > 0` to flag a stall.
A capture that never produces its first photo can remain stalled indefinitely
without this warning. Finish early is still offered with no minimum-photo
validation, potentially leading straight to failed reconstruction.

Fix: track time since capture started even at zero shots, distinguish no initial
capture from a later stall, show relevant live feedback, and validate that usable
input exists before offering reconstruction.

## Other product improvements

1. Add a resumable scan lifecycle. Failed reconstruction currently deletes the
   scan via `AppModel.fail`; startup cleanup also deletes old incomplete scans.
   Offer retry for recoverable failures and show interrupted work explicitly.
2. Add scan names, thumbnails, storage usage and optional source-photo cleanup.
   Finished scans retain photographs after checkpoints are deleted.
3. Add custom printer dimensions. “Other printer” currently disables fit checking.
4. Report calibration limits explicitly. Requested scale is silently clamped to
   10–500% in `ResultView.applyCalibration`, so the requested dimension may not be
   achieved. Validate input and explain the achievable range.
5. Add a visible app/build identifier and derive versions from releases.
   `project.yml:23` fixes every build to version 1.0, build 1, making installed
   versions difficult to identify and requiring changes for distribution updates.
6. Add an accessible preview inspector: axis labels, dimension overlays, highlighted
   holes/problem faces and an original/prepared comparison. Verify Dynamic Type,
   VoiceOver and small-screen capture layout on hardware.
7. Expand automated coverage to app state and preparation persistence. Current
   automated tests cover geometry, not camera permission denial, cancel races,
   app interruption, retry, reopening prepared scans or navigation during jobs.

## Validation performed

- Existing suite: 44 tests executed; 41 passed, 3 failed. All three failures were
  bundled-sample ModelIO reads returning `noGeometry` after logging “Unable to
  issue extension for path”. This environment does not establish whether those
  reads succeed on an iPhone or in unrestricted CI.
- Temporary executable probes compiled the actual geometry source and reproduced
  the cleanup, misleading print verdict and unused-vertex examples above.
- Unsigned Release iOS build attempted. It failed with unavailable/malformed Swift
  macro plugin responses and CoreSimulator access/service errors. A successful
  production build is not confirmed by this audit; the errors also do not prove
  that the app source fails in an unrestricted build environment.
- No physical-device capture, interruption testing, actual slicer import, or print
  was performed. No fresh remote CI status was obtained.

## Recommended order

First correct cleanup limits, mesh bounds and the print-readiness verdict. Next
persist preparation and fix cancellation/job ownership. Then strengthen capture
diagnostics and recovery. Finally validate real scans on hardware and import the
exports into Bambu Studio and another slicer before adding larger features.

Use measured acceptance criteria: a calibrated reference object's exported
dimensions agree with the app within rounding; preview and export use identical
prepared geometry; reopening restores edits; cancellation works during preparation;
rapid edits remain within measured memory limits; invalid shells are not marked
ready; interrupted scans have a clear recovery or discard path.


## Remediation status — 7 October 2026

Implemented locally after the audit:

- Fragment cleanup now requires both advertised limits. Regression tests retain
  the 96 mm² part and the part exceeding the relative limit.
- Seating compacts surviving surface vertices; unused vertices no longer alter
  size, centering, calibration or build-plate fit. Empty/invalid loaded meshes
  are rejected. The plain triangle OBJ sample now has a direct validated reader.
- Surface reports check signed volume per connected shell and triangle intersections
  using a bounded BVH. Incomplete checks and negative shells require review.
  UI and export-checker language no longer promise repair-free slicing.
- Versioned preparation recipes save atomically, restore on reopening, and support
  explicit reset. Corrupt/unknown recipes are reported rather than overwritten.
- Mesh preparation runs serially with cached prefixes, debounce, cooperative
  cancellation and stale-result protection. Leaving the screen cancels work.
- Cancellation survives reconstruction initialization. Failed/cancelled reconstruction
  retains photos. Interrupted scans can be retried or explicitly deleted.
  Reconstruction writes a temporary model and publishes it only on completion.
- Flip pass counts survive redetection. The watchdog detects zero-photo stalls
  and suspends during pauses. Building requires at least 20 photos.
- Added camera permission recovery guidance, custom printer dimensions, explicit
  calibration validation, original/prepared preview comparison, scan naming,
  storage usage and confirmed photo removal that preserves models and edits.
- App version/build is visible. Local version is 1.1 (2); CI assigns build numbers
  from its run number.

Validation: 58 automated tests pass, including 14 new audit regressions. Sample STL
and 3MF exports pass the independent Python topology check with matching dimensions.
The generated unsigned Release iOS build succeeds with temporary module caches and
Swift frontend macro sandbox disabled for the local build invocation. That temporary
compiler flag is not saved in the project or CI. Simulator service warnings remain
in this restricted environment, but the iPhoneOS build completes.

Remaining validation and improvements:
- Install on a physical iPhone and test camera denial/recovery, flip capture,
  cancellation during setup, background interruption, retry, persistence and rapid
  edits on a large real scan. No install or device session was performed here.
- Import actual scan exports into Bambu Studio and another slicer; measure and print
  a calibrated reference object.
- Measure peak memory and processing time on the oldest supported hardware.
- Intersection checks exclude pairs sharing a welded vertex and have a work budget;
  they are not a complete geometric validity proof. Negative shells can represent
  valid internal cavities and are deliberately shown for review rather than repaired.
- Thumbnails, selected-face issue overlays, wall thickness analysis, automatic mesh
  repair and full VoiceOver/Dynamic Type device validation remain future work.


## Follow-up improvements — preview inspection and browsing

Implemented after commit `473068a`:
- Added lightweight scan-list thumbnails using a cached 256 px rendered model image
  or a downsampled source photograph. Browsing does not load full 3D models.
- Reports retain bounded examples of problem edges and triangles in the exact
  prepared mesh. An optional overlay marks holes/inconsistent edges in orange and
  intersections/inward shells in red, including occluded problems. Generated
  previews include X/Y/Z markers. Overlays do not change exported geometry.
- Interrupted photo counts are loaded off the main thread rather than repeatedly
  reading storage during view rendering. Scan titles refresh when returning from
  a rename. Export completion refreshes storage without presenting a share sheet
  after leaving the result screen.
- Preparation workers reject malformed recipes before rotation and preserve their
  prior cache. Thumbnail scenes are privately constructed so offscreen rendering
  never shares a mutable scene with the interactive preview.
- Local app version is now 1.2 (3).

Validation: 65 tests pass, including 7 new inspection regressions covering actual
vertex references, flipped edges, texture seams, intersections, inward shells and
invalid recipe rejection. Unsigned iPhoneOS Release build and independent sample
STL/3MF export topology checks pass. Thumbnail rendering, overlay readability,
axis labels and accessibility still require visual verification on an iPhone;
these changes have not been installed on hardware or pushed to GitHub.
