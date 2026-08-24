# Research Notes: Minecraft Java AOT for iOS

## Date: 2026-08-24

## Executive Summary

Attempting to compile Minecraft Java Edition as a GraalVM Native Image for iOS (no JIT required), targeting TrollStore on real device.

**Status:** Research complete, plan approved, implementation starting.

## Sources Consulted

1. `plan/no-jit-01.md` — original feasibility study (Vietnamese)
2. GluonHQ docs (docs.gluonhq.com) — GluonFX plugin 1.0.29, Substrate 0.0.69
3. oracle/graal#8776 — iOS platform status: Oracle does NOT officially support it
4. hpi-swa/native-minecraft-server — proven MC server AOT with GraalVM
5. LWJGL 3.3.3+ release notes — Native Image compatibility confirmed (#875)
6. utopia-rise/ios-graal-jdk-21 — alternative iOS native-image path (godot-kotlin)
7. gluonhq/graal releases — Gluon's custom GraalVM builds

## Key Technical Findings

### GraalVM iOS Support
- Oracle explicitly says: "we don't support iOS platform and we currently do not have any plans to support it"
- iOS support relies on Gluon's static Java libraries from `graalvm/labs-openjdk`
- CAP cache values must match Gluon's builds — mixing versions causes errors
- gluon-22.1.0.1-Final is the referenced stable build (JDK17)

### GluonFX Plugin (1.0.29, June 2026)
- Active development, substrate 0.0.69
- Supports iOS arm64 and x86_64
- Min iOS: 12 (substrate 1.0.29 bump)
- Produces .app bundle for iOS
- Maven plugin: `gluonfx:build`, `gluonfx:nativerun`, `gluonfx:simrun`
- Works for plain Java (not just JavaFX)

### Minecraft AOT Precedents

#### Server (hpi-swa/native-minecraft-server)
- MC 1.18.2 server → native executable successfully
- Key flags:
  ```
  --no-fallback
  -H:ConfigurationFileDirectories=configuration/
  --enable-url-protocols=https
  --initialize-at-run-time=io.netty
  -H:+AllowVMInspection
  --initialize-at-build-time=net.minecraft.util.profiling.jfr.event
  ```
- Reachability metadata published in repo
- Issue #6: MC 1.21.3 PaperMC also works with manual JFR patch
- `.mcassetsroot` glob fix needed: replace `data/.mcassetsroot` → `data/**`

#### Client (anecdotal)
- Community member on hpi-swa issue claims MC 1.17.1 client compiled as native-image
- Desktop only (not iOS)
- LWJGL + OpenGL context needed for full graphics

### LWJGL 3.3.3+ Native Image
- Official support added in 3.3.3 release
- LWJGL repo includes `build_native_image.sh` and `config/cli/classpath.args`
- `chirontt/lwjgl3-helloworld-native` — verified working example
- Build flags: `--initialize-at-run-time=org.lwjgl`, `-march=compatibility`

### Reflection & Dynamic Features
- Minecraft uses reflection heavily (serialization, event binding, mod loading)
- DataFixerUpper uses complex generic types that break native-image if unconfigured
- native-image agent captures ~340+ reflective accesses in a single play session
- Must run agent across multiple scenarios (menu, world load, options, multiplayer)
- Obfuscated code: official Mojang mappings allow remapping to named before agent run
- tiny-remapper (FabricMC) handles obf→named mapping

### Native Image Build Parameters (from precedent)
- Heap: `-R:MaxHeapSize=2g` (server), `3g` (client)
- Classpath: all MC libraries + remapped client/server jar
- Main class: `net.minecraft.client.main.Main` (named) or `net.minecraft.server.Main` (server)
- Resources: `-H:IncludeResources="assets/.*|data/.*"`
- Time: 20-90 minutes depending on classpath size and config

### Performance Characteristics
- StackOverflow: native image up to 5x slower than JIT in some benchmarks
- Startup: native image near-instant vs JVM seconds
- Memory: native image significantly lower (no JVM heap overhead)
- iOS device: weaker CPU than desktop → AOT may be further disadvantaged
- But: AOT = no JIT needed = valid on App Store (legal path)

### Our Project's Assets
- `liblwjgl*.dylib` (arm64 iOS): liblwjgl, liblwjgl_opengl, liblwjgl_stb, etc.
- `libopenal.dylib` (arm64 iOS)
- `libEGL.framework`, `libGLESv2.framework` (MetalANGLE)
- `libMoltenVK.dylib`
- `libgl4es_114.dylib`
- 3 LWJGL versions vendored: 3.3.3, 3.3.6, 3.4.1
- Full packaging pipeline for TrollStore (.tipa)

### Environment (as of 2026-08-24)
- macOS 15.7.7, Xcode 26.3
- Only JDK 8 (Homebrew) installed — need Gluon GraalVM 17+
- No Maven/Gradle installed
- No iOS simulator available (hardware constraint)

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| GluonFX plugin can't inject extra dylibs | Fallback: manual substrate API or direct native-image + clang link |
| Reflection missing paths → runtime crash | Agent capture + manual crash-log iteration (hpi-swa approach) |
| LWJGL iOS fork incompatible with native-image | JNI-config handcraft; rebuild LWJGL with --features for GraalVM |
| Performance too low for playable FPS | Accept for POC; optimize GC, reduce heap, profile hotspots |
| Xcode 26.3 SDK mismatch with substrate | Pin `--target-sdk-version`, manual link fallback |
| Mojang EULA prohibits distribution | Private research only, no public release, jars not committed |

## Legal Note

Mojang EULA prohibits distributing modified client/server binaries. This project is:
- Private research only
- Using only publicly available data (Mojang piston-meta for jar download)
- No jars/assets committed to repository
- No public distribution planned

## Decision Points

1. **After t02:** Can GluonFX handle MC's classpath size? If not, fallback to manual link.
2. **After t05:** Server AOT bootable? If yes → proceed to client. If no → debug configs.
3. **After t07:** Does LWJGL+MetalANGLE work on device? If no → investigate renderer path.
4. **After t08:** Is title screen reachable? If yes → tune performance. If no → more agent configs needed.
