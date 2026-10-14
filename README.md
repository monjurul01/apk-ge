# AI Image Studio

Text-to-image generator for **Windows** and **Android**, built with Flutter.

> **Version 2.0 replaced the image backend.** Cloudinary's Image Generation
> API has been removed entirely. The app now targets Dola
> (<https://www.dola.com>) using the signed-in user's own browser session.
> See [Image backend](#image-backend) for the current state and the
> trade-offs involved.

## Features

- **Studio** - compose a single prompt and review the result full-size on a
  two-pane layout, with pan/zoom and an inline inspector.
- **Batch** - paste one prompt per line and run the queue sequentially, with
  a cooldown between jobs so a consumer account is less likely to be
  throttled.
- **Gallery** - everything generated this run, with adjustable grid density,
  bulk save, and a phone-mockup preview (wallpaper / lock / home / chat /
  call) for checking a wallpaper in situ.
- **Local export** - resizing and cropping run on-device through the `image`
  package. Presets cover the original pixels, 1620x2880 and 2000x2000.
  Exports work offline and no longer depend on a delivery URL staying alive.
- **Secure session storage** - credentials live in OS secure storage
  (Keychain / Keystore / Windows Credential Manager).

## Image backend

Dola is a consumer AI assistant with **no public API**, so this is worth
understanding before relying on it.

Its frontend loads ByteDance's `webmssdk` anti-abuse SDK and applies it to
exactly the request paths that matter - `/alice`, `/samantha`, `/passport`
and `/chat/completion`. Every generation request therefore carries a
per-request device signature on top of the session cookies. Re-implementing
that signing in Dart would mean defeating a bot-detection control, which
this app deliberately does not do.

The design instead runs **the real Dola page inside an embedded WebView**
with the user's own session restored into it. Dola's own JavaScript signs
its own requests; the app only types the prompt, presses send and reads the
resulting image. Cookies are captured from a desktop browser and pasted into
Settings.

Known costs of this approach:

- Driving a consumer account from an app is **against Dola's terms of
  service**. The account can be throttled or banned.
- Dola **geo-restricts** access ("not available in this country or region").
  Where it is blocked, no session will make it work.
- Reading results out of a web transcript is **inherently brittle**. Any
  Dola redesign breaks it, which is why every CSS selector the driver uses
  is editable in **Settings -> Advanced** rather than compiled in.
- The chat product exposes **no seed, aspect ratio, resolution or format
  control**, and no image-to-image editing.

Because of that last point the previous wallpaper *set* pipeline is gone.
It built 24-hour / battery / dual sets by chaining image-to-image edits off
a hidden anchor frame at a fixed seed to keep the subject identical across
variants. Nothing in a chat product supports that, so Batch is now an honest
one-prompt-one-image queue. The prompt-set vocabulary is still in
`models.dart` so the sets can return if a seeded-editing backend is wired
in.

### Swapping the backend

Every screen depends only on the `ImageGenerator` interface in
`lib/core/generation.dart`. Pointing the app at an official API - Replicate,
fal.ai, Together, Gemini - means writing one class and changing one return
statement in `lib/core/generator_factory.dart`. Nothing else in the app
knows which backend is in use.

## Project layout

```
lib/
  main.dart                   app entry; dark-only MaterialApp
  app_theme.dart              "Darkroom" design tokens + theme
  models.dart                 prompt-set vocabulary (arcs, variants)
  secure_store.dart           secure session storage + preferences

  core/
    generation.dart           GenerationResult, errors, ImageGenerator
    generator_factory.dart    the only place a concrete backend is named
    export_presets.dart       on-device resize / crop / re-encode
    image_io.dart             save, share, filename rules

  dola/
    dola_session.dart         cookie model, parsing, validation
    dola_selectors.dart       overridable CSS selectors + timeouts
    dola_js.dart              in-page driver script
    dola_client.dart          WebView driver - NOT YET PRESENT, see below

  screens/
    app_shell.dart            nav rail / bottom bar + session gallery
    studio_screen.dart        single-prompt composer
    batch_screen.dart         sequential prompt queue
    gallery_screen.dart       run gallery + device preview
    settings_screen.dart      session, export, selectors

  widgets/
    studio_widgets.dart       Panel, SectionLabel, NoticeBar, EmptyState
    device_mockup.dart        phone mockup preview (byte-backed)

  gemini_api.dart             prompt/metadata authoring (not generation)
  gemini_web.dart             cookie session for Gemini Web
  distribute.dart             upload targets for generated sets
  zip_export.dart             zip bundling
```

## Design

Version 2.0 is a full visual rebuild. The previous seeded-indigo Material
theme with light/dark switching is replaced by **Darkroom**: a single
near-black canvas (`#0B0B0F`), one amber accent (`#F5A524`), flat panels
drawn with hairline borders instead of shadows, and a tighter radius and
spacing scale. There is no theme toggle - a neutral dark canvas is the only
honest background to judge generated colour against.

Navigation moved from an AppBar with pushed routes to a persistent
navigation rail (desktop) / bottom bar (phone), so switching between
composing, queueing and reviewing never loses state.

## Build

```bash
flutter pub get
flutter run -d windows     # or: flutter run -d android
flutter test
```

CI builds Windows and Android artifacts; see `.github/workflows/build.yml`.

## Outstanding work

`lib/dola/dola_client.dart` - the WebView driver that ties the session,
selectors and driver script together - is **not in this tree yet**. Until it
is added and returned from `createDolaGenerator()`, the app builds and runs
but every generation fails with "No image backend is connected yet", which
Settings states plainly.

Everything else the driver needs is in place: session storage and cookie
parsing, the overridable selector config, the in-page driver script, the
error taxonomy it maps onto, and the queueing and export paths that consume
its results.
