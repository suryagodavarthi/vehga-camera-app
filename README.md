# Vehga Field Camera App (Flutter)

Camera app for field agencies: log in, enter a vehicle number, take the AVO
inspection photos with a location watermark, and sync them to the Pronto
backend so they appear on the AVO page.

## Flow

1. **Login** — each agency has its own ID and password
   (validated by `POST /api/users/login` on the backend).
2. **Vehicle number** — the app looks the number up among open cases
   (`GET /api/valuations/workflows/open`).
3. **Photos** — the checklist mirrors the AVO page photo slots.
   Mandatory ones are marked `*` (orange border).
4. Every capture is stamped and **saved to the phone gallery**
   (album "Vehga Inspections"):
   - Vehga logo bottom-left (white glow so it is visible on dark photos)
   - Date & time, street, area, village/town/city, state bottom-right
     (white text with dark outline — no box, image stays visible)
5. **Submit** — uploads via `PUT /api/valuations/{id}/photos`, the same
   endpoint the AVO page reads, so photos reflect there immediately.

## Setting agency credentials

Passwords live in the `Users` table (Azure Table Storage) in a `Password`
column. Set them either by:
- creating/updating the user through `POST /api/users` with a `password`
  field in the body, or
- adding the `Password` property to the user row directly in
  Azure Storage Explorer.

Login is `POST /api/users/login` with `{ "userId": "...", "password": "..." }`.

## Server URL

Defaults to the production backend (see `lib/config.dart`).
To point elsewhere without rebuilding: **long-press the logo on the login
screen** and edit the URL (persisted on the device).

## Build

```
flutter pub get
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

## Replacing the logo

Overwrite `assets/logo.png` (transparent PNG) and rebuild.
