# ARCHi Unity companion and play preview

This Unity source project presents KIN and local practice alongside ARCHi's native desktop direction. Native Swift assistance, memory and saved companion development remain the existing owners. The preview displays **Port preview · not connected to saved companion**. It adds no assistant client, native profile writer, evolution grant, creator entitlement or marketplace.

## Source and prerequisites

The project is pinned to **Unity 6000.5.4f1** with the Built-in Render Pipeline and legacy Input Manager. The Mac standalone module is required for its current ARM64/Mono development build. Unity itself is an external prerequisite, not bundled or relicensed by ARCHi.

The starting project was adapted from an existing local ARCHi presentation pilot. [Source provenance](source-provenance.json) records historical copied inputs and the public PNG sanitation mapping. Pearl/Lumen reference scenes remain source assets but are excluded from the port's player build. The KIN and Quotient runtime images reuse the native project's existing artwork, with [KIN provenance](Assets/Resources/KIN/provenance.json) and [branding provenance](Assets/Resources/Branding/provenance.json).

The optional embedded Coplay 10.0.0 Editor package retains its [MIT notice](Packages/com.coplaydev.unity-mcp/LICENSE.md). The project no longer depends on a private sibling output directory to find that package. No package installation or model download is performed by the build helper. Unity may resolve its declared package dependencies when you open the project.

Keep all source `.meta` files. Generated Library, Temp, Logs, UserSettings, Builds and IDE state are excluded. The startup scene and baked PanelSettings/PanelTextSettings/theme are included: their text dependencies are required by the standalone UI Toolkit player.

## Behavior

- Companion shows the source KIN artwork and explicit Seed/First Light appearance previews. Its Seed reference badge stays visible and does not follow the pointer.
- Items offers the bundled Focus Staff with session-only equip/unequip and a bounded cue. Stop, Quiet and Reduce Motion retain a still fallback.
- Practice adapts the retained Broken Relay rules into a pure C# session domain. Legal actions, retry and temporary focus cues do not save game history or award growth.
- The header uses the existing Quotient mark. A copied logo or bundled item does not claim authenticated ownership or creator endorsement.

Runtime source is [DesktopPort.cs](Assets/ARCHi/Runtime/DesktopPort.cs) and [RelayPractice.cs](Assets/ARCHi/Runtime/RelayPractice.cs). The runtime does not use WebViews, network requests or local model clients. A future native/Unity handoff requires a separate reviewed contract through the current owners.

## Build and check

From the repository root, with source writers finished and no other Editor using this project:

    ./script/build_unity_port.sh

The script expects the pinned Editor under the standard Unity Hub installation path. Alternatively invoke that Editor with the project path, Mac build target and `-executeMethod ARCHiPortBuild.BuildMac`. The Editor helper validates the bundled asset hashes, startup scene/configuration and pure Relay rules before building. Existing output apps are preserved; repeat builds accept a new output path beneath the evidence directory through `-archiBuildOutput`.

`ARCHiPortBuild.Prepare` sets up absent startup assets without overwriting an authored scene. `ARCHiPortBuild.Validate` checks existing project state. All entry points reject the wrong project/version, Play Mode, an active build and unsaved scenes. The player uses the baked UI assets rather than a runtime-created default text panel.

For a separate explicit programmatic runtime check, launch a fresh built player with:

    -archiPortSmoke /absolute/new-output-directory -logFile /absolute/player.log

The runner refuses an existing output directory, enables background execution only for the smoke run, exercises the shared UI actions, captures four framebuffer images and writes JSON before exiting 0/1. It checks the 1280×820 and 900×640 layouts. Normal startup does not perform these actions or write a smoke receipt. These are programmatic runtime checks, not human pointer or VoiceOver acceptance.

## Qualification

This exported source is prepared for verification. Earlier local development builds and fixtures do not establish that this exported revision is qualified. See [public validation](../../docs/ALPHA_VALIDATION.md) for its current evidence status.

The preview uses static existing artwork, a stationary Seed reference and session-only state. Native assistance/memory handoff, retained cross-surface state, complete 3D embodiment, full battle-engine integration, accessibility, long-session performance, notarized distribution and marketplace services remain subsequent work.
