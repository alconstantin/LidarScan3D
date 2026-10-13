# Changelog

Version tags identify source snapshots. GitHub release assets are available only
after successful tagged builds. Device validation is tracked separately in
[TESTING.md](TESTING.md).

## Unreleased

- Nothing yet.

## 1.4 — 13 October 2026

Tag: `v1.4`; local app build: 5.

- Added Fill small holes: boundary loops of up to 300 edges are closed with
  ear-clipped patches wound like the surrounding surface. Saved in the recipe;
  recipes from earlier builds open with it off.
- Not yet validated on a device; see S10 in TESTING.md.

## 1.3 — 13 October 2026

Tag: `v1.3`; local app build: 4.

- Added Lay flat: rests the model on its largest flat outer face at any angle,
  squares the footprint, and cycles through other flat faces. Saved like other turns.
- Added wall-thickness analysis: sampled inward ray casts, a minimum-wall picker,
  a thin-area warning that follows the print scale, and a yellow thin-wall overlay.
- Updated README, installation instructions, audit publication status and project map.
- Added test plan, release guide and structured bug-report template.
- Not yet validated on a device; see S08/S09 in TESTING.md.

## 1.2 — 7 October 2026

Tag: `v1.2`; source: `0c4fff8`; local app build: 3.

- Added scan thumbnails with capture-photo fallback.
- Added problem-edge/face highlighting and X/Y/Z preview markers.
- Added bounded report examples for holes, winding, intersections and inward shells.
- Cached interrupted photo counts; refreshed titles/storage around navigation/export.
- Rejected invalid preparation recipes before processing.
- Tagged CI builds derive their app version from the pushed tag.
- Validation: 65 tests, unsigned iPhoneOS Release build and independent sample
  STL/3MF topology checks passed locally. New visuals require physical testing.

## 1.1 — 7 October 2026

Tag: `v1.1`; source: `473068a`; local app build: 2.

- Fixed fragment-removal limits and bounds affected by unused vertices.
- Added shell/intersection surface checks and more accurate verdict language.
- Saved preparation/calibration with reset and original comparison.
- Added cancellable serial preparation with cached stages.
- Remembered reconstruction cancellation during setup; retained interrupted input for retry.
- Fixed flip-pass counting and zero-photo stall feedback; required 20 photos to build.
- Added custom printer dimensions, calibration validation and camera recovery guidance.
- Added scan names, storage display, optional source-photo removal and app/build label.
- Added direct triangle OBJ sample loading and regression coverage.
- Validation: 58 tests and unsigned iPhoneOS Release build passed locally.

## 1.0

Initial tagged version. See the tag's repository history for its exact contents;
features committed later on main are not automatically part of this tag.
