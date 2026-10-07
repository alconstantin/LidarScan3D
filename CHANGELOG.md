# Changelog

Version tags identify source snapshots. GitHub release assets are available only
after successful tagged builds. Device validation is tracked separately in
[TESTING.md](TESTING.md).

## Unreleased

- Updated README, installation instructions, audit publication status and project map.
- Added test plan, release guide and structured bug-report template.

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
