Steps to generate platform icons from your source image (PowerShell)

1. Place your provided image (attached earlier) at:
   assets/icon/app_icon.png

2. Get packages:

   flutter pub get

3. Run the icon generator:

   flutter pub run flutter_launcher_icons:main

4. Clean and run your app (uninstall any installed app first to avoid icon caching):

   flutter clean
   flutter run -d <device-id>

Notes:
- The generator will update Android mipmap folders and iOS AppIcon assets automatically.
- If you want adaptive Android icons, add `adaptive_icon_background` and/or `adaptive_icon_foreground` to the `flutter_icons` section in `pubspec.yaml`.
- For web, windows, macos: you may need to replace `web/favicon.png`, `windows/runner/resources/app_icon.ico`, and `macos/Runner/Assets.xcassets/AppIcon.appiconset/*` manually if desired.
