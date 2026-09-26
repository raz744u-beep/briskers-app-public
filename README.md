# Briskers App

Development Flutter frontend for the Briskers auto-repair operating system.

## Current milestone
- Android-first office/owner prototype
- Target physical test device: Galaxy Note 9, Android 10 (API 29)
- Supabase Dev backend connection
- Email/password development login
- Role/business gate
- Today dashboard
- Customer search/list/create/detail
- Vehicle display
- Job list

## Build
GitHub Actions builds a debug APK on every push to `main` and on manual workflow dispatch.
The workflow creates a clean Flutter Android shell, copies this app source into it, runs `flutter analyze`, runs tests, and builds `app-debug.apk`.

The Supabase publishable key is intentionally client-side. No Supabase secret/service key is stored in this repository.
