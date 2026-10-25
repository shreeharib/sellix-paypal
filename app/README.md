# sellix merchant app (Flutter)

The merchant's control centre: Today (stock and the agent switch), Ask me (the agent's questions), Orders, Chats, Settings. One codebase for Android (first), web, and iOS (later). Design: [docs/dev-plan.md](../docs/dev-plan.md), section 6.

## Running Flutter on the team's managed Windows laptops

Group policy blocks PowerShell, which `flutter.bat` needs. Use the native launcher instead, everywhere you'd type `flutter`:

```bash
D:\Android\flutter-direct.cmd pub get
D:\Android\flutter-direct.cmd analyze
D:\Android\flutter-direct.cmd test
D:\Android\flutter-direct.cmd build web --release
```

From Git Bash: `cmd //c 'D:\Android\flutter-direct.cmd' analyze < /dev/null`. On other machines, plain `flutter` works.

## Run it

The app talks to the sellix API (`backend/`). Point it at the API with `--dart-define`:

```bash
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000
flutter run -d <android-device> --dart-define=API_BASE_URL=https://<public API URL>
```

The API must list the app's redirect and origin in `backend/.env`:

- `APP_REDIRECT_URIS=sellix://auth/callback,http://localhost:8080/auth.html`
- `WEB_APP_ORIGINS=http://localhost:8080`

## Sign-in

"Continue with Instagram" opens Instagram's login (with PKCE), comes back to `sellix://auth/callback` on Android or `web/auth.html` on the web, and exchanges a one-time code for the session. Tokens live in secure storage. Until the platform's Meta app passes App Review, only Instagram accounts with a role on that app can sign in. See [ADR 0004](../docs/adr/0004-sign-in-with-instagram.md).

## Layout

```
lib/
  main.dart, app.dart
  core/           API client and models, sign-in (PKCE, tokens, refresh), router, theme, shared widgets
  features/       sign_in, shell (tabs), today, ask_me, orders, chats, settings
  l10n/           app_en.arb, app_ta.arb (keys prefixed by feature); Dart code is generated
test/             widget tests against an in-memory API
web/auth.html     where the web sign-in returns
```

Before release: replace the `com.example.sellix` application ID, and have a native speaker review `app_ta.arb`.
