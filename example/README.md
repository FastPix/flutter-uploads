# fastpix_resumable_uploader — Example App

An end-to-end Flutter example showing how to upload a video to **FastPix** with the
[`fastpix_resumable_uploader`](https://pub.dev/packages/fastpix_resumable_uploader) SDK.
The same code runs on **Android** and **iOS** — Flutter handles the platform glue.

The example demonstrates:

- Picking a video from the device gallery (Android & iOS).
- Requesting a signed URL from the FastPix Direct Upload API.
- Uploading the video in 16 MB chunks via the builder API.
- Real-time progress, chunk counters, pause / resume / abort, and error handling.

## Running the example

### 1. Add your FastPix credentials

Open [`lib/upload_screen.dart`](lib/upload_screen.dart) and replace the placeholder
constants near the top of the file:

```dart
const String _kFastPixTokenId  = 'YOUR_FASTPIX_TOKEN_ID';
const String _kFastPixSecretKey = 'YOUR_FASTPIX_SECRET_KEY';
```

You can generate these from the
[FastPix dashboard](https://docs.fastpix.com/docs/basic-authentication).

> In production never ship the token + secret in the client. Proxy
> `POST https://api.fastpix.app/v1/on-demand/upload` through your own backend
> and only return the resulting `data.url` to the device.

### 2. Install dependencies

```bash
cd example
flutter pub get
```

### 3. Run on a device or simulator

```bash
# Android
flutter run -d android

# iOS (open ios/Runner.xcworkspace once first to set a signing team if needed)
flutter run -d ios
```

## Permissions

These are already configured in the example, but worth knowing about if you're
porting this into your own app.

### Android — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
```

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs access to your photo library to pick a video for upload.</string>
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to record videos to upload.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record audio when recording video.</string>
```

## File tour

| File | What it does |
| --- | --- |
| [`lib/main.dart`](lib/main.dart) | App entry point and theming. |
| [`lib/signed_url_service.dart`](lib/signed_url_service.dart) | Calls the FastPix Direct Upload API to mint a signed URL. |
| [`lib/upload_screen.dart`](lib/upload_screen.dart) | UI + glue code that drives `FlutterResumableUploads`. |

The example consumes the SDK via a **path dependency** in
[`pubspec.yaml`](pubspec.yaml), so any local edits to the library propagate
into the example without re-publishing:

```yaml
dependencies:
  fastpix_resumable_uploader:
    path: ../
```
