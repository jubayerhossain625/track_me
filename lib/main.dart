import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_background/flutter_background.dart' as fb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(const TrackMeApp());
}

class TrackMeApp extends StatelessWidget {
  const TrackMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Track Me',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const TrackMeHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TrackMeHomePage extends StatefulWidget {
  const TrackMeHomePage({super.key});

  @override
  State<TrackMeHomePage> createState() => _TrackMeHomePageState();
}

class _TrackMeHomePageState extends State<TrackMeHomePage> {
  final Completer<GoogleMapController> _controller = Completer();
  LocationData? _currentLocation;
  final Location _location = Location();
  LatLng? _destination;
  bool _alertShown = false;
  final double _range = 100; // meters
  bool _isTracking = false; // Flag to control loop
  Timer? _timer; // Timer for the loop

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _startBackgroundExecution();
    _initLocation();
  }

  Future<void> _startBackgroundExecution() async {
    var androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Track Me",
      notificationText: "Tracking in background...",
      notificationImportance: fb.AndroidNotificationImportance.high,
      notificationIcon: fb.AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
    );

    final initialized = await FlutterBackground.initialize(androidConfig: androidConfig);
    if (initialized) {
      await FlutterBackground.enableBackgroundExecution();
    } else {
      debugPrint("Background initialization failed.");
    }
  }

  Future<void> _initLocation() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted &&
          permissionGranted != PermissionStatus.grantedLimited) {
        return;
      }
    }

    try {
      await _location.enableBackgroundMode(enable: true);
    } catch (e) {
      debugPrint('Background mode not granted: $e');
    }

    _location.onLocationChanged.listen((locationData) {
      setState(() {
        _currentLocation = locationData;
      });
      _checkProximity();
    });
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await flutterLocalNotificationsPlugin.initialize(settings);
  }

  Future<void> _showNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'proximity_channel',
      'Proximity Alert',
      importance: Importance.max,
      priority: Priority.high,
    );

    const platformDetails = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      'You are close!',
      'You\'re within 100m of your destination.',
      platformDetails,
    );
  }

  void _checkProximity() async {
    if (_currentLocation != null && _destination != null) {
      final distance = Geolocator.distanceBetween(
        _currentLocation!.latitude!,
        _currentLocation!.longitude!,
        _destination!.latitude,
        _destination!.longitude,
      );

      if (distance <= _range) {

        print("----------------- Are You Closer -------------------------------");
        // Trigger vibration and notification only once
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 1000);
        }
        await _showNotification();
        _playBackgroundMusic();
        setState(() {
          _alertShown = true;
        });
      }
    }
  }

  // Start the continuous loop
  void _startLoop() {
    _isTracking = true;
    _timer = Timer.periodic(const Duration(milliseconds: 4200), (timer) {
      _checkProximity(); // Check proximity every 3 seconds
    });
  }

  // Stop the continuous loop
  void _stopLoop() {
    _isTracking = false;
    _timer?.cancel();
  }
// Create an AudioPlayer instance

  void _playBackgroundMusic() async {
    // Play music (ensure to have a valid URL or local asset)
    _audioPlayer.play(UrlSource('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3')); // You can change the URL or use a local asset
      print("Music started playing.");
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:  AppBar(title: Text("Track Me")),
      body: _currentLocation == null
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(
              _currentLocation!.latitude!, _currentLocation!.longitude!),
          zoom: 16,
        ),
        onMapCreated: (controller) => _controller.complete(controller),
        onTap: (latLng) {
          setState(() {
            _destination = latLng;
            _alertShown = false; // Reset the alert if a new destination is tapped
          });
        },
        markers: {
          Marker(
            markerId: const MarkerId("current"),
            position: LatLng(
                _currentLocation!.latitude!, _currentLocation!.longitude!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: const InfoWindow(title: 'You'),
          ),
          if (_destination != null)
            Marker(
              markerId: const MarkerId("destination"),
              position: _destination!,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: const InfoWindow(title: 'Destination'),
            ),
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_isTracking) {
            _stopLoop(); // Stop the loop if it's already running
          } else {
            _startLoop(); // Start the loop
          }
        },
        child: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
      ),
    );
  }
}