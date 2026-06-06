# iOS unsigned build workflow

This repository includes a GitHub Actions workflow that builds **unsigned iOS outputs** for inspection and CI verification.

## What it produces

The workflow tries to generate and upload:

- `Hermes_IOS.xcarchive`
- extracted app bundle under `exported-app/`
- `Hermes_IOS-unsigned.ipa`
- simulator / archive logs and status files

Artifact name:

- `ios-unsigned-outputs`

## What it does *not* guarantee

This workflow does **not** sign the app. That means:

- the generated `.ipa` is mainly for structure/build verification
- it is **not expected** to install on a physical iPhone as-is

## Trigger

Run manually from GitHub Actions:

- workflow: `Build iOS unsigned outputs`

## Useful status files inside the artifact

- `sim-exit-code.txt`
- `archive-exit-code.txt`
- `ipa-status.txt`
- `build-sim.log`
- `archive.log`

## Current known behavior

At the current stage, the produced app bundle is a very small native shell for a remote-webui style client, so output size may be much smaller than a traditional fully self-contained iOS app.
