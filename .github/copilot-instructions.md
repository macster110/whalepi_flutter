## WhalePi BLE Terminal - Flutter App

This is a Flutter app for communicating with WhalePi passive acoustic recording devices via Bluetooth Low Energy.

### Project Details

- **Type**: Flutter Mobile Application (WhalePi Controller)
- **Framework**: Flutter 3.41.2
- **Language**: Dart 3.11.0
- **Organization**: com.whalepi
- **Platforms**: Android, iOS, macOS

### Key Dependencies

- `flutter_blue_plus: ^1.35.2` - Cross-platform Bluetooth Low Energy
- `permission_handler: ^11.3.1` - Runtime permissions

### App Structure

```
lib/
├── main.dart                          # App entry point, theme
├── models/
│   ├── message.dart                   # Terminal message model
│   └── pamguard_summary.dart          # PAMGuard data model
├── screens/
│   ├── devices_screen.dart            # BLE device list
│   ├── device_screen.dart             # Main device view (tabs)
│   └── summary_screen.dart            # PAMGuard summary GUI
└── services/
    └── bluetooth_le_service.dart      # BLE UART service
```

### Features

- BLE device discovery and connection
- **Summary View**: GUI for PAMGuard status (audio levels, GPS, recorder, temperature)
- **Terminal View**: Raw command/response interface
- Commands: ping, status, summary, start, stop
- HEX mode and configurable line endings
- Raspberry Pi terminal styling

### Development Commands

```bash
flutter run              # Run on connected device
flutter build apk        # Build Android APK
flutter analyze          # Check for issues
flutter test             # Run tests
```

### Notes

- Supports Android, iOS, and macOS
- Uses Bluetooth Low Energy (BLE) with UART services (Nordic UART, HM-10, etc.)
- Requires physical device for testing (simulators/emulators don't support BLE)
- Parses XML data from WhalePi watchdog (PAMGuard summaries)
