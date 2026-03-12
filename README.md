# WhalePi BLE Terminal

A Flutter mobile application for communicating with WhalePi passive acoustic recording devices via Bluetooth Low Energy (BLE).

![App Screenshot](assets/Screenshot_20260309-212042.png)

## Features

- **Device Discovery**: Scan for and connect to nearby BLE devices
- **Summary View**: GUI dashboard for PAMGuard status — audio levels, GPS, recorder state, and temperature
- **Terminal View**: Raw command/response interface with Raspberry Pi terminal styling
- **HEX Mode**: Switch between text and hexadecimal display
- **Line Endings**: Configurable line endings (CR, LF, CR+LF, None)
- **Connection Status**: Real-time BLE connection state display
- **Message History**: Scrollable timestamped message log
- **UART Services**: Supports Nordic UART Service, HM-10, and other BLE UART profiles
- **Commands**: `ping`, `status`, `summary`, `start`, `stop`

## Project Information

- **Framework**: Flutter 3.41.2
- **Dart**: 3.11.0
- **Organization**: com.whalepi
- **Platforms**: Android, iOS, macOS

## Dependencies

- `flutter_blue_plus` - Cross-platform BLE support
- `permission_handler` - Runtime permission handling

## Getting Started

### Prerequisites

- Flutter SDK 3.41.2 or higher
- Android SDK (for Android development)
- Xcode (for iOS/macOS development)
- A physical device (BLE is not available on emulators/simulators)

### Platform Setup

**Android**: Bluetooth permissions configured in `android/app/src/main/AndroidManifest.xml`
- `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` (Android 12+)
- `ACCESS_FINE_LOCATION` (for device discovery)

**iOS/macOS**: Bluetooth usage descriptions configured in `Info.plist`

### Running the App

```bash
flutter run
```

### Building for Release

```bash
flutter build apk --release        # Android APK
flutter build appbundle --release  # Android App Bundle
```

## Usage

1. **Launch the app** — The device list screen appears
2. **Enable Bluetooth** — If disabled, tap "Enable Bluetooth"
3. **Select a device** — Tap a discovered WhalePi device to connect
4. **Summary tab** — View real-time PAMGuard status (audio, GPS, recorder, temperature)
5. **Terminal tab** — Send raw commands and view responses
6. **Options**:
   - Toggle HEX mode for raw byte display
   - Configure line endings
   - Clear message history

## Project Structure

```
lib/
├── main.dart                          # App entry point, theme
├── models/
│   ├── message.dart                   # Terminal message model
│   └── pamguard_summary.dart          # PAMGuard data model
├── screens/
│   ├── devices_screen.dart            # BLE device list
│   ├── device_screen.dart             # Main device view (tabs)
│   ├── summary_screen.dart            # PAMGuard summary GUI
│   └── terminal_screen.dart           # Raw terminal UI
└── services/
    └── bluetooth_le_service.dart      # BLE UART service
```

## Notes

- **Bluetooth Low Energy (BLE)** — Uses UART-over-BLE (Nordic UART Service and compatible profiles)
- **Physical device required** — BLE is not available on emulators or simulators
- **WhalePi devices** — Parses XML data from the WhalePi watchdog process (PAMGuard summaries)

## Resources

- [flutter_blue_plus](https://pub.dev/packages/flutter_blue_plus)
- [Flutter Documentation](https://docs.flutter.dev/)
