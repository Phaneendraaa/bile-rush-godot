# Bike Rush 3D

Superbike racing for Android, built with **Godot 4.7** (Mobile renderer, Jolt physics).
Everything is procedural: tracks, terrain, trees, textures, bike and rider models, and engine sound. The APK contains no image or audio assets.

**Download:** grab `BikeRush3D.apk` from the latest release on the [Releases](../../releases/latest) page, open it on your phone and allow the install.

## Features
- **Physics:** two ray-cast wheels with tyre profile, progressive suspension, slip-angle and camber-thrust tyre model with a friction circle, a 1000 cc torque curve, a 6-speed gearbox, aero drag, front/rear brakes and weight transfer. Wheelies and stoppies happen naturally.
- **Rider:** a lean controller handles balance (it stands in for counter-steering). The rider tucks and hangs off in corners, posed with IK. In a crash the rider becomes a ragdoll.
- **Rider aids:** traction control, ABS, wheelie control and lean limit. *Full assist* also keeps your lane when you're not steering.
- **AI:** 5 rivals use the same physics, with racing lines, speed planning from braking distance, and overtaking.
- **Tracks:** Green Valley, Sunset Coast and Desert Canyon. Each has a custom sky, fog, terrain shader, animated grass and trees, barriers, a grandstand and brake markers.
- **Controls:** on-screen ◀ ▶ / GAS / BRAKE, or tilt steering, plus 3 camera views.
- **Privacy:** no internet permission, no tracking, nothing stored.

## Build
Every push to `main` runs `.github/workflows/build-android.yml`:
1. Import the project with Godot 4.7.2 headless.
2. Autotest: a full 6-bike AI race on every track. It fails the build on script errors or if bikes can't finish.
3. Render test: real Mobile renderer on software Vulkan, with screenshots saved to the `ci-logs` branch.
4. Export a signed release APK and publish it as a GitHub Release.

Locally: open the folder in Godot 4.7, then Project → Export → Android.
