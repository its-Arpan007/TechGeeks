import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';


// =======================================================================
// |                                                                     |
// |      IMPORTANT: SETUP INSTRUCTIONS TO FIX THE APP CRASH             |
// |                                                                     |
// =======================================================================
//
// The app uses native features and requires configuration outside of this file.
//
// 1. EDIT `pubspec.yaml`:
//    Add the `http` and `image_picker` packages.
//
//    dependencies:
//      flutter:
//        sdk: flutter
//      # ... other packages
//      http: ^1.2.1
//      image_picker: ^1.0.7
//      permission_handler: ^11.3.1
//      google_maps_flutter: ^2.5.3
//      geolocator: ^11.0.0
//
// 2. EDIT `android/app/build.gradle`:
//    Ensure `minSdkVersion` is at least 21.
//
//    android { ... defaultConfig { ... minSdkVersion 21 ... } ... }
//
// 3. EDIT `android/app/src/main/AndroidManifest.xml`:
//    a) Add Permissions (inside `<manifest>` tag):
//    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
//    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
//    <uses-permission android:name="android.permission.CAMERA" />
//
//    b) Add Google Maps API Key (inside `<application>` tag):
//    <meta-data android:name="com.google.android.geo.API_KEY"
//               android:value="YOUR_GOOGLE_MAPS_API_KEY_HERE"/>
//
// 4. EDIT `ios/Runner/Info.plist`:
//    Add descriptions for camera and photo library usage.
//
//    <key>NSCameraUsageDescription</key>
//    <string>This app needs camera access to take pictures of the ambulance.</string>
//    <key>NSPhotoLibraryUsageDescription</key>
//    <string>This app needs photo library access to select pictures of the ambulance.</string>
//    <key>NSLocationWhenInUseUsageDescription</key>
//    <string>This app needs access to your location to find nearby hospitals and track rides.</string>
//
// 5. RUN `flutter clean` AND RE-RUN THE APP.
//
// =======================================================================

// --- MAIN APP ENTRY POINT ---
void main() {
  runApp(const CombinedMediRideApp());
}

// --- ENUMS ---
enum BookingFlow {
  emergency,
  later,
}

// --- DATA MODELS ---
class Hospital {
  final String name;
  final double lat;
  final double lng;
  final String specialty;
  final double distanceKm;
  final int bedCapacity;
  int availableBeds; // Made non-final to allow updates
  List<String> facilities; // Made non-final to allow updates
  final String phone;

  Hospital({
    required this.name,
    required this.lat,
    required this.lng,
    required this.specialty,
    required this.distanceKm,
    required this.bedCapacity,
    required this.availableBeds,
    required this.facilities,
    required this.phone,
  });
}
extension GradientButton on Widget {
  Widget applyGradientBackground(Gradient gradient) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: this,
    );
  }
}



// --- API SERVICE (Logic from Python script + Enhancements) ---
class HospitalApiService {
  // Generates consistent, realistic dummy data for a given hospital name
  static Map<String, dynamic> _generateDummyDetails(String hospitalName) {
    final random = Random(hospitalName.hashCode);
    final bedCapacity = 50 + random.nextInt(251); // Capacity between 50 and 300
    final availableBeds = (bedCapacity * (0.1 + random.nextDouble() * 0.7)).round(); // 10% to 80% available

    final allFacilities = ['Emergency', 'ICU', 'Radiology', 'Pharmacy', 'Cardiology', 'Neurology', 'Oncology'];
    allFacilities.shuffle(random);
    final facilities = allFacilities.take(3 + random.nextInt(3)).toList(); // 3 to 5 facilities

    final phone = '9${random.nextInt(999).toString().padLeft(3, '0')}-${random.nextInt(999).toString().padLeft(3, '0')}-${random.nextInt(9999).toString().padLeft(4, '0')}';

    return {
      'bedCapacity': bedCapacity,
      'availableBeds': availableBeds,
      'facilities': facilities,
      'phone': phone,
    };
  }

  static Future<List<Hospital>> getNearbyHospitals(double lat, double lng, {double radius = 10000}) async {
    final overpassUrl = Uri.parse("http://overpass-api.de/api/interpreter");
    final overpassQuery = """
        [out:json][timeout:30];
        (
          node["amenity"~"hospital|clinic"](around:$radius,$lat,$lng);
          way["amenity"~"hospital|clinic"](around:$radius,$lat,$lng);
        );
        out center;
    """;

    try {
      final response = await http.post(overpassUrl, body: overpassQuery);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> elements = data['elements'];
        final List<Hospital> hospitals = [];

        for (var element in elements) {
          final tags = element['tags'];
          if (tags != null && tags['name'] != null) {
            double hLat, hLng;
            if (element['type'] == 'node') {
              hLat = element['lat'];
              hLng = element['lon'];
            } else if (element['center'] != null) {
              hLat = element['center']['lat'];
              hLng = element['center']['lon'];
            } else {
              continue;
            }

            final distance = Geolocator.distanceBetween(lat, lng, hLat, hLng) / 1000; // in km

            // Generate additional realistic details
            final dummyDetails = _generateDummyDetails(tags['name']);

            hospitals.add(Hospital(
              name: tags['name'],
              lat: hLat,
              lng: hLng,
              specialty: tags['healthcare:speciality'] ?? 'General',
              distanceKm: double.parse(distance.toStringAsFixed(2)),
              bedCapacity: dummyDetails['bedCapacity'],
              availableBeds: dummyDetails['availableBeds'],
              facilities: List<String>.from(dummyDetails['facilities']),
              phone: dummyDetails['phone'],
            ));
          }
        }
        hospitals.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        return hospitals;
      } else {
        throw Exception("Failed to load hospitals from API");
      }
    } catch (e) {
      debugPrint("Error fetching hospitals: $e");
      return []; // Return empty list on error
    }
  }
}


// --- UNIFIED APP THEME & COLORS ---
class AppTheme {
  // Patient-Side Colors
  static const Color emergencyColor = Color(0xFFDC2626);
  static const Color laterColor = Color(0xFF7C3AED);
  static const Color processColor = Color(0xFF10B981);
  static const Color hospitalColor = Color(0xFF2563EB);

  // Driver-Side Colors
  static const Color driverAccessColor = Color(0xFF0F172A);
  static const Color ambulanceDetailsColor = Color(0xFF7C3AED);
  static const Color allBookingsColor = Color(0xFF78350F);
  static const Color feedbackColor = Color(0xFF15803D);
  static const Color logoutColor = Color(0xFFB91C1C);

  // Shared Colors
  static const Color homeColor = Color(0xFF0891B2); // Cyan
  static const Color secondaryColor = Color(0xFFF59E0B); // Amber
  static const Color surfaceColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);

  static Color getColorForFlow(BookingFlow flow) {
    return flow == BookingFlow.emergency ? emergencyColor : laterColor;
  }

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: surfaceColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: homeColor,
        primary: homeColor,
        secondary: driverAccessColor,
        surface: surfaceColor,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
        titleLarge: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textSecondary),
      ),
    );
  }
}

// --- TOP-LEVEL COMBINED APP ---
class CombinedMediRideApp extends StatelessWidget {
  const CombinedMediRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediRide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const AppSelectionScreen(),
    );
  }
}

// --- APP SELECTION SCREEN (Glass + Gradient style) ---
class AppSelectionScreen extends StatelessWidget {
  const AppSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.driverAccessColor,
      body: Stack(
        children: [
          // Gradient backdrop (same vibe as login pages)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.driverAccessColor,
                  AppTheme.driverAccessColor.withOpacity(0.88),
                  AppTheme.homeColor.withOpacity(0.55),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // Floating glow blobs
          const Positioned(
            top: -80,
            right: -40,
            child: _GlowBlob(size: 220, color: Colors.white54),
          ),
          const Positioned(
            bottom: -60,
            left: -50,
            child: _GlowBlob(size: 260, color: Colors.white38),
          ),

          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _GlassCard(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.emergency, color: Colors.white, size: 56),
                        const SizedBox(height: 12),
                        const Text(
                          'Welcome to MediRide',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your trusted medical transport service.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.9)),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Please select your role:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Patient
                        _RoleButton(
                          title: 'Patient',
                          subtitle: 'Book an ambulance or view hospitals',
                          icon: Icons.personal_injury,
                          background: AppTheme.hospitalColor,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PatientHomeScreen()),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Driver
                        _RoleButton(
                          title: 'Driver',
                          subtitle: 'Manage your vehicle and bookings',
                          icon: Icons.drive_eta,
                          background: AppTheme.driverAccessColor,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DriverAccessScreen()),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Hospital
                        _RoleButton(
                          title: 'Hospital',
                          subtitle: 'Manage facility details & availability',
                          icon: Icons.business,
                          background: AppTheme.feedbackColor,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HospitalLoginScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Mini glass + glow helpers (scoped to this file; no extra imports) ----
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double blur;
  final double opacity;

  const _GlassCard({
    required this.child,
    this.padding,
    this.borderRadius = 22,
    this.blur = 16,
    this.opacity = 0.12,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: size * 0.6,
              spreadRadius: size * 0.25,
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Role Button (glass-friendly card button) ----
class _RoleButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color background;
  final VoidCallback onTap;

  const _RoleButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.background,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background.withOpacity(0.18);
    final border = Colors.white.withOpacity(0.28);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: background.withOpacity(0.25),
                border: Border.all(color: Colors.white.withOpacity(0.35)),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }
}


class _UserTypeButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _UserTypeButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Icon(icon, color: color, size: 40),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: AppTheme.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// --- SHARED UTILITY WIDGETS ---
class NavButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color color;
  final IconData icon;
  final bool outlined;

  const NavButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.color,
    required this.icon,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: outlined
            ? OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, color: color),
          label: Text(
            text,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: color, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        )
            : ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white),
          label: Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
        ),
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const FeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium!),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey.shade400, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================================================================
// |                                                                     |
// |                   PATIENT APPLICATION CODE                          |
// |                                                                     |
// =======================================================================

// --- PATIENT UTILITY WIDGETS ---
class FlowStepContainer extends StatelessWidget {
  final Widget child;
  final Color themeColor;
  final String title;
  final String stepDescription;

  const FlowStepContainer({
    super.key,
    required this.child,
    required this.themeColor,
    required this.title,
    required this.stepDescription,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: themeColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Text(
                stepDescription,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

// --- 1. PATIENT HOME SCREEN ---
class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text('MediRide'),
        backgroundColor: AppTheme.homeColor,
        leading: IconButton( // <-- ADDED BACK BUTTON
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 16),
                const Text(
                  'How can we help you?',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your trusted ambulance service',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 32),
                FeatureCard(
                  title: 'Emergency Booking',
                  subtitle: 'Book ambulance immediately',
                  icon: Icons.local_hospital,
                  color: AppTheme.emergencyColor,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AutoTrackLocationScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                FeatureCard(
                  title: 'Schedule Booking',
                  subtitle: 'Book for a later date & time',
                  icon: Icons.calendar_month,
                  color: AppTheme.laterColor,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ManualBookingScreen()),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Explore',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                FeatureCard(
                  title: 'Nearby Hospitals',
                  subtitle: 'View hospitals in your area',
                  icon: Icons.corporate_fare,
                  color: AppTheme.hospitalColor,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ViewHospitalsScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                FeatureCard(
                  title: 'Map View',
                  subtitle: 'See hospitals on map',
                  icon: Icons.map,
                  color: AppTheme.secondaryColor,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OpenMapScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- 2. EMERGENCY BOOKING FLOW (Patient) ---
// ... (All emergency booking screens remain the same)
class AutoTrackLocationScreen extends StatelessWidget {
  const AutoTrackLocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Emergency Booking',
      stepDescription: 'Locating your position for fastest response',
      themeColor: AppTheme.emergencyColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.emergencyColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.my_location, size: 64, color: AppTheme.emergencyColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: AppTheme.emergencyColor),
                  const SizedBox(height: 16),
                  Text(
                    'Acquiring GPS coordinates...',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Location Acquired - Continue',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BookNearestAmbulanceScreen()),
            ),
            color: AppTheme.emergencyColor,
            icon: Icons.location_on,
          ),
        ],
      ),
    );
  }
}

class BookNearestAmbulanceScreen extends StatelessWidget {
  const BookNearestAmbulanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Emergency Booking',
      stepDescription: 'Searching for nearest available ambulance',
      themeColor: AppTheme.emergencyColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.emergencyColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search, size: 64, color: AppTheme.emergencyColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: AppTheme.emergencyColor),
                  const SizedBox(height: 16),
                  Text(
                    'Connecting to emergency services...',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Check Availability',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckAvailabilityScreen()),
            ),
            color: AppTheme.emergencyColor,
            icon: Icons.forward,
          ),
        ],
      ),
    );
  }
}

class CheckAvailabilityScreen extends StatelessWidget {
  const CheckAvailabilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Emergency Booking',
      stepDescription: 'Checking ambulance availability',
      themeColor: AppTheme.emergencyColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.emergencyColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline, size: 64, color: AppTheme.emergencyColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                'Verifying unit availability in your area',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Ambulance Available',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ConfirmBookingScreen(flow: BookingFlow.emergency),
              ),
            ),
            color: AppTheme.processColor,
            icon: Icons.check_circle,
          ),
          NavButton(
            text: 'No Ambulance Available',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PriorityQueueScreen()),
            ),
            color: AppTheme.laterColor,
            icon: Icons.error_outline,
            outlined: true,
          ),
        ],
      ),
    );
  }
}

class PriorityQueueScreen extends StatelessWidget {
  const PriorityQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Priority Queue',
      stepDescription: 'You have been added to priority queue',
      themeColor: AppTheme.laterColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.laterColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.queue, size: 64, color: AppTheme.laterColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Text(
                    'We are expanding our search radius to find an available ambulance for you.',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.laterColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Priority: HIGH',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.laterColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Expand Search Radius',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExpandRadiusScreen()),
            ),
            color: AppTheme.laterColor,
            icon: Icons.travel_explore,
          ),
        ],
      ),
    );
  }
}

class ExpandRadiusScreen extends StatelessWidget {
  const ExpandRadiusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Expanding Search',
      stepDescription: 'Searching wider area for available units',
      themeColor: AppTheme.laterColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.laterColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.radar, size: 64, color: AppTheme.laterColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: AppTheme.laterColor),
                  const SizedBox(height: 16),
                  Text(
                    'Scanning extended service area...',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Ambulance Found - Continue',
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const ConfirmBookingScreen(flow: BookingFlow.emergency),
              ),
            ),
            color: AppTheme.processColor,
            icon: Icons.check_circle,
          ),
          NavButton(
            text: 'No Ambulance Found',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelplineOptionScreen()),
            ),
            color: AppTheme.emergencyColor,
            icon: Icons.phone,
            outlined: true,
          ),
        ],
      ),
    );
  }
}

class HelplineOptionScreen extends StatelessWidget {
  const HelplineOptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Emergency Helpline',
      stepDescription: 'Immediate assistance required',
      themeColor: AppTheme.emergencyColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.emergencyColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_in_talk, size: 64, color: AppTheme.emergencyColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 48, color: AppTheme.emergencyColor),
                  const SizedBox(height: 16),
                  const Text(
                    'IMMEDIATE ACTION REQUIRED',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.emergencyColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No ambulance is currently available in your area. Please contact our 24/7 emergency helpline for immediate assistance.',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Call Emergency Helpline',
            onPressed: () {},
            color: AppTheme.emergencyColor,
            icon: Icons.call,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phone, color: AppTheme.emergencyColor),
                  const SizedBox(width: 12),
                  Text(
                    '999-000-111',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          NavButton(
            text: 'Return to Home',
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            color: AppTheme.homeColor,
            icon: Icons.home,
            outlined: true,
          ),
        ],
      ),
    );
  }
}


// --- 3. LATER BOOKING FLOW (Patient) ---
// ... (All later booking screens remain the same)
class ManualBookingScreen extends StatelessWidget {
  const ManualBookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Schedule Booking',
      stepDescription: 'Enter your booking details',
      themeColor: AppTheme.laterColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.laterColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit_calendar, size: 64, color: AppTheme.laterColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Pickup Location',
                      prefixIcon: const Icon(Icons.location_on),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Destination',
                      prefixIcon: const Icon(Icons.flag),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Date & Time',
                      prefixIcon: const Icon(Icons.access_time),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Search Available Ambulances',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FindAmbulanceLaterScreen()),
            ),
            color: AppTheme.laterColor,
            icon: Icons.search,
          ),
        ],
      ),
    );
  }
}

class FindAmbulanceLaterScreen extends StatelessWidget {
  const FindAmbulanceLaterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Finding Ambulance',
      stepDescription: 'Searching for your scheduled booking',
      themeColor: AppTheme.laterColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.laterColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search, size: 64, color: AppTheme.laterColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: AppTheme.laterColor),
                  const SizedBox(height: 16),
                  Text(
                    'Finding available ambulances for your scheduled time...',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Ambulance Found - Continue',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ConfirmBookingScreen(flow: BookingFlow.later),
              ),
            ),
            color: AppTheme.laterColor,
            icon: Icons.check_circle,
          ),
        ],
      ),
    );
  }
}


// --- 4. HOSPITAL & MAP FLOW (Patient) ---
class ViewHospitalsScreen extends StatefulWidget {
  const ViewHospitalsScreen({super.key});

  @override
  State<ViewHospitalsScreen> createState() => _ViewHospitalsScreenState();
}

class _ViewHospitalsScreenState extends State<ViewHospitalsScreen> {
  bool _isLoading = true;
  List<Hospital> _hospitals = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchNearbyHospitals();
  }

  Future<void> _fetchNearbyHospitals() async {
    try {
      // First, get user location
      var status = await Permission.location.request();
      if (!status.isGranted) {
        setState(() {
          _errorMessage = "Location permission is required to find nearby hospitals.";
          _isLoading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // Then, fetch hospitals from the API
      final hospitals = await HospitalApiService.getNearbyHospitals(position.latitude, position.longitude);

      setState(() {
        _hospitals = hospitals;
        _isLoading = false;
        if (_hospitals.isEmpty) {
          _errorMessage = "No hospitals found nearby.";
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = "An error occurred: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Nearby Hospitals',
      stepDescription: 'Hospitals found near your location',
      themeColor: AppTheme.hospitalColor,
      child: Column(
        children: [
          _buildBody(),
          const SizedBox(height: 24),
          NavButton(
            text: 'View on Map',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OpenMapScreen(hospitals: _hospitals)),
            ),
            color: AppTheme.hospitalColor,
            icon: Icons.map,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.hospitalColor));
    }
    if (_errorMessage.isNotEmpty) {
      return Center(child: Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)));
    }
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _hospitals.length,
        itemBuilder: (context, index) {
          final hospital = _hospitals[index];
          return _HospitalListItem(hospital: hospital);
        },
        separatorBuilder: (context, index) => const Divider(height: 1),
      ),
    );
  }
}


class _HospitalListItem extends StatelessWidget {
  final Hospital hospital;

  const _HospitalListItem({required this.hospital});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.hospitalColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.local_hospital, color: AppTheme.hospitalColor),
      ),
      title: Text(hospital.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          _BedAvailabilityIndicator(
            available: hospital.availableBeds,
            total: hospital.bedCapacity,
          ),
          const SizedBox(height: 6),
          if (hospital.facilities.isNotEmpty) _FacilitiesRow(facilities: hospital.facilities),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('${hospital.distanceKm} km', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
    );
  }
}

class _BedAvailabilityIndicator extends StatelessWidget {
  final int available;
  final int total;

  const _BedAvailabilityIndicator({required this.available, required this.total});

  @override
  Widget build(BuildContext context) {
    final double ratio = total > 0 ? available / total : 0;
    final color = ratio > 0.5 ? AppTheme.processColor : (ratio > 0.1 ? AppTheme.secondaryColor : AppTheme.emergencyColor);

    return Row(
      children: [
        Icon(Icons.bed, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          'Beds: $available / $total',
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }
}

class _FacilitiesRow extends StatelessWidget {
  final List<String> facilities;

  const _FacilitiesRow({required this.facilities});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: facilities.map((facility) => Chip(
        label: Text(facility, style: const TextStyle(fontSize: 10)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        backgroundColor: AppTheme.homeColor.withOpacity(0.1),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
      )).toList(),
    );
  }
}


class OpenMapScreen extends StatefulWidget {
  final List<Hospital> hospitals;
  const OpenMapScreen({super.key, this.hospitals = const []});

  @override
  State<OpenMapScreen> createState() => _OpenMapScreenState();
}

class _OpenMapScreenState extends State<OpenMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  String? _mapStyle;
  bool _isLoading = true;
  LatLng? _userLocation;

  static const CameraPosition _kKolkata = CameraPosition(
    target: LatLng(22.5726, 88.3639),
    zoom: 12.0,
  );

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndFetchLocation();
  }

  void _addHospitalMarkers(List<Hospital> hospitals) {
    for (final hospital in hospitals) {
      _markers.add(
        Marker(
          markerId: MarkerId(hospital.name + hospital.lat.toString()),
          position: LatLng(hospital.lat, hospital.lng),
          infoWindow: InfoWindow(
            title: hospital.name,
            snippet: 'Beds: ${hospital.availableBeds} / ${hospital.bedCapacity}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
  }

  Future<void> _checkPermissionsAndFetchLocation() async {
    setState(() => _isLoading = true);
    var status = await Permission.location.request();
    if (status.isGranted) {
      await _getUserLocation();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required.')),
        );
      }
      if (widget.hospitals.isNotEmpty) {
        _addHospitalMarkers(widget.hospitals);
        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(_createBounds(widget.hospitals), 50),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  LatLngBounds _createBounds(List<Hospital> places) {
    final lats = places.map((p) => p.lat);
    final lngs = places.map((p) => p.lng);
    return LatLngBounds(
      southwest: LatLng(lats.reduce(min), lngs.reduce(min)),
      northeast: LatLng(lats.reduce(max), lngs.reduce(max)),
    );
  }

  Future<void> _getUserLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _userLocation = LatLng(position.latitude, position.longitude);

      _markers.add(Marker(
        markerId: const MarkerId('user_location'),
        position: _userLocation!,
        infoWindow: const InfoWindow(title: 'Your Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
      ));

      List<Hospital> hospitalsToDisplay = widget.hospitals;
      if (hospitalsToDisplay.isEmpty) {
        hospitalsToDisplay = await HospitalApiService.getNearbyHospitals(_userLocation!.latitude, _userLocation!.longitude);
      }

      _addHospitalMarkers(hospitalsToDisplay);

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _userLocation!, zoom: 14.0),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not fetch location: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map View'),
        backgroundColor: AppTheme.hospitalColor,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _kKolkata,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_mapStyle != null) _mapController!.setMapStyle(_mapStyle);
            },
            markers: _markers,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.hospitalColor),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _checkPermissionsAndFetchLocation,
        label: const Text('My Location'),
        icon: const Icon(Icons.my_location),
        backgroundColor: AppTheme.hospitalColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
//... (Rest of the Patient and Driver code remains unchanged)
// The remaining code for ConfirmBooking, DriverAssigned, LiveTracking, PaymentFeedback,
// and all Driver screens are the same as the previous version. I have omitted them
// here for brevity but they should be included in the final file.
class ConfirmBookingScreen extends StatelessWidget {
  final BookingFlow flow;
  const ConfirmBookingScreen({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final String flowType = flow == BookingFlow.emergency ? 'Emergency' : 'Scheduled';
    final Color themeColor = AppTheme.getColorForFlow(flow);

    return FlowStepContainer(
      title: '$flowType Booking',
      stepDescription: 'Confirm your booking details',
      themeColor: themeColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.assignment_turned_in, size: 64, color: themeColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Booking Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _BookingDetailRow(
                    icon: Icons.local_hospital,
                    label: 'Service Type',
                    value: flowType,
                  ),
                  const SizedBox(height: 12),
                  _BookingDetailRow(
                    icon: Icons.location_on,
                    label: 'Pickup',
                    value: 'Current Location',
                  ),
                  const SizedBox(height: 12),
                  _BookingDetailRow(
                    icon: Icons.access_time,
                    label: 'Time',
                    value: flow == BookingFlow.emergency ? 'Immediate' : 'Scheduled',
                  ),
                  const SizedBox(height: 12),
                  _BookingDetailRow(
                    icon: Icons.payments,
                    label: 'Estimated Cost',
                    value: '\$45 - \$65',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Confirm Booking',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DriverAssignedScreen(flow: flow)),
            ),
            color: AppTheme.processColor,
            icon: Icons.check_circle,
          ),
          NavButton(
            text: 'Cancel',
            onPressed: () => Navigator.pop(context),
            color: Colors.grey.shade600,
            icon: Icons.close,
            outlined: true,
          ),
        ],
      ),
    );
  }
}

class _BookingDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _BookingDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class DriverAssignedScreen extends StatelessWidget {
  final BookingFlow flow;
  const DriverAssignedScreen({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Driver Assigned',
      stepDescription: 'Your ambulance is on the way',
      themeColor: AppTheme.processColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.processColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.drive_eta, size: 64, color: AppTheme.processColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppTheme.processColor.withOpacity(0.1),
                        child: const Icon(Icons.person, size: 32, color: AppTheme.processColor),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'John Doe',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'License: ABC-123',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.star, size: 16, color: AppTheme.secondaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  '4.9 (234 trips)',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.processColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.call, color: AppTheme.processColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.processColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.timer, color: AppTheme.processColor),
                        SizedBox(width: 8),
                        Text(
                          'ETA: 5 minutes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,

                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Track Live Location',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => LiveTrackingScreen(flow: flow)),
            ),
            color: AppTheme.processColor,
            icon: Icons.location_searching,
          ),
        ],
      ),
    );
  }
}

class LiveTrackingScreen extends StatefulWidget {
  final BookingFlow flow;
  const LiveTrackingScreen({super.key, required this.flow});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  GoogleMapController? _mapController;
  String? _mapStyle;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  StreamSubscription<Position>? _simulationTimer; // To listen to location updates
  BitmapDescriptor? _ambulanceIcon;

  // Initial fixed locations for simulation (Kolkata/nearish area for quick test)
  LatLng? _userLocation = const LatLng(22.5726, 88.3639); // User fixed at one spot
  LatLng? _ambulanceLocation = const LatLng(22.5958, 88.3697); // Ambulance starts elsewhere

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _startSimulation();
  }

  Future<void> _loadAssets() async {
    // A simple colored circle icon will be used for the ambulance marker
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()..color = AppTheme.processColor;
    canvas.drawCircle(const Offset(30, 30), 30, paint);
    final img = await pictureRecorder.endRecording().toImage(60, 60);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data != null) {
      _ambulanceIcon = BitmapDescriptor.fromBytes(data.buffer.asUint8List());
    }
  }

  void _startSimulation() async {
    _updateMarkers();

    // Simulate movement towards the user location every 2 seconds
    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_ambulanceLocation == null || _userLocation == null) return;

      // Simple linear interpolation for simulation
      double newLat = ui.lerpDouble(_ambulanceLocation!.latitude, _userLocation!.latitude, 0.15)!;
      double newLng = ui.lerpDouble(_ambulanceLocation!.longitude, _userLocation!.longitude, 0.15)!;

      setState(() {
        _ambulanceLocation = LatLng(newLat, newLng);
        _updateMarkers();
        _updatePolylines();
      });

      _mapController?.animateCamera(CameraUpdate.newLatLng(_ambulanceLocation!));

      // Stop simulation if distance is very close
      final distance = Geolocator.distanceBetween(
          _ambulanceLocation!.latitude, _ambulanceLocation!.longitude,
          _userLocation!.latitude, _userLocation!.longitude);
      if (distance < 100) {
        timer.cancel();
        setState(() {
          _ambulanceLocation = _userLocation; // Snap to final spot
          _updateMarkers();
        });
      }
    }) as StreamSubscription<Position>?;
  }

  void _updateMarkers() {
    _markers.clear();
    if (_userLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('user_location'),
        position: _userLocation!,
        infoWindow: const InfoWindow(title: 'Your Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
      ));
    }
    if (_ambulanceLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('ambulance_location'),
        position: _ambulanceLocation!,
        icon: _ambulanceIcon ?? BitmapDescriptor.defaultMarker,
        infoWindow: const InfoWindow(title: 'Ambulance'),
      ));
    }
  }

  void _updatePolylines() {
    _polylines.clear();
    if (_userLocation != null && _ambulanceLocation != null) {
      _polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: [_ambulanceLocation!, _userLocation!],
        color: AppTheme.processColor,
        width: 5,
      ));
    }
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlowStepContainer(
      title: 'Live Tracking',
      stepDescription: 'Track your ambulance in real-time',
      themeColor: AppTheme.processColor,
      child: Column(
        children: [
          Card(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 300,
                child: _userLocation == null ?
                const Center(child: CircularProgressIndicator()) :
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _userLocation!, zoom: 13),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if(_mapStyle != null) {
                      _mapController!.setMapStyle(_mapStyle);
                    }
                  },
                  markers: _markers,
                  polylines: _polylines,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  _TrackingStep(
                    icon: Icons.check_circle,
                    label: 'Driver Assigned',
                    isCompleted: true,
                  ),
                  _TrackingStep(
                    icon: Icons.local_shipping,
                    label: 'En Route to Pickup',
                    isCompleted: true,
                  ),
                  _TrackingStep(
                    icon: Icons.person,
                    label: 'Patient Pickup',
                    isCompleted: false,
                  ),
                  _TrackingStep(
                    icon: Icons.local_hospital,
                    label: 'Arriving at Hospital',
                    isCompleted: false,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Complete Journey',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PaymentFeedbackScreen(flow: widget.flow)),
            ),
            color: AppTheme.processColor,
            icon: Icons.check_circle,
          ),
        ],
      ),
    );
  }
}

class _TrackingStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isCompleted;
  final bool isLast;

  const _TrackingStep({
    required this.icon,
    required this.label,
    required this.isCompleted,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppTheme.processColor
                    : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCompleted ? Icons.check : icon,
                color: Colors.white,
                size: 20,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isCompleted
                    ? AppTheme.processColor
                    : Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isCompleted ? FontWeight.w600 : FontWeight.normal,
                color: isCompleted ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PaymentFeedbackScreen extends StatelessWidget {
  final BookingFlow flow;
  const PaymentFeedbackScreen({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final Color themeColor = AppTheme.getColorForFlow(flow);

    return FlowStepContainer(
      title: 'Trip Complete',
      stepDescription: 'Payment & Feedback',
      themeColor: themeColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.processColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, size: 64, color: AppTheme.processColor),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Text(
                    'Payment Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _PaymentRow(label: 'Base Fare', amount: '\$35.00'),
                  _PaymentRow(label: 'Distance (8.5 km)', amount: '\$15.00'),
                  _PaymentRow(label: 'Service Charge', amount: '\$5.00'),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '\$55.00',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: themeColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.processColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: AppTheme.processColor),
                        SizedBox(width: 12),
                        Text(
                          'Payment Successful',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.processColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Text(
                    'Rate Your Experience',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      5,
                          (index) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.star,
                          color: AppTheme.secondaryColor,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Share your feedback (optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Submit & Return Home',
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            color: AppTheme.homeColor,
            icon: Icons.home,
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String label;
  final String amount;

  const _PaymentRow({
    required this.label,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          Text(
            amount,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// =======================================================================
// |                                                                     |
// |                    DRIVER APPLICATION CODE                          |
// |                                                                     |
// =======================================================================


// --- DRIVER UTILITY WIDGETS ---
class AppScreenContainer extends StatelessWidget {
  final Widget child;
  final Color themeColor;
  final String title;

  const AppScreenContainer({
    super.key,
    required this.child,
    required this.themeColor,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: themeColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: child,
      ),
    );
  }
}




// Assumes you already have AppTheme and DriverHomeScreen.
// If you don’t, swap AppTheme.* with your own colors and change the navigation target.

class DriverAccessScreen extends StatefulWidget {
  const DriverAccessScreen({super.key});

  @override
  State<DriverAccessScreen> createState() => _DriverAccessScreenState();
}

class _DriverAccessScreenState extends State<DriverAccessScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _driverIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscure = true;
  bool _rememberMe = true;
  bool _loading = false;

  late final AnimationController _anim;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _float = Tween(begin: -6.0, end: 6.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_anim);
  }

  @override
  void dispose() {
    _driverIdCtrl.dispose();
    _passwordCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _loading = true);

    // Simulate auth; plug in your API here.
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() => _loading = false);

    // Navigate on success
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.driverAccessColor,
      body: Stack(
        children: [
          // Soft gradient backdrop
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.driverAccessColor,
                  AppTheme.driverAccessColor.withOpacity(0.85),
                  AppTheme.homeColor.withOpacity(0.65),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // Floating glow blobs
          Positioned(
            top: -80,
            right: -40,
            child: _GlowBlob(size: 220, color: Colors.white.withOpacity(0.12)),
          ),
          Positioned(
            bottom: -60,
            left: -50,
            child: _GlowBlob(size: 260, color: Colors.white.withOpacity(0.10)),
          ),

          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AnimatedBuilder(
                    animation: _float,
                    builder: (context, _) {
                      return Transform.translate(
                        offset: Offset(0, _float.value),
                        child: _GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Icon + Title
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Hero(
                                      tag: 'mediride-logo',
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white.withOpacity(0.12),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.25),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.local_hospital,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'MediRide Driver',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Please log in to continue',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withOpacity(0.85),
                                  ),
                                ),

                                const SizedBox(height: 28),
                                Form(
                                  key: _formKey,
                                  child: Column(
                                    children: [
                                      // Driver ID
                                      TextFormField(
                                        controller: _driverIdCtrl,
                                        textInputAction: TextInputAction.next,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: _inputDecoration(
                                          context,
                                          label: 'Driver ID',
                                          icon: Icons.person,
                                        ),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return 'Driver ID is required';
                                          }
                                          if (v.trim().length < 4) {
                                            return 'Enter a valid ID (min 4 chars)';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 14),

                                      // Password
                                      TextFormField(
                                        controller: _passwordCtrl,
                                        obscureText: _obscure,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: _inputDecoration(
                                          context,
                                          label: 'Password',
                                          icon: Icons.lock,
                                          trailing: IconButton(
                                            onPressed: () =>
                                                setState(() => _obscure = !_obscure),
                                            icon: Icon(
                                              _obscure
                                                  ? Icons.visibility
                                                  : Icons.visibility_off,
                                              color: Colors.white.withOpacity(0.9),
                                            ),
                                          ),
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty) {
                                            return 'Password is required';
                                          }
                                          if (v.length < 6) {
                                            return 'Minimum 6 characters';
                                          }
                                          return null;
                                        },
                                      ),

                                      const SizedBox(height: 10),

                                      // Remember + Forgot
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: _rememberMe,
                                            onChanged: (v) =>
                                                setState(() => _rememberMe = v ?? true),
                                            side: BorderSide(
                                              color: Colors.white.withOpacity(0.6),
                                            ),
                                            checkColor: AppTheme.homeColor,
                                            activeColor: Colors.white,
                                          ),
                                          Text(
                                            'Remember me',
                                            style: TextStyle(
                                              color:
                                              Colors.white.withOpacity(0.9),
                                            ),
                                          ),
                                          const Spacer(),
                                          TextButton(
                                            onPressed: () {
                                              // TODO: Forgot password flow
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                      'Forgot password coming soon'),
                                                ),
                                              );
                                            },
                                            child: Text(
                                              'Forgot?',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.95),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),

                                      // Login Button
                                      SizedBox(
                                        width: double.infinity,
                                        height: 54,
                                        child: ElevatedButton(
                                          onPressed: _loading ? null : _onLogin,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.homeColor,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.circular(16),
                                            ),
                                            elevation: 8,
                                            shadowColor:
                                            Colors.black.withOpacity(0.35),
                                          ),
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                                milliseconds: 250),
                                            child: _loading
                                                ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child:
                                              CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                                valueColor:
                                                AlwaysStoppedAnimation<
                                                    Color>(
                                                    Colors.white),
                                              ),
                                            )
                                                : Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Icon(Icons.login),
                                                SizedBox(width: 10),
                                                Text(
                                                  'Login',
                                                  style: TextStyle(
                                                    fontSize: 17,
                                                    fontWeight:
                                                    FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 18),

                                // Small helper / footer
                                Opacity(
                                  opacity: 0.9,
                                  child: Text(
                                    'By continuing you agree to our Terms & Privacy Policy.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
      BuildContext context, {
        required String label,
        required IconData icon,
        Widget? trailing,
      }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.9)),
      prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.95)),
      suffixIcon: trailing,
      filled: true,
      fillColor: Colors.white.withOpacity(0.08),
      hintStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.28)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white, width: 1.3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}





// --- 2. DRIVER HOME SCREEN ---
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _showRideRequest = true;

  void _handleDecline() {
    setState(() {
      _showRideRequest = false;
    });
  }

  void _handleAccept() {
    setState(() {
      _showRideRequest = false;
    });
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverRouteMapScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: AppTheme.homeColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
                  (route) => false,
            );
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showRideRequest)
              _RideRequestCard(
                onAccept: _handleAccept,
                onDecline: _handleDecline,
              ),
            const Text('Welcome, Driver!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            FeatureCard(
              title: 'Ambulance Details',
              subtitle: 'Update your vehicle information',
              icon: Icons.local_shipping,
              color: AppTheme.ambulanceDetailsColor,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AmbulanceDetailsScreen())),
            ),
            const SizedBox(height: 12),
            FeatureCard(
              title: 'All Bookings',
              subtitle: 'View current and past trips',
              icon: Icons.history,
              color: AppTheme.allBookingsColor,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllBookingsScreen())),
            ),
            const SizedBox(height: 12),
            FeatureCard(
              title: 'Feedback',
              subtitle: 'Provide feedback about the service',
              icon: Icons.feedback,
              color: AppTheme.feedbackColor,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverFeedbackScreen())),
            ),
            const SizedBox(height: 48),
            NavButton(
              text: 'Logout',
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
                      (route) => false,
                );
              },
              color: AppTheme.logoutColor,
              icon: Icons.logout,
            ),
          ],
        ),
      ),
    );
  }
}

class _RideRequestCard extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RideRequestCard({required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.emergencyColor.withOpacity(0.05),
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New Ride Request!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.emergencyColor),
            ),
            const Divider(height: 24),
            _buildDetailRow(icon: Icons.person, label: 'Patient:', value: 'Subhojit'),
            const SizedBox(height: 12),
            _buildDetailRow(icon: Icons.location_on, label: 'From:', value: 'Adi Saptagram, Bandel'),
            const SizedBox(height: 12),
            _buildDetailRow(icon: Icons.flag, label: 'To:', value: 'Chandannagar Sub Divisional Hospital, Chandannagar'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onDecline,
                    icon: const Icon(Icons.close),
                    label: const Text('Decline'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade300,
                      foregroundColor: Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Accept'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.processColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({required IconData icon, required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    );
  }
}

class DriverRouteMapScreen extends StatefulWidget {
  const DriverRouteMapScreen({super.key});

  @override
  State<DriverRouteMapScreen> createState() => _DriverRouteMapScreenState();
}

class _DriverRouteMapScreenState extends State<DriverRouteMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isNavigating = false;
  StreamSubscription<Position>? _positionStreamSubscription;
  List<LatLng> _routePoints = [];
  BitmapDescriptor _driverIcon = BitmapDescriptor.defaultMarker;

  static const LatLng destinationLocation = LatLng(22.8669385,88.3695814); // north city hospital

  @override
  void initState() {
    super.initState();
    _createDriverIcon();
    _fetchAndDrawRoute();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _createDriverIcon() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()..color = AppTheme.driverAccessColor;
    const double size = 60.0; // Icon size

    final Path path = Path();
    path.moveTo(size / 2, 0);
    path.lineTo(size, size);
    path.lineTo(size / 2, size * 0.75);
    path.lineTo(0, size);
    path.close();

    canvas.drawPath(path, paint);

    final img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data != null) {
      _driverIcon = BitmapDescriptor.fromBytes(data.buffer.asUint8List());
    }
  }

  Future<List<LatLng>> _decodePolyline(String encoded) async {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLng((lat / 1E5), (lng / 1E5)));
    }
    return points;
  }

  Future<List<LatLng>> _getRouteFromOsrm(LatLng start, LatLng end) async {
    final url = 'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=polyline';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final geometry = data['routes'][0]['geometry'];
      return await _decodePolyline(geometry);
    } else {
      throw Exception('Failed to load route from OSRM');
    }
  }

  Future<void> _fetchAndDrawRoute() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _markers.clear();
      _polylines.clear();
    });

    try {
      var status = await Permission.location.request();
      if (!status.isGranted) {
        setState(() {
          _errorMessage = "Location permission is required.";
          _isLoading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final driverLocation = LatLng(position.latitude, position.longitude);

      _routePoints = await _getRouteFromOsrm(driverLocation, destinationLocation);

      setState(() {
        _markers.add(
          Marker(
            markerId: const MarkerId('driver'),
            position: driverLocation,
            icon: _driverIcon,
            anchor: const Offset(0.5, 0.5),
            flat: true,
            rotation: position.heading,
          ),
        );
        _markers.add(
          Marker(
            markerId: const MarkerId('destination'),
            position: destinationLocation,
            infoWindow: const InfoWindow(title: 'Pickup: Naihati Municipality'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ),
        );
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: _routePoints,
            color: AppTheme.hospitalColor,
            width: 5,
          ),
        );
        _isLoading = false;
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(min(driverLocation.latitude, destinationLocation.latitude), min(driverLocation.longitude, destinationLocation.longitude)),
            northeast: LatLng(max(driverLocation.latitude, destinationLocation.latitude), max(driverLocation.longitude, destinationLocation.longitude)),
          ),
          100.0,
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = "Error: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  void _startNavigation() {
    if (_routePoints.isEmpty) return;

    setState(() {
      _isNavigating = true;
    });

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      final driverLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _markers.removeWhere((m) => m.markerId.value == 'driver');
        _markers.add(
          Marker(
            markerId: const MarkerId('driver'),
            position: driverLatLng,
            icon: _driverIcon,
            rotation: position.heading,
            anchor: const Offset(0.5, 0.5),
            flat: true,
          ),
        );
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: driverLatLng,
            zoom: 18.0,
            tilt: 50.0,
            bearing: position.heading,
          ),
        ),
      );
    });
  }

  void _stopNavigation() {
    _positionStreamSubscription?.cancel();
    setState(() {
      _isNavigating = false;
    });
    if (_routePoints.isNotEmpty) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(min(_routePoints.first.latitude, destinationLocation.latitude), min(_routePoints.first.longitude, destinationLocation.longitude)),
            northeast: LatLng(max(_routePoints.first.latitude, destinationLocation.latitude), max(_routePoints.first.longitude, destinationLocation.longitude)),
          ),
          100.0,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route to Pickup'),
        backgroundColor: AppTheme.driverAccessColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(_errorMessage, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
      ))
          : GoogleMap(
        initialCameraPosition: const CameraPosition(target: destinationLocation, zoom: 11),
        onMapCreated: (controller) => _mapController = controller,
        markers: _markers,
        polylines: _polylines,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
      ),
      floatingActionButton: _isLoading || _errorMessage.isNotEmpty
          ? null
          : FloatingActionButton.extended(
        onPressed: _isNavigating ? _stopNavigation : _startNavigation,
        label: Text(_isNavigating ? 'Stop Navigation' : 'Start Navigation'),
        icon: Icon(_isNavigating ? Icons.stop : Icons.navigation),
        backgroundColor: _isNavigating ? Colors.red.shade700 : AppTheme.driverAccessColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}


// --- 3. AMBULANCE DETAILS FLOW ---
class AmbulanceDetailsScreen extends StatefulWidget {
  const AmbulanceDetailsScreen({super.key});

  @override
  State<AmbulanceDetailsScreen> createState() => _AmbulanceDetailsScreenState();
}

class _AmbulanceDetailsScreenState extends State<AmbulanceDetailsScreen> {
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  // pick image from camera or gallery
  Future<void> _pickImage(ImageSource source) async {
    final permission = source == ImageSource.camera
        ? Permission.camera
        : (Platform.isAndroid ? Permission.photos : Permission.storage);

    var status = await permission.status;

    if (status.isDenied) {
      status = await permission.request();
    }

    if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Permission permanently denied. Open settings to enable it.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: openAppSettings,
          ),
        ),
      );
      return;
    }

    if (status.isGranted) {
      try {
        final XFile? pickedFile = await _picker.pickImage(source: source);
        if (pickedFile != null) {
          setState(() {
            _imageFile = File(pickedFile.path);
          });
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ambulance Details'),
        backgroundColor: Colors.red,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Ambulance Picture',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _imageFile != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    _imageFile!,
                    fit: BoxFit.cover,
                  ),
                )
                    : const Center(
                  child: Icon(Icons.local_shipping, size: 64, color: Colors.black45),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                // 📸 TAKE PHOTO BUTTON
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00C853), Color(0xFF00E676)], // emerald tones
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                      label: const Text(
                        'Take Photo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _pickImage(ImageSource.camera),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // 🖼️ BROWSE PHOTO BUTTON
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3D5AFE), Color(0xFF6200EA)], // blue-purple tones
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.photo_library, color: Colors.white, size: 24),
                      label: const Text(
                        'Browse Photo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _pickImage(ImageSource.gallery),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            NavButton(
              text: 'Next: Add Details',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddAmbulanceDetailsPage()),
              ),
              color: AppTheme.ambulanceDetailsColor,
              icon: Icons.arrow_forward,
            ),
          ],
        ),
      ),
    );
  }
}
class AddAmbulanceDetailsPage extends StatelessWidget {
  const AddAmbulanceDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreenContainer(
      title: 'Add Ambulance Details',
      themeColor: AppTheme.ambulanceDetailsColor,
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(labelText: 'Vehicle Number', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(labelText: 'Vehicle Model', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(labelText: 'License Plate', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Save Details',
            onPressed: () {
              // Pop back to the driver home screen
              Navigator.popUntil(context, (Route<dynamic> route) => route.isFirst);
            },
            color: AppTheme.processColor,
            icon: Icons.save,
          ),
        ],
      ),
    );
  }
}

// --- 4. ALL BOOKINGS SCREEN ---
// --- DATA MODEL FOR BOOKINGS (for demonstration) ---
class _BookingInfo {
  final String patientName;
  final String from;
  final String to;
  final DateTime dateTime;
  final bool isCompleted;
  final String? fare;

  _BookingInfo({
    required this.patientName,
    required this.from,
    required this.to,
    required this.dateTime,
    this.isCompleted = false,
    this.fare,
  });
}

// --- 4. ALL BOOKINGS SCREEN ---
class AllBookingsScreen extends StatelessWidget {
  const AllBookingsScreen({super.key});

  // Dummy data for demonstration
  static final List<_BookingInfo> _allBookings = [
    _BookingInfo(
      patientName: "Alice",
      from: "Current Location (User)",
      to: "City Hospital",
      dateTime: DateTime(2025, 10, 15, 11, 0),
    ),
    _BookingInfo(
      patientName: "User 1",
      from: "Pickup Point A",
      to: "Destination B",
      dateTime: DateTime(2025, 10, 14, 15, 30),
    ),
    _BookingInfo(
      patientName: "User 2",
      from: "Howrah Station",
      to: "NRS Medical College",
      dateTime: DateTime(2025, 10, 8, 9, 15),
      isCompleted: true,
      fare: "\$45.00",
    ),
    _BookingInfo(
      patientName: "User 3",
      from: "Salt Lake Sector V",
      to: "City General Hospital",
      dateTime: DateTime(2025, 10, 2, 18, 0),
      isCompleted: true,
      fare: "\$55.00",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final upcomingBookings = _allBookings.where((b) => !b.isCompleted).toList();
    final pastBookings = _allBookings.where((b) => b.isCompleted).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('All Bookings'),
          backgroundColor: AppTheme.allBookingsColor,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontSize: 16),
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),

            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Upcoming Bookings Tab
            upcomingBookings.isEmpty
                ? const _EmptyBookingView(message: "You have no upcoming rides.")
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: upcomingBookings.length,
              itemBuilder: (context, index) {
                return _BookingListItem(booking: upcomingBookings[index]);
              },
            ),
            // Past Bookings Tab
            pastBookings.isEmpty
                ? const _EmptyBookingView(message: "You have no past rides.")
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pastBookings.length,
              itemBuilder: (context, index) {
                return _BookingListItem(booking: pastBookings[index]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// --- HELPER WIDGETS FOR BOOKING LIST ---

class _BookingListItem extends StatelessWidget {
  final _BookingInfo booking;

  const _BookingListItem({required this.booking});

  @override
  Widget build(BuildContext context) {
    final month = "${booking.dateTime.month}".padLeft(2, '0');
    final day = "${booking.dateTime.day}".padLeft(2, '0');
    final hour = "${booking.dateTime.hour}".padLeft(2, '0');
    final minute = "${booking.dateTime.minute}".padLeft(2, '0');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Date Column
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    day,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.allBookingsColor),
                  ),
                  Text(
                    month,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Details Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.patientName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _RouteInfoRow(icon: Icons.my_location, location: booking.from),
                  const SizedBox(height: 4),
                  _RouteInfoRow(icon: Icons.flag, location: booking.to),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Status/Fare Column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BookingStatusChip(isCompleted: booking.isCompleted),
                const SizedBox(height: 8),
                booking.isCompleted
                    ? Text(
                  booking.fare ?? '',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                )
                    : Text(
                  '$hour:$minute',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteInfoRow extends StatelessWidget {
  final IconData icon;
  final String location;

  const _RouteInfoRow({required this.icon, required this.location});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            location,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _BookingStatusChip extends StatelessWidget {
  final bool isCompleted;

  const _BookingStatusChip({required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isCompleted ? AppTheme.processColor.withOpacity(0.1) : AppTheme.secondaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isCompleted ? 'Completed' : 'Upcoming',
        style: TextStyle(
          color: isCompleted ? AppTheme.processColor : AppTheme.secondaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyBookingView extends StatelessWidget {
  final String message;
  const _EmptyBookingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}


// --- 5. DRIVER FEEDBACK SCREEN ---
class DriverFeedbackScreen extends StatelessWidget {
  const DriverFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreenContainer(
      title: 'Submit Feedback',
      themeColor: AppTheme.feedbackColor,
      child: Column(
        children: [
          const Icon(Icons.feedback, size: 64, color: AppTheme.feedbackColor),
          const SizedBox(height: 16),
          const Text('We value your feedback to improve our service.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'Enter your feedback here...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          NavButton(
            text: 'Submit Feedback',
            onPressed: () {
              Navigator.pop(context);
            },
            color: AppTheme.feedbackColor,
            icon: Icons.send,
          ),
        ],
      ),
    );
  }
}


// =======================================================================
// |                                                                     |
// |                   HOSPITAL APPLICATION CODE                         |
// |                                                                     |
// =======================================================================



// Assumes you already have AppTheme and HospitalDashboardScreen.
// If not, sample placeholders are at the bottom so this file runs standalone.

class HospitalLoginScreen extends StatefulWidget {
  const HospitalLoginScreen({super.key});

  @override
  State<HospitalLoginScreen> createState() => _HospitalLoginScreenState();
}

class _HospitalLoginScreenState extends State<HospitalLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _hospitalIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscure = true;
  bool _rememberMe = true;
  bool _loading = false;

  late final AnimationController _anim;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _float = Tween(begin: -6.0, end: 6.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_anim);
  }

  @override
  void dispose() {
    _hospitalIdCtrl.dispose();
    _passwordCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _loading = true);
    // TODO: plug in your auth call here.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    setState(() => _loading = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HospitalDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.driverAccessColor,
      body: Stack(
        children: [
          // Gradient backdrop
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.driverAccessColor,
                  AppTheme.driverAccessColor.withOpacity(0.85),
                  AppTheme.feedbackColor.withOpacity(0.55),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // Floating glow blobs
          Positioned(
            top: -90,
            right: -40,
            child: _GlowBlob(size: 230, color: Colors.white.withOpacity(0.12)),
          ),
          Positioned(
            bottom: -70,
            left: -60,
            child: _GlowBlob(size: 280, color: Colors.white.withOpacity(0.10)),
          ),

          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AnimatedBuilder(
                    animation: _float,
                    builder: (context, _) {
                      return Transform.translate(
                        offset: Offset(0, _float.value),
                        child: _GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Hero(
                                      tag: 'mediride-hospital-logo',
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white.withOpacity(0.12),
                                          border: Border.all(
                                            color:
                                            Colors.white.withOpacity(0.25),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.local_hospital,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'MediRide for Hospitals',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Manage your facility details',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withOpacity(0.85),
                                  ),
                                ),

                                const SizedBox(height: 28),
                                Form(
                                  key: _formKey,
                                  child: Column(
                                    children: [
                                      // Hospital ID
                                      TextFormField(
                                        controller: _hospitalIdCtrl,
                                        textInputAction: TextInputAction.next,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: _inputDecoration(
                                          context,
                                          label: 'Hospital ID',
                                          icon: Icons.account_balance, // business icon
                                        ),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return 'Hospital ID is required';
                                          }
                                          if (v.trim().length < 4) {
                                            return 'Enter a valid ID (min 4 chars)';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 14),

                                      // Password
                                      TextFormField(
                                        controller: _passwordCtrl,
                                        obscureText: _obscure,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: _inputDecoration(
                                          context,
                                          label: 'Password',
                                          icon: Icons.lock,
                                          trailing: IconButton(
                                            onPressed: () =>
                                                setState(() => _obscure = !_obscure),
                                            icon: Icon(
                                              _obscure
                                                  ? Icons.visibility
                                                  : Icons.visibility_off,
                                              color: Colors.white.withOpacity(0.9),
                                            ),
                                          ),
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty) {
                                            return 'Password is required';
                                          }
                                          if (v.length < 6) {
                                            return 'Minimum 6 characters';
                                          }
                                          return null;
                                        },
                                      ),

                                      const SizedBox(height: 10),

                                      // Remember + Forgot
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: _rememberMe,
                                            onChanged: (v) =>
                                                setState(() => _rememberMe = v ?? true),
                                            side: BorderSide(
                                              color: Colors.white.withOpacity(0.6),
                                            ),
                                            checkColor: AppTheme.feedbackColor,
                                            activeColor: Colors.white,
                                          ),
                                          Text(
                                            'Remember me',
                                            style: TextStyle(
                                              color:
                                              Colors.white.withOpacity(0.9),
                                            ),
                                          ),
                                          const Spacer(),
                                          TextButton(
                                            onPressed: () {
                                              // TODO: Forgot password flow
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                      'Forgot password coming soon'),
                                                ),
                                              );
                                            },
                                            child: Text(
                                              'Forgot?',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.95),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),

                                      // Login Button
                                      SizedBox(
                                        width: double.infinity,
                                        height: 54,
                                        child: ElevatedButton(
                                          onPressed: _loading ? null : _onLogin,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.feedbackColor,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.circular(16),
                                            ),
                                            elevation: 8,
                                            shadowColor:
                                            Colors.black.withOpacity(0.35),
                                          ),
                                          child: AnimatedSwitcher(
                                            duration:
                                            const Duration(milliseconds: 250),
                                            child: _loading
                                                ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child:
                                              CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                                valueColor:
                                                AlwaysStoppedAnimation<
                                                    Color>(
                                                    Colors.white),
                                              ),
                                            )
                                                : Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Icon(Icons.login),
                                                SizedBox(width: 10),
                                                Text(
                                                  'Login',
                                                  style: TextStyle(
                                                    fontSize: 17,
                                                    fontWeight:
                                                    FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 18),

                                // Footer note
                                Opacity(
                                  opacity: 0.9,
                                  child: Text(
                                    'By continuing you agree to our Terms & Privacy Policy.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
      BuildContext context, {
        required String label,
        required IconData icon,
        Widget? trailing,
      }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.9)),
      prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.95)),
      suffixIcon: trailing,
      filled: true,
      fillColor: Colors.white.withOpacity(0.08),
      hintStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.28)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white, width: 1.3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.redAccent.shade100),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}





// --- 2. ENHANCED HOSPITAL DASHBOARD SCREEN ---
// --- Update Bed Availability Screen ---
class UpdateBedAvailabilityScreen extends StatefulWidget {
  final Hospital hospital;
  const UpdateBedAvailabilityScreen({super.key, required this.hospital});

  @override
  State<UpdateBedAvailabilityScreen> createState() => _UpdateBedAvailabilityScreenState();
}

class _UpdateBedAvailabilityScreenState extends State<UpdateBedAvailabilityScreen> {
  late TextEditingController _controller;
  late int _availableBeds;

  @override
  void initState() {
    super.initState();
    _availableBeds = widget.hospital.availableBeds;
    _controller = TextEditingController(text: _availableBeds.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Bed Availability'),
        backgroundColor: AppTheme.hospitalColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text('Current Beds Available:', style: TextStyle(fontSize: 16)),
                    Text(
                      '${widget.hospital.availableBeds} / ${widget.hospital.bedCapacity}',
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.hospitalColor),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'New Available Beds',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _availableBeds = int.tryParse(value) ?? widget.hospital.availableBeds;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.hospitalColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  if (_availableBeds >= 0 && _availableBeds <= widget.hospital.bedCapacity) {
                    Navigator.pop(context, _availableBeds); // Return the new count
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid bed count.')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Manage Facilities Screen ---
class ManageFacilitiesScreen extends StatefulWidget {
  final List<String> currentFacilities;
  const ManageFacilitiesScreen({super.key, required this.currentFacilities});

  @override
  State<ManageFacilitiesScreen> createState() => _ManageFacilitiesScreenState();
}

class _ManageFacilitiesScreenState extends State<ManageFacilitiesScreen> {
  late List<String> _selectedFacilities;
  final List<String> _allPossibleFacilities = ['Emergency', 'ICU', 'Radiology', 'Pharmacy', 'Cardiology', 'Neurology', 'Oncology', 'Pediatrics', 'Neurosurgery'];

  @override
  void initState() {
    super.initState();
    _selectedFacilities = List<String>.from(widget.currentFacilities);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Facilities'),
        backgroundColor: AppTheme.hospitalColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select all applicable specialties:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: _allPossibleFacilities.map((facility) {
                  final isSelected = _selectedFacilities.contains(facility);
                  return CheckboxListTile(
                    title: Text(facility),
                    value: isSelected,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value ?? false) {
                          _selectedFacilities.add(facility);
                        } else {
                          _selectedFacilities.remove(facility);
                        }
                      });
                    },
                    activeColor: AppTheme.hospitalColor,
                  );
                }).toList(),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.done),
                label: const Text('Save Facilities'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.hospitalColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(context, _selectedFacilities);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HospitalDashboardScreen extends StatefulWidget {
  const HospitalDashboardScreen({super.key});

  @override
  State<HospitalDashboardScreen> createState() => _HospitalDashboardScreenState();
}

class _HospitalDashboardScreenState extends State<HospitalDashboardScreen> {
  Hospital? _hospital;
  bool _isLoading = true;
  int _incomingPatients = 3; // Mock data
  int _dischargedToday = 7; // Mock data

  @override
  void initState() {
    super.initState();
    _loadHospitalData();
  }

  void _loadHospitalData() {
    final details = HospitalApiService._generateDummyDetails("City General Hospital");
    setState(() {
      _hospital = Hospital(
        name: "City General Hospital",
        lat: 22.5852,
        lng: 88.3656,
        specialty: "Multi-Specialty",
        distanceKm: 0,
        bedCapacity: details['bedCapacity'],
        availableBeds: details['availableBeds'],
        facilities: List<String>.from(details['facilities']),
        phone: details['phone'],
      );
      _isLoading = false;
    });
  }

  void _updateBeds(int newBedCount) {
    setState(() {
      _hospital?.availableBeds = newBedCount;
    });
  }

  void _updateFacilities(List<String> newFacilities) {
    setState(() {
      _hospital?.facilities = newFacilities;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hospital Dashboard'),
        backgroundColor: AppTheme.feedbackColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
                (route) => false,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('3 new ambulance requests')),
              );
            },
          ),
        ],
      ),
      body: _isLoading || _hospital == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () async {
          _loadHospitalData();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHospitalHeader(),
              const SizedBox(height: 24),
              _buildQuickStatsRow(),
              const SizedBox(height: 24),
              _buildBedManagementCard(),
              const SizedBox(height: 16),
              _buildFacilitiesCard(),
              const SizedBox(height: 16),
              _buildEmergencyStatusCard(),
              const SizedBox(height: 16),
              _buildQuickActions(),
              const SizedBox(height: 24),
              NavButton(
                text: 'Logout',
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
                      (route) => false,
                ),
                color: AppTheme.logoutColor,
                icon: Icons.logout,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHospitalHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppTheme.feedbackColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.local_hospital, size: 32, color: AppTheme.feedbackColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _hospital!.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hospital!.specialty,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        _hospital!.phone,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.people,
            label: 'Incoming',
            value: _incomingPatients.toString(),
            color: AppTheme.secondaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle,
            label: 'Discharged',
            value: _dischargedToday.toString(),
            color: AppTheme.processColor,
          ),
        ),
      ],
    );
  }

  Widget _buildBedManagementCard() {
    final occupancyRate = ((_hospital!.bedCapacity - _hospital!.availableBeds) / _hospital!.bedCapacity * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Bed Management",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getBedStatusColor(_hospital!.availableBeds, _hospital!.bedCapacity).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$occupancyRate% Occupied',
                    style: TextStyle(
                      color: _getBedStatusColor(_hospital!.availableBeds, _hospital!.bedCapacity),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Bed visualization
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BedInfoColumn(
                  label: 'Total',
                  value: _hospital!.bedCapacity.toString(),
                  color: Colors.grey.shade400,
                ),
                _BedInfoColumn(
                  label: 'Available',
                  value: _hospital!.availableBeds.toString(),
                  color: AppTheme.processColor,
                ),
                _BedInfoColumn(
                  label: 'Occupied',
                  value: (_hospital!.bedCapacity - _hospital!.availableBeds).toString(),
                  color: AppTheme.emergencyColor,
                ),
              ],
            ),
            const SizedBox(height: 16),

            LinearProgressIndicator(
              value: _hospital!.availableBeds / _hospital!.bedCapacity,
              backgroundColor: AppTheme.emergencyColor.withOpacity(0.3),
              color: AppTheme.processColor,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text("Update Bed Count"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.feedbackColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  final result = await Navigator.push<int>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UpdateBedAvailabilityScreen(hospital: _hospital!),
                    ),
                  );
                  if (result != null) {
                    _updateBeds(result);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacilitiesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Available Facilities",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _hospital!.facilities.map((facility) => Chip(
                label: Text(facility),
                avatar: const Icon(Icons.check_circle, size: 16, color: AppTheme.processColor),
                backgroundColor: AppTheme.processColor.withOpacity(0.1),
                side: BorderSide.none,
              )).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text("Manage Facilities"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.ambulanceDetailsColor,
                  side: const BorderSide(color: AppTheme.ambulanceDetailsColor, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  final result = await Navigator.push<List<String>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManageFacilitiesScreen(
                        currentFacilities: List<String>.from(_hospital!.facilities),
                      ),
                    ),
                  );
                  if (result != null) {
                    _updateFacilities(result);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyStatusCard() {
    return Card(
      color: AppTheme.emergencyColor.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.emergencyColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.emergency, color: AppTheme.emergencyColor, size: 32),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emergency Status',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Emergency department operational',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Switch(
              value: true,
              activeColor: AppTheme.processColor,
              onChanged: (value) {
                // Toggle emergency status
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        FeatureCard(
          title: 'View Incoming Ambulances',
          subtitle: '$_incomingPatients ambulances en route',
          icon: Icons.local_shipping,
          color: AppTheme.secondaryColor,
          onTap: () {
            // Navigate to incoming ambulances screen
          },
        ),
        const SizedBox(height: 12),
        FeatureCard(
          title: 'Patient Records',
          subtitle: 'Manage patient information',
          icon: Icons.folder_shared,
          color: AppTheme.hospitalColor,
          onTap: () {
            // Navigate to patient records
          },
        ),
        const SizedBox(height: 12),
        FeatureCard(
          title: 'Staff Directory',
          subtitle: 'View and manage hospital staff',
          icon: Icons.badge,
          color: AppTheme.ambulanceDetailsColor,
          onTap: () {
            // Navigate to staff directory
          },
        ),
      ],
    );
  }

  Color _getBedStatusColor(int available, int total) {
    final ratio = available / total;
    if (ratio > 0.5) return AppTheme.processColor;
    if (ratio > 0.2) return AppTheme.secondaryColor;
    return AppTheme.emergencyColor;
  }
}

// Helper Widget for Stats Cards
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper Widget for Bed Info Columns
class _BedInfoColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BedInfoColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// Helper function for OpenMapScreen
double min(double a, double b) => a < b ? a : b;
double max(double a, double b) => a > b ? a : b;