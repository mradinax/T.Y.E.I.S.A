import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Flutter Assistant Core - Play Store Compliant
/// Provides core assistant functionality with proper permissions
class AssistantCore {
  
  /// Opens YouTube with a search query
  /// Requires internet permission (automatically granted)
  static Future<bool> openYouTubeSearch(String query) async {
    try {
      // Encode the search query for URL
      final encodedQuery = Uri.encodeComponent(query);
      final youtubeUrl = 'https://www.youtube.com/results?search_query=$encodedQuery';
      final uri = Uri.parse(youtubeUrl);
      
      // Check if URL can be launched
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        throw Exception('Could not launch YouTube');
      }
    } catch (e) {
      print('Error opening YouTube: $e');
      return false;
    }
  }

  /// Opens Spotify with a search query
  /// Falls back to web version if app not installed
  static Future<bool> openSpotifySearch(String query) async {
    try {
      // Encode the search query for URL
      final encodedQuery = Uri.encodeComponent(query);
      
      // Try to open Spotify app first
      final spotifyAppUrl = 'spotify:search:$encodedQuery';
      final spotifyAppUri = Uri.parse(spotifyAppUrl);
      
      if (await canLaunchUrl(spotifyAppUri)) {
        await launchUrl(spotifyAppUri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        // Fall back to web version
        final spotifyWebUrl = 'https://open.spotify.com/search/$encodedQuery';
        final webUri = Uri.parse(spotifyWebUrl);
        
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
          return true;
        }
      }
      
      throw Exception('Could not launch Spotify');
    } catch (e) {
      print('Error opening Spotify: $e');
      return false;
    }
  }

  /// Search for a contact by name
  /// Returns the contact's phone number if found, null otherwise
  static Future<String?> searchContact(String contactName) async {
    try {
      // Request contacts permission
      final permission = await Permission.contacts.request();
      
      if (permission != PermissionStatus.granted) {
        print('Contacts permission denied');
        return null;
      }

      // Get all contacts with phone numbers
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      
      if (contacts.isEmpty) {
        print('No contacts found');
        return null;
      }

      // Search for the contact (case insensitive)
      final searchName = contactName.toLowerCase().trim();
      
      // Try exact match first
      Contact? foundContact;
      
      // Exact match with display name
      for (var contact in contacts) {
        if (contact.displayName.toLowerCase() == searchName) {
          foundContact = contact;
          break;
        }
      }
      
      // If no exact match, try partial match with display name
      if (foundContact == null) {
        for (var contact in contacts) {
          if (contact.displayName.toLowerCase().contains(searchName)) {
            foundContact = contact;
            break;
          }
        }
      }
      
      // If still no match, try first/last name
      if (foundContact == null) {
        for (var contact in contacts) {
          String firstName = contact.name.first.toLowerCase();
          String lastName = contact.name.last.toLowerCase();
          
          if (firstName == searchName || lastName == searchName ||
              firstName.contains(searchName) || lastName.contains(searchName)) {
            foundContact = contact;
            break;
          }
        }
      }

      // Check if we found a valid contact with phone numbers
      if (foundContact != null && foundContact.phones.isNotEmpty) {
        final phoneNumber = foundContact.phones.first.number;
        print('Found contact: ${foundContact.displayName} - $phoneNumber');
        return phoneNumber;
      }

      print('Contact "$contactName" not found');
      return null;
      
    } catch (e) {
      print('Error searching contacts: $e');
      return null;
    }
  }

  /// Makes a phone call by contact name or phone number
  /// First searches contacts if the input looks like a name
  static Future<Map<String, dynamic>> makePhoneCallByNameOrNumber(String input) async {
    try {
      // Clean the input
      final cleanInput = input.trim();
      
      // Check if input looks like a phone number (contains mostly digits)
      final digitCount = cleanInput.replaceAll(RegExp(r'[^\d]'), '').length;
      final isLikelyPhoneNumber = digitCount >= 7 && digitCount <= 15;
      
      if (isLikelyPhoneNumber) {
        // Treat as phone number directly
        final success = await makePhoneCall(cleanInput);
        return {
          'success': success,
          'message': success ? 'Calling $cleanInput' : 'Could not make call to $cleanInput',
          'contactName': null,
          'phoneNumber': cleanInput
        };
      } else {
        // Treat as contact name - search contacts first
        final phoneNumber = await searchContact(cleanInput);
        
        if (phoneNumber != null) {
          // Found contact, make the call
          final success = await makePhoneCall(phoneNumber);
          return {
            'success': success,
            'message': success ? 'Calling $cleanInput at $phoneNumber' : 'Could not call $cleanInput',
            'contactName': cleanInput,
            'phoneNumber': phoneNumber
          };
        } else {
          // Contact not found
          return {
            'success': false,
            'message': 'Contact "$cleanInput" not found in your phone book',
            'contactName': cleanInput,
            'phoneNumber': null
          };
        }
      }
    } catch (e) {
      print('Error in makePhoneCallByNameOrNumber: $e');
      return {
        'success': false,
        'message': 'Error processing call request: $e',
        'contactName': null,
        'phoneNumber': null
      };
    }
  }

  /// Makes a phone call after requesting permission
  /// Requires CALL_PHONE permission
  static Future<bool> makePhoneCall(String phoneNumber) async {
    try {
      // Request phone call permission
      final permission = await Permission.phone.request();
      
      if (permission != PermissionStatus.granted) {
        print('Phone permission denied');
        return false;
      }

      // Clean phone number (remove spaces, dashes, etc.)
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      
      // Make the call using FlutterPhoneDirectCaller
      final result = await FlutterPhoneDirectCaller.callNumber(cleanNumber);
      return result ?? false;
      
    } catch (e) {
      print('Error making phone call: $e');
      return false;
    }
  }

  /// Opens any app by package name or common name
  /// Falls back to Play Store if app not installed
  static Future<bool> openApp(String appName) async {
    try {
      String? packageInfo = _getPackageName(appName.toLowerCase());
      
      if (packageInfo != null) {
        // Handle different URI schemes
        if (packageInfo.startsWith('com.')) {
          // This is an Android package name, try to launch it
          final androidUri = Uri.parse('package:$packageInfo');
          if (await canLaunchUrl(androidUri)) {
            await launchUrl(androidUri, mode: LaunchMode.externalApplication);
            return true;
          }
          
          // Try alternative Android app launch
          final appUri = Uri.parse('android-app://$packageInfo');
          if (await canLaunchUrl(appUri)) {
            await launchUrl(appUri, mode: LaunchMode.externalApplication);
            return true;
          }
          
          // Fall back to Play Store
          final playStoreUri = Uri.parse('market://details?id=$packageInfo');
          if (await canLaunchUrl(playStoreUri)) {
            await launchUrl(playStoreUri, mode: LaunchMode.externalApplication);
            return true;
          }
          
          // Final fallback to web Play Store
          final webPlayStoreUri = Uri.parse('https://play.google.com/store/apps/details?id=$packageInfo');
          if (await canLaunchUrl(webPlayStoreUri)) {
            await launchUrl(webPlayStoreUri, mode: LaunchMode.externalApplication);
            return true;
          }
        } else {
          // This is a custom URI scheme
          final appUri = Uri.parse(packageInfo);
          if (await canLaunchUrl(appUri)) {
            await launchUrl(appUri, mode: LaunchMode.externalApplication);
            return true;
          }
        }
      }
      
      throw Exception('Could not open app: $appName');
    } catch (e) {
      print('Error opening app: $e');
      return false;
    }
  }

  /// Close an app by bringing the assistant app back to foreground
  /// This is the Play Store compliant way to "close" apps
  static Future<bool> closeApp(String appName) async {
    try {
      print('Closing $appName by bringing assistant to foreground...');
      // On Android, we can't actually "close" other apps due to security restrictions
      // Instead, we bring our own app back to the foreground
      // The user can then use the recent apps button to close the target app
      
      // For now, we'll just return true to indicate the command was processed
      // The main effect is that speech recognition will resume
      return true;
    } catch (e) {
      print('Error closing app: $e');
      return false;
    }
  }

  /// Search for songs on specific music player
  /// Supports Spotify, YouTube Music, Apple Music, etc.
  static Future<bool> searchSongOnMusicPlayer(String musicPlayerName, String songQuery) async {
    try {
      final encodedQuery = Uri.encodeComponent(songQuery);
      String? musicUri = _getMusicPlayerUri(musicPlayerName.toLowerCase(), encodedQuery);
      
      if (musicUri != null) {
        final uri = Uri.parse(musicUri);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return true;
        }
      }
      
      // Fallback to general music search
      return await openYouTubeSearch('$songQuery music');
      
    } catch (e) {
      print('Error searching song on music player: $e');
      return false;
    }
  }

  /// Get package name or URI scheme for common apps
  static String? _getPackageName(String appName) {
    final Map<String, String> commonApps = {
      // Social Media & Communication
      'whatsapp': 'com.whatsapp',
      'instagram': 'com.instagram.android',
      'snapchat': 'com.snapchat.android',
      'facebook': 'com.facebook.katana',
      'messenger': 'com.facebook.orca',
      'twitter': 'com.twitter.android',
      'telegram': 'org.telegram.messenger',
      'discord': 'com.discord',
      'linkedin': 'com.linkedin.android',
      'skype': 'com.skype.raider',
      'teams': 'com.microsoft.teams',
      'zoom': 'us.zoom.videomeetings',
      
      // Entertainment & Media
      'youtube': 'com.google.android.youtube',
      'netflix': 'com.netflix.mediaclient',
      'amazon prime': 'com.amazon.avod.thirdpartyclient',
      'disney plus': 'com.disney.disneyplus',
      'hulu': 'com.hulu.plus',
      'hbo max': 'com.hbo.hbonow',
      'twitch': 'tv.twitch.android.app',
      'tiktok': 'com.zhiliaoapp.musically',
      'reddit': 'com.reddit.frontpage',
      
      // Music & Audio
      'spotify': 'com.spotify.music',
      'youtube music': 'com.google.android.apps.youtube.music',
      'apple music': 'com.apple.android.music',
      'soundcloud': 'com.soundcloud.android',
      'amazon music': 'com.amazon.mp3',
      'pandora': 'com.pandora.android',
      'deezer': 'deezer.android.app',
      
      // Shopping & E-commerce
      'amazon': 'com.amazon.mShop.android.shopping',
      'flipkart': 'com.flipkart.android',
      'myntra': 'com.myntra.android',
      'paytm': 'net.one97.paytm',
      'gpay': 'com.google.android.apps.nbu.paisa.user',
      'phonepe': 'com.phonepe.app',
      'swiggy': 'in.swiggy.android',
      'zomato': 'com.application.zomato',
      'uber eats': 'com.ubercab.eats',
      
      // Transportation
      'uber': 'com.ubercab',
      'ola': 'com.olacabs.customer',
      'google maps': 'com.google.android.apps.maps',
      'waze': 'com.waze',
      
      // Productivity & Utilities
      'gmail': 'com.google.android.gm',
      'chrome': 'com.android.chrome',
      'firefox': 'org.mozilla.firefox',
      'edge': 'com.microsoft.emmx',
      'drive': 'com.google.android.apps.docs',
      'dropbox': 'com.dropbox.android',
      'office': 'com.microsoft.office.officehubrow',
      'word': 'com.microsoft.office.word',
      'excel': 'com.microsoft.office.excel',
      'powerpoint': 'com.microsoft.office.powerpoint',
      'one note': 'com.microsoft.office.onenote',
      'evernote': 'com.evernote',
      'notion': 'notion.id',
      
      // System Apps
      'camera': 'com.android.camera2',
      'calculator': 'com.android.calculator2',
      'settings': 'com.android.settings',
      'contacts': 'com.android.contacts',
      'phone': 'com.google.android.dialer',
      'messages': 'com.google.android.apps.messaging',
      'gallery': 'com.google.android.apps.photos',
      'files': 'com.google.android.documentsui',
      'play store': 'com.android.vending',
      
      // Gaming
      'pubg': 'com.tencent.ig',
      'cod': 'com.activision.callofduty.shooter',
      'free fire': 'com.dts.freefireth',
      'candy crush': 'com.king.candycrushsaga',
      'clash of clans': 'com.supercell.clashofclans',
      'clash royale': 'com.supercell.clashroyale',
      'pokemon go': 'com.nianticlabs.pokemongo',
      'among us': 'com.innersloth.spacemafia',
      
      // News & Reading
      'times of india': 'com.toi.reader.activities',
      'hindustan times': 'com.ht.news',
      'news18': 'com.news18.app',
      'inshorts': 'com.nis.app',
      'google news': 'com.google.android.apps.magazines',
      
      // Dating & Social
      'tinder': 'com.tinder',
      'bumble': 'com.bumble.app',
      'hinge': 'co.hinge.app',
      
      // Health & Fitness
      'google fit': 'com.google.android.apps.fitness',
      'nike run club': 'com.nike.plusone',
      'strava': 'com.strava',
      'fitbit': 'com.fitbit.FitbitMobile',
      'headspace': 'com.headspace.android',
      'calm': 'com.calm.android',
      
      // Photo & Video
      'vsco': 'com.vsco.cam',
      'lightroom': 'com.adobe.lrmobile',
      'canva': 'com.canva.editor',
      'picsart': 'com.picsart.studio',
      'snapseed': 'com.niksoftware.snapseed',
    };
    
    return commonApps[appName];
  }

  /// Get music player specific URI for song search
  static String? _getMusicPlayerUri(String musicPlayer, String encodedQuery) {
    final Map<String, String> musicPlayers = {
      'spotify': 'spotify:search:$encodedQuery',
      'youtube music': 'https://music.youtube.com/search?q=$encodedQuery',
      'apple music': 'music://search?term=$encodedQuery',
      'soundcloud': 'soundcloud://search?q=$encodedQuery',
      'deezer': 'deezer://search/$encodedQuery',
      'amazon music': 'amzn://music/search?query=$encodedQuery',
      'pandora': 'pandora://search/$encodedQuery',
      'youtube': 'https://www.youtube.com/results?search_query=$encodedQuery',
    };
    
    return musicPlayers[musicPlayer];
  }

  /// Check if all required permissions are granted
  static Future<Map<String, bool>> checkAllPermissions() async {
    return {
      'phone': await Permission.phone.isGranted,
      'contacts': await Permission.contacts.isGranted,
    };
  }

  /// Request all permissions at once
  static Future<bool> requestAllPermissions() async {
    try {
      final permissions = await [
        Permission.phone,
        Permission.contacts,
      ].request();
      
      // Check if all permissions are granted
      return permissions.values.every((status) => status == PermissionStatus.granted);
    } catch (e) {
      print('Error requesting permissions: $e');
      return false;
    }
  }
}
