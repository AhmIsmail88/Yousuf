# Yousuf

> يوسف — رفيقك في الطاعة. تطبيق إسلامي شامل يعمل أوفلاين.

## Overview
Yousuf is a comprehensive offline Islamic application designed to assist users in their daily religious practices. It provides a wide range of features including Quran recitation, prayer time calculations, and various religious tools.

## Features
- **Quranic Features**: Includes a Mushaf reader, audio recitation with background playback support, Ayah study (Tafsir and Asbab al-Nuzul), and a download manager for recitations.
- **Prayer Tools**: Provides prayer time calculations based on location, Qibla direction, and Adhan notifications.
- **Daily Practices**: Includes Adhkar (morning/evening and Quranic), Tasbih, and a Khatma plan.
- **Educational Content**: Features a kids' section with learning screens and a Hadith library.
- **Localization**: Supports multiple languages including Arabic and English.
- **Offline Capability**: Uses a local SQLite database for content and supports offline audio playback.
- **Data Management**: Includes a city database for accurate prayer time calculations and a content versioning system using SHA256 checksums.

## Tech Stack
- **Framework**: Flutter
- **Language**: Dart
- **State Management**: Flutter Riverpod
- **Database**: SQLite3
- **Audio**: just_audio, just_audio_background
- **Location/Sensors**: geolocator, flutter_compass
- **Networking**: http
- **Other**: whisper_ggml, shared_preferences, timezone, hijri

## Getting Started
To run the project, ensure you have the Flutter SDK installed.

```bash
# Clone the repository
git clone https://github.com/AhmIsmail88/Yousuf

# Navigate to the project directory
cd Yousuf

# Install dependencies
flutter pub get

# Run the application
flutter run
```

## Configuration
The application reads configuration from the process environment and internal assets.

| Variable/Setting | Description |
| --- | --- |
| `content.sqlite` | Local database containing Quranic and Adhkar data. |
| `cities.json` | Database of cities for prayer time calculations. |
| `shared_preferences` | Used for storing user preferences like language and onboarding status. |

## Usage
The application provides a multi-feature interface:
- **Quran**: Access the Mushaf, select a reciter, and download audio.
- **Prayer**: View prayer times and Qibla direction.
- **Adhkar**: Track daily remembrances with repeat counts.
- **Kids**: Dedicated learning section for children.

## Project Structure
```text
.
├── android/            # Android specific configuration and native code
├── ios/                # iOS specific configuration and native code
├── assets/             # Fonts, brand icons, and database files
│   ├── db/            # SQLite databases and city JSON
│   ├── fonts/        # Arabic and Latin fonts
│   └── brand/        # App branding and logos
├── lib/                # Main application source code
│   ├── app/           # Routing, themes, and localization
│   ├── core/          # Database, networking, and utility logic
│   ├── features/      # Feature-based modules (Quran, Prayer, Adhkar, etc.)
│   └── l10n/          # Localization files
├── packages/           # External packages (e.g., whisper_ggml)
├── test/               # Unit and widget tests
└── pubspec.yaml        # Project dependencies and assets
```
