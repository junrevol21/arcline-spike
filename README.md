# Arcline spike: GPS background test

Throwaway prototype (Flutter) to check whether location recording and voice prompts keep working while the phone screen is off, on iPhone and Android.

- App: `spike/gps_bg` (geolocator, flutter_tts). Records 1 Hz GPS to CSV, speaks a test prompt every 60 s, shows the longest gap between fixes.
- Build: GitHub Actions workflow `Spike build` (Actions tab → Run workflow) produces an unsigned iOS IPA (for sideloading) and an Android APK.

Not production code.
