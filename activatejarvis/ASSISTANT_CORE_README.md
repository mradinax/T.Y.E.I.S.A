# Assistant Core Documentation

## Overview
The Assistant Core provides Play Store-compliant functionality for voice assistants and automation apps. It includes permission management and core assistant functions.

## Features

### 1. YouTube Search
- **Function**: `AssistantCore.openYouTubeSearch(String query)`
- **Permission**: Internet (automatically granted)
- **Description**: Opens YouTube with a search query
- **Example**: `AssistantCore.openYouTubeSearch("Iron Man soundtrack")`

### 2. Spotify Search  
- **Function**: `AssistantCore.openSpotifySearch(String query)`
- **Permission**: Internet (automatically granted)
- **Description**: Opens Spotify app or web version with search query
- **Example**: `AssistantCore.openSpotifySearch("Tony Stark music")`

### 3. Phone Call
- **Function**: `AssistantCore.makePhoneCall(String phoneNumber)`
- **Permission**: CALL_PHONE (user must grant)
- **Description**: Makes a direct phone call
- **Example**: `AssistantCore.makePhoneCall("+1234567890")`

### 4. Open Any App
- **Function**: `AssistantCore.openApp(String appName)`
- **Permission**: Internet (automatically granted)
- **Description**: Opens any app by name, falls back to Play Store if not installed
- **Example**: `AssistantCore.openApp("Instagram")`
- **Supported Apps**: Spotify, Instagram, Facebook, WhatsApp, Netflix, YouTube, Gmail, Chrome, and many more

### 5. Search Song on Music Player
- **Function**: `AssistantCore.searchSongOnMusicPlayer(String musicPlayer, String songQuery)`
- **Permission**: Internet (automatically granted)
- **Description**: Opens specific music player with song search
- **Example**: `AssistantCore.searchSongOnMusicPlayer("Spotify", "Bohemian Rhapsody Queen")`
- **Supported Players**: Spotify, YouTube Music, Apple Music, SoundCloud, Deezer, Amazon Music, Pandora

## Permission Management

### Check Permissions
```dart
Map<String, bool> permissions = await AssistantCore.checkAllPermissions();
print('Phone permission: ${permissions['phone']}');
```

### Request All Permissions
```dart
bool allGranted = await AssistantCore.requestAllPermissions();
if (allGranted) {
    print('All permissions granted!');
} else {
    print('Some permissions were denied');
}
```

## Android Permissions Required

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Assistant Core Permissions - Play Store Compliant -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CALL_PHONE" />

<!-- URL Launcher queries -->
<queries>
    <intent>
        <action android:name="android.intent.action.VIEW" />
        <data android:scheme="https" />
    </intent>
    <intent>
        <action android:name="android.intent.action.VIEW" />
        <data android:scheme="spotify" />
    </intent>
</queries>
```

## Dependencies Required

Add to `pubspec.yaml`:

```yaml
dependencies:
  permission_handler: ^11.3.1
  url_launcher: ^6.3.1
  flutter_phone_direct_caller: ^2.1.1
```

## Usage in Voice Assistant

Integration with voice commands:

```dart
// Example voice command processing
Future<void> processVoiceCommand(String command) async {
  command = command.toLowerCase();
  
  if (command.contains('call')) {
    String phoneNumber = extractPhoneNumber(command);
    bool success = await AssistantCore.makePhoneCall(phoneNumber);
    speak(success ? "Calling now" : "Could not make call");
  }
  
  else if (command.contains('open')) {
    String appName = extractAppName(command);
    bool success = await AssistantCore.openApp(appName);
    speak(success ? "Opening $appName" : "Could not open $appName");
  }
  
  else if (command.contains('play') && command.contains('on')) {
    String musicPlayer = extractMusicPlayer(command);
    String song = extractSongName(command);
    bool success = await AssistantCore.searchSongOnMusicPlayer(musicPlayer, song);
    speak(success ? "Playing $song on $musicPlayer" : "Could not play song");
  }
  
  else if (command.contains('play') && command.contains('youtube')) {
    String query = extractSearchQuery(command);
    bool success = await AssistantCore.openYouTubeSearch(query);
    speak(success ? "Opening YouTube" : "Could not open YouTube");
  }
  
  else if (command.contains('play') && command.contains('spotify')) {
    String query = extractSearchQuery(command);
    bool success = await AssistantCore.openSpotifySearch(query);
    speak(success ? "Opening Spotify" : "Could not open Spotify");
  }
}
```

## Supported Apps

### Common Apps
- **Social**: Instagram, Facebook, Twitter, TikTok, Discord
- **Communication**: WhatsApp, Telegram, Gmail
- **Entertainment**: Netflix, YouTube, Spotify
- **Shopping**: Amazon
- **Transportation**: Uber
- **Browsers**: Chrome
- **System**: Settings, Camera, Calculator, Contacts

### Music Players
- **Spotify**: Full app and search integration
- **YouTube Music**: Web and app integration
- **Apple Music**: iOS app integration
- **SoundCloud**: App and web integration
- **Deezer**: Search integration
- **Amazon Music**: Search integration
- **Pandora**: Search integration

## Play Store Compliance

This implementation is designed to be Play Store compliant:

1. **No Background Permissions**: All actions require user interaction
2. **Minimal Permission Requests**: Only phone calls require special permission
3. **Standard Permissions**: Only uses common, accepted permissions
4. **User Control**: Users can test all functions in the demo interface
5. **Transparent Usage**: Clear documentation of what each permission does

## Demo Interface

The `AssistantCoreDemo` widget provides:
- Permission status display
- Request permissions button
- Test interfaces for all functions
- Success/failure feedback
- Sample data buttons for quick testing

## Error Handling

All functions return `bool` to indicate success/failure:
- `true`: Action completed successfully
- `false`: Action failed (permission denied, network error, app not found, etc.)

Check console logs for detailed error messages during development.

## Testing

Use the demo interface to test all functionality:
1. Launch app and navigate to "Assistant Functions Demo"
2. Grant required permissions
3. Test each function with sample data
4. Verify apps open correctly and actions complete

## Integration Notes

- Functions are static and can be called from anywhere
- Always check permissions before calling restricted functions
- Handle failures gracefully with user feedback
- Test on real devices for accurate app opening behavior
- Music player integration may vary by device and installed apps
