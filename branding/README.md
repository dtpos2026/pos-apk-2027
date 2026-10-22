# DT Food POS branding

| Path | What it is |
|---|---|
| `vector/*.svg` | **Source of truth.** Icon, round icon, adaptive foreground/background, monochrome. Edit geometry in `vector/dt_art.py`. |
| `icon/` | Rendered PNGs: 1024 master, 512 Play Store, adaptive layers, 2048 art for splash/feature graphic. |
| `../android-res/` | Android launcher resources (mdpi to xxxhdpi, adaptive XML). Copy into `android/app/src/main/res/`. |
| `animation/dt_splash_logo.json` | Lottie logo animation (800x800, 60 fps, 130 frames, transparent, 16 KB). |
| `animation/animated_splash_screen.dart` | Flutter splash that plays the Lottie and reveals the text. **Not compiled yet.** |
| `animation/splash_preview.mp4` | Browser-rendered preview of the full splash sequence. |
| `screens/` | Static splash and Play Store feature graphic (PNG). |

The Digital Target mark is four right triangles traced from the supplied logo (IoU 0.997 against the logo file), not freehand.

## Rebuild

```sh
python3 -I branding/vector/build_vector.py .          # SVGs + render job list
node branding/vector/render.mjs branding/vector/render_jobs.json   # PNGs via Chromium (Playwright)
python3 -I branding/animation/build_lottie.py .       # Lottie JSON
python3 -I branding/screens/generate_brand_assets.py <logo.jpg> .  # static splash + feature graphic
```

## Splash timeline (60 fps)

| Frames | Event |
|---|---|
| 4-34 | Receipt rises and fades in |
| 34-67 | DT mark triangles pop, one by one |
| 58-92 | Line items wipe in, then the total line |
| 60-90 | "Powered by Digital Target" fades in |
| 88-114 | Fork/knife badge pops |
| 92-128 | App name and tagline slide up |
| 112+ | Loading dots, until start-up work finishes |

Colours: brand purple `#3D096D` (measured from the logo), gradient `#5A1D96` to `#240341`, amber `#FFB547`, lavender `#CDB4F0`.

## Verification status

- SVG/PNG icon renders: viewed in Chromium. Not yet checked on an Android device or emulator.
- Lottie: plays correctly in lottie-web (Chromium). Not yet tested in Flutter's `lottie` package.
- `animated_splash_screen.dart`: never compiled (no Flutter SDK available). Run `flutter analyze` first.
- Android 12+ shows its own system splash (static icon on a solid colour) before the Flutter splash; configure `windowSplashScreenBackground` as `#3D096D` when the Android project exists.
