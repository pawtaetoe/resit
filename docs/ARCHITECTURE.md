# reSIT architecture

reSIT follows Flutter's recommended app architecture (the [Flutter app architecture guide](https://docs.flutter.dev/app-architecture)): a **data layer** that talks to the outside world and a **UI layer** that shows it, with plain **domain models** passed between them. State and dependency injection use [Riverpod](https://riverpod.dev).

## Folders

```
lib/
  main.dart              starts the app (and nothing else)
  app/                   the app shell: phone tabs, desktop sidebar, theme, app lock
  core/                  shared by every feature
    auth/                session controller (automatic sign-in), app lock
    network/             the HTTP client: cookies, redirects, timeouts, host checks
    storage/             encrypted storage (secure_storage, private_store)
    ui/                  theme, error messages
    widgets/             shared widgets (cards, bars, charts, sign-in gate)
    providers.dart       app-wide providers (storage, network, sign-in, tabs)
  sites/                 one folder per SIT system: the code that talks to it
    adfs/                SIT sign-in (fs.singaporetech.edu.sg) and MFA
    in4sit/              in4SIT (PeopleSoft): timetable, exam results
    xsite/               xSiTe (Brightspace): courses, content, activities
    rbs/                 Room Booking System
    sit_website/         the public academic calendar page
  features/              one folder per part of the app
    <feature>/
      domain/            the feature's models and pure rules: no I/O, no Flutter
      data/              caches and saved copies (repositories)
      ui/                screens and widgets
      <feature>_providers.dart   wires the feature's services, data and state
```

## The layers

| Layer | Folder | Does | Must not |
| --- | --- | --- | --- |
| Site services | `sites/<site>/*_service.dart` | Make the HTTP requests to one SIT system | Know about screens, or cache |
| Site parsers | `sites/<site>/*_parsers.dart` (or functions next to the service) | Turn that system's HTML or JSON into domain models, checking each value's type | Make requests |
| Domain | `features/<feature>/domain/` | Hold the app's data types and pure rules (e.g. the weekly room quota, what's due soon) | Import `sites/`, `data/`, `ui/` or Flutter widgets |
| Data | `features/<feature>/data/` | Keep saved copies (encrypted) and decide when to ask the site again | Build widgets |
| UI | `features/<feature>/ui/` | Show state and pass user actions on | Make requests or parse replies |

Dependencies point one way: **ui → data → sites → domain**, and everything may use `core/`. `core/` never imports from `features/`. A rule like this is easy to check: `grep -rn "package:resit/features" lib/core` should print nothing.

## Rules

- **One site, one folder.** If code builds a URL for an SIT system, it belongs in that system's `sites/` folder. Each site has one base address, and requests only ever go to that host (see `LmsService.onXsite`).
- **Parse defensively.** SIT's replies are untrusted input. Parsers check types (`is String`, `is num`) instead of casting, give a safe default for a missing field, and drop rows they can't read rather than crashing.
- **Models are plain.** Domain models are immutable data with derived getters. Reading a site's format (`fromJson` for Brightspace or RBS) is done by the site's parser, not by the model.
- **Secrets stay in `core/storage`.** Passwords, MFA secrets, cookies and personal data are only stored through `SecureStorage` or `PrivateStore` (encrypted), never `SharedPreferences`.
- **Every screen that loads data handles loading, error and offline** (a saved copy with its age where one exists).

## Testing

- Parsers and domain rules: unit tests with saved replies (`test/`).
- Services: tests against a fake server (`MockClient`) that checks the exact requests sent.
- Screens: widget tests with providers overridden.
- `tool/screenshots/` renders the README screenshots from demo data.

## Next steps

The reorganisation above is the first step. Next, one feature at a time:

1. **View models (MVVM).** Screens that load data themselves (`ConsumerStatefulWidget` with loading and error fields) move that logic into a view model (a Riverpod `Notifier`) that exposes one immutable state and named actions; the screen only draws it.
2. **Repository interfaces.** Each feature's data layer gets an abstract repository class (for example `abstract class TimetableRepository`) that view models depend on, with the real implementation built on the site service, so tests and offline mode can swap it.
3. **A shared base for site services.** The common parts of talking to an SIT system (the request headers, the anti-forgery token, signing in again when a session expires) move into one base class that each site's service extends.
4. **Stricter typing.** Turn on the analyzer's `strict-casts`, `strict-inference` and `strict-raw-types`, and remove the remaining `dynamic`.
5. **Input checks.** Validate what users type (student ID format, booking times) at the edge of the UI, and what SIT sends at the edge of the parsers.
