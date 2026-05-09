# Local Helper

A cross-platform Flutter application that connects users with local workers and service providers. The app features real-time location tracking, booking management, and direct communication capabilities through integrated WhatsApp and calling features.

## 📱 Features

- **User Authentication**: Secure Firebase authentication for user registration and login
- **Real-Time Geolocation**: Live location tracking and distance calculation using Google Maps
- **Worker Discovery**: Browse and search for available local workers and service providers
- **Booking System**: Schedule and manage worker bookings with real-time updates
- **Direct Communication**: Contact workers via WhatsApp or direct phone calls
- **Location-Based Services**: Find workers near your location using Google Maps integration
- **Real-Time Updates**: Firebase Firestore for instant data synchronization
- **Dark Theme UI**: Modern Material Design 3 with a sleek dark theme

## 🛠️ Tech Stack

### Core
- **Flutter**: ^3.0.0 - Cross-platform mobile framework
- **Dart**: ^3.0.0 - Programming language

### Backend & Database
- **Firebase Core**: ^3.13.0 - Firebase initialization
- **Firebase Auth**: ^5.5.2 - User authentication
- **Cloud Firestore**: ^5.6.6 - Real-time database

### Maps & Location
- **Google Maps Flutter**: ^2.12.1 - Interactive map display
- **Geolocator**: ^14.0.0 - Device location services

### Communication
- **URL Launcher**: ^6.3.1 - WhatsApp and phone call integration

### UI & State Management
- **Provider**: ^6.1.5 - State management
- **Flutter Spinkit**: ^5.2.1 - Loading indicators
- **Font Awesome Flutter**: ^10.8.0 - Icon library
- **Material 3**: Modern Material Design

## 📋 Prerequisites

Before you begin, ensure you have the following installed:

- **Flutter SDK**: Version 3.0.0 or higher
  - [Download Flutter](https://flutter.dev/docs/get-started/install)
- **Dart SDK**: Included with Flutter
- **Android Studio** or **Xcode** (for iOS):
  - Android: Min SDK 21, Target SDK 34+
  - iOS: Min iOS 11.0
- **Git**: For version control
- **Firebase Project**: Set up a Firebase project for your application

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/local_helper.git
cd local_helper
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Firebase Setup

#### Android Setup:
1. Download `google-services.json` from Firebase Console
2. Place it in `android/app/` directory
3. Follow [Firebase Android Setup Guide](https://firebase.flutter.dev/docs/overview)

#### iOS Setup:
1. Download `GoogleService-Info.plist` from Firebase Console
2. Add it to `ios/Runner/` using Xcode
3. Follow [Firebase iOS Setup Guide](https://firebase.flutter.dev/docs/overview)

### 4. Google Maps API

1. Enable Google Maps API in your Google Cloud Console
2. Generate API keys for Android and iOS
3. Add Android key to `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="YOUR_ANDROID_API_KEY" />
   ```
4. Add iOS key to `ios/Runner/Info.plist`

### 5. Run the App

#### Android:
```bash
flutter run -d android
```

#### iOS:
```bash
flutter run -d ios
```

#### Web (if supported):
```bash
flutter run -d chrome
```

#### All available devices:
```bash
flutter devices
```

## 📁 Project Structure

```
local_helper/
├── lib/
│   └── main.dart              # App entry point and configuration
├── android/                   # Android-specific code
│   └── app/
│       └── google-services.json
├── ios/                       # iOS-specific code
├── web/                       # Web build (if applicable)
├── linux/                     # Linux build (if applicable)
├── windows/                   # Windows build (if applicable)
├── pubspec.yaml              # Dependencies and project configuration
├── analysis_options.yaml     # Dart lint rules
└── README.md                 # This file
```

## 🔐 Firebase Configuration

This app requires the following Firebase services:

- **Authentication**: Email/password and Google Sign-in support
- **Cloud Firestore**: Database for users, workers, and bookings
- **Cloud Storage** (optional): For profile images and documents

### Firestore Collections Structure:
```
users/
├── {userId}
│   ├── name
│   ├── email
│   ├── phone
│   ├── location
│   └── createdAt

workers/
├── {workerId}
│   ├── name
│   ├── category
│   ├── rating
│   ├── location
│   ├── availability
│   └── contact

bookings/
├── {bookingId}
│   ├── userId
│   ├── workerId
│   ├── status
│   ├── date
│   ├── location
│   └── timestamp
```

## 🔧 Development

### Code Generation (if applicable):
```bash
flutter pub run build_runner build
```

### Running Tests:
```bash
flutter test
```

### Code Analysis:
```bash
flutter analyze
```

### Format Code:
```bash
flutter format lib/
```

### Build APK (Android):
```bash
flutter build apk
```

### Build iOS Archive:
```bash
flutter build ios
```

## 📝 Environment Variables

Create a `.env` file in the project root (if needed):
```
FIREBASE_PROJECT_ID=your_project_id
GOOGLE_MAPS_API_KEY=your_api_key
```

## 🐛 Troubleshooting

### Common Issues

1. **Firebase initialization fails**
   - Ensure `google-services.json` (Android) or `GoogleService-Info.plist` (iOS) is properly placed
   - Verify Firebase project settings

2. **Google Maps not displaying**
   - Check API key configuration for both Android and iOS
   - Ensure Google Maps API is enabled in Google Cloud Console
   - Verify AndroidManifest.xml and Info.plist have correct API keys

3. **Location permission denied**
   - Check platform-specific permission files
   - Ensure app requests location permissions on first launch
   - For iOS: Update `Info.plist` with `NSLocationWhenInUseUsageDescription`

4. **Build issues**
   - Run `flutter clean`
   - Delete `pubspec.lock` and run `flutter pub get` again
   - Update Flutter: `flutter upgrade`

## 📚 Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Firebase for Flutter](https://firebase.flutter.dev/)
- [Google Maps Flutter Plugin](https://pub.dev/packages/google_maps_flutter)
- [Provider State Management](https://pub.dev/packages/provider)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 👨‍💻 Author

Created with ❤️ by [Your Name]

For support or questions, please open an issue on GitHub.

---

**Last Updated**: May 2026
**Flutter Version**: 3.0.0+
**Dart Version**: 3.0.0+
