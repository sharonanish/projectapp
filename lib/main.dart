import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';

// ===== CRITICAL: Renamed import to avoid conflict =====
final fln.FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    fln.FlutterLocalNotificationsPlugin();

// ===== MENU PAGE =====
class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        backgroundColor: const Color(0xFF3D3B8C),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          'This is your new menu page.\nYou can customize it however you want.',
          style: TextStyle(fontSize: 18, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ===== SPLASH SCREEN =====
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2500), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MyHomePage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3D3B8C), Color(0xFF5A58B5), Color(0xFF7A78D5)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                'CarryGo',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      blurRadius: 15,
                      color: Colors.black.withOpacity(0.3),
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Never forget your essentials',
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CarryGo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D3B8C)),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ===== MAIN APP =====
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  late TabController _tabController;
  late MapController mapController;
  ll.LatLng currentLocation = const ll.LatLng(40.7128, -74.0060);
  Map<String, bool> _userInsideLocation = {};
  bool _isTrackingEnabled = false;
  int _notificationIdCounter = 0; // Safe counter for notification IDs

  List<Map<String, dynamic>> locations = [];
  List<Map<String, dynamic>> reminders = [];
  final Map<String, IconData> iconMap = {
    'home': Icons.home,
    'work': Icons.work,
    'school': Icons.school,
    'location_on': Icons.location_on,
  };

  // ===== PERSISTENCE =====
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final locationsJson = prefs.getString('locations');
    if (locationsJson != null && locationsJson.isNotEmpty) {
      setState(() {
        locations = List<Map<String, dynamic>>.from(jsonDecode(locationsJson));
      });
    }
    final remindersJson = prefs.getString('reminders');
    if (remindersJson != null && remindersJson.isNotEmpty) {
      setState(() {
        reminders = List<Map<String, dynamic>>.from(jsonDecode(remindersJson));
      });
    }
    _initializeLocationTracking();
  }

  Future<void> _saveLocations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locations', jsonEncode(locations));
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reminders', jsonEncode(reminders));
  }

  IconData _stringToIconData(String iconStr) {
    return iconMap[iconStr] ?? Icons.location_on;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    mapController = MapController();
    _initializeNotifications();

    _requestAllPermissions();
    _loadData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimePermissionDialog();
    });
  }

  Future<void> _requestAllPermissions() async {
    final notificationStatus = await Permission.notification.request();
    if (notificationStatus.isDenied || notificationStatus.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notifications are disabled. Enable in Settings for reminders to work.'),
            action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
          ),
        );
      }
    }

    var locationStatus = await Permission.location.status;
    if (locationStatus.isDenied) {
      locationStatus = await Permission.location.request();
    }
    if (locationStatus.isGranted || locationStatus.isLimited) {
      locationStatus = await Permission.locationAlways.request();
    }

    if (locationStatus.isGranted) {
      _getCurrentLocation();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Location permission is required for reminders to work properly.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(label: 'Open Settings', textColor: Colors.white, onPressed: openAppSettings),
        ),
      );
    }
  }

  Future<void> _showFirstTimePermissionDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenDialog = prefs.getBool('hasSeenPermissionDialog') ?? false;

    if (!hasSeenDialog) {
      await prefs.setBool('hasSeenPermissionDialog', true);

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Permissions Required'),
          content: const Text(
            'Thank you for installing CarryGo!\n\n'
            'To use location-based reminders, please kindly grant:\n'
            '- Location permission (Allow all the time)\n'
            '- Notifications permission\n\n'
            'You can do this in the next screens or via Settings.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3D3B8C)),
              child: const Text('Open Settings', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _initializeNotifications() async {
    tz_data.initializeTimeZones();
    const fln.AndroidInitializationSettings initializationSettingsAndroid =
        fln.AndroidInitializationSettings('@mipmap/ic_launcher');

    await flutterLocalNotificationsPlugin.initialize(
      const fln.InitializationSettings(android: initializationSettingsAndroid),
      onDidReceiveNotificationResponse: (fln.NotificationResponse response) async {
        final String? payload = response.payload;

        if (payload == null) return;

        final payloadData = jsonDecode(payload);
        final String title = payloadData['title'];
        final String location = payloadData['location'];
        final String trigger = payloadData['trigger'];

        if (response.actionId == 'SNOOZE_ACTION') {
          // Snooze: reschedule the same notification after 45 seconds
          print('Snooze clicked → rescheduling in 45s');
          await _scheduleSnoozedNotification(title, location, trigger, 45);
        } else if (response.actionId == 'DISMISS_ACTION') {
          // Dismiss: do nothing extra (already auto-cancels via cancelNotification: true)
          print('Dismiss clicked');
        }
      },
    );
  }

  Future<void> _scheduleSnoozedNotification(
      String title, String location, String trigger, int seconds) async {
    final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));

    const fln.AndroidNotificationDetails androidDetails = fln.AndroidNotificationDetails(
      'location_reminders',
      'Location Reminders',
      channelDescription: 'Notifications for location-based reminders',
      importance: fln.Importance.max,
      priority: fln.Priority.high,
      autoCancel: true,
      fullScreenIntent: true,
      visibility: fln.NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );

    final int id = _notificationIdCounter++; // Use counter for snoozed notifications too

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      'Don\'t forget your $title when you $trigger $location! (Snoozed)',
      scheduledTime,
      const fln.NotificationDetails(android: androidDetails),
      uiLocalNotificationDateInterpretation: fln.UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
      payload: jsonEncode({'title': title, 'location': location, 'trigger': trigger}),
    );
  }

  void _initializeLocationTracking() {
    for (var location in locations) {
      _userInsideLocation[location['name']] = false;
    }
  }

  void _startLocationTracking() {
    if (_isTrackingEnabled) return;

    for (var location in locations) {
      _userInsideLocation[location['name']] = false;
    }
    _isTrackingEnabled = true;

    _checkLocationAndTriggerReminders();
    _startPositionStream();
  }

  void _stopLocationTracking() {
    _isTrackingEnabled = false;
  }

  Future<void> _checkLocationAndTriggerReminders() async {
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        currentLocation = ll.LatLng(position.latitude, position.longitude);
      });
      mapController.move(currentLocation, mapController.camera.zoom);
    } catch (e) {
      print('Location fetch error: $e');
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // km
  }

  Future<void> _triggerRemindersForLocation(String locationName, String triggerType) async {
    print('Trigger check → $locationName on $triggerType');
    final dayOfWeek = DateTime.now().weekday - 1;
    for (var reminder in reminders) {
      if (reminder['location'] != locationName) continue;
      if (!(reminder['days'][dayOfWeek] as bool)) continue;
      if (reminder['trigger'] == 'both' || reminder['trigger'] == triggerType) {
        print('Sending → ${reminder['title']}');
        await _showNotification(reminder['title'], locationName, triggerType);
      }
    }
  }

  Future<void> _showNotification(String title, String location, String action) async {
    const fln.AndroidNotificationAction snoozeAction =
        fln.AndroidNotificationAction('SNOOZE_ACTION', 'Snooze (45s)');
    const fln.AndroidNotificationAction dismissAction =
        fln.AndroidNotificationAction('DISMISS_ACTION', 'Dismiss', cancelNotification: true);

    const fln.AndroidNotificationDetails androidDetails = fln.AndroidNotificationDetails(
      'location_reminders',
      'Location Reminders',
      channelDescription: 'Notifications for location-based reminders',
      importance: fln.Importance.max,
      priority: fln.Priority.high,
      autoCancel: false,
      fullScreenIntent: true,
      visibility: fln.NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      actions: [snoozeAction, dismissAction],
    );

    final int notificationId = _notificationIdCounter++;
    print('Showing notification with safe ID: $notificationId');

    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      'Don\'t forget your $title when you $action $location!',
      const fln.NotificationDetails(android: androidDetails),
      payload: jsonEncode({'title': title, 'location': location, 'trigger': action}),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        currentLocation = ll.LatLng(position.latitude, position.longitude);
      });
      mapController.move(currentLocation, 15.0);
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  void _startPositionStream() {
    Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((Position position) {
      setState(() {
        currentLocation = ll.LatLng(position.latitude, position.longitude);
      });
      mapController.move(currentLocation, 16.0);

      print('GPS update → lat: ${position.latitude}, lng: ${position.longitude}');

      for (var location in locations) {
        final distance = _calculateDistance(
          currentLocation.latitude,
          currentLocation.longitude,
          location['lat'],
          location['lng'],
        );
        final radiusKm = location['radius'] / 1000.0;
        final isInside = distance <= radiusKm + 0.05;

        final wasInside = _userInsideLocation[location['name']] ?? false;

        print('Distance to ${location['name']}: ${distance.toStringAsFixed(3)} km (radius ${radiusKm.toStringAsFixed(3)} km) → ${isInside ? 'INSIDE' : 'OUTSIDE'}');

        if (isInside && !wasInside) {
          _userInsideLocation[location['name']] = true;
          print('ENTRY DETECTED → ${location['name']}');
          _triggerRemindersForLocation(location['name'], 'on entry');
        } else if (!isInside && wasInside) {
          _userInsideLocation[location['name']] = false;
          print('EXIT DETECTED → ${location['name']}');
          _triggerRemindersForLocation(location['name'], 'on exit');
        } else {
          _userInsideLocation[location['name']] = isInside;
        }
      }
    }).onError((error) => print('Position stream error: $error'));
  }

  void _onMapTapped(ll.LatLng position) => _showAddLocationDialog(position);

  void _showAddLocationDialog(ll.LatLng position) {
    final nameController = TextEditingController();
    int radius = 100;
    String selectedIcon = 'location_on';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Add New Location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(hintText: 'Location name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Radius (m): '),
                  Expanded(
                    child: Slider(
                      value: radius.toDouble(),
                      min: 10,
                      max: 1000,
                      divisions: 99,
                      label: '$radius',
                      onChanged: (v) => setStateDialog(() => radius = v.toInt()),
                    ),
                  ),
                  Text('$radius'),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Choose icon:'),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: iconMap.entries.map((entry) {
                  final String key = entry.key;
                  final IconData icon = entry.value;
                  final bool isSelected = selectedIcon == key;
                  return GestureDetector(
                    onTap: () => setStateDialog(() => selectedIcon = key),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF3D3B8C).withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isSelected ? const Color(0xFF3D3B8C) : Colors.grey),
                      ),
                      child: Icon(icon, size: 30, color: const Color(0xFF3D3B8C)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  _addLocationToList(nameController.text, position, radius, selectedIcon);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3D3B8C)),
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _addLocationToList(String name, ll.LatLng position, int radius, String icon) {
    setState(() {
      locations.add({
        'name': name,
        'icon': icon,
        'lat': position.latitude,
        'lng': position.longitude,
        'radius': radius,
      });
    });
    _saveLocations();
  }

  void _showEditLocationDialog(int index) {
    final location = locations[index];
    final nameController = TextEditingController(text: location['name']);
    int radius = location['radius'];
    String selectedIcon = location['icon'] as String;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Edit Location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(hintText: 'Location name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Radius (m): '),
                  Expanded(
                    child: Slider(
                      value: radius.toDouble(),
                      min: 10,
                      max: 1000,
                      divisions: 99,
                      label: '$radius',
                      onChanged: (v) => setStateDialog(() => radius = v.toInt()),
                    ),
                  ),
                  Text('$radius'),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Choose icon:'),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: iconMap.entries.map((entry) {
                  final String key = entry.key;
                  final IconData icon = entry.value;
                  final bool isSelected = selectedIcon == key;
                  return GestureDetector(
                    onTap: () => setStateDialog(() => selectedIcon = key),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF3D3B8C).withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isSelected ? const Color(0xFF3D3B8C) : Colors.grey),
                      ),
                      child: Icon(icon, size: 30, color: const Color(0xFF3D3B8C)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  final String oldName = location['name'];
                  final String newName = nameController.text;
                  setState(() {
                    locations[index]['name'] = newName;
                    locations[index]['icon'] = selectedIcon;
                    locations[index]['radius'] = radius;
                    if (newName != oldName) {
                      for (var rem in reminders) {
                        if (rem['location'] == oldName) {
                          rem['location'] = newName;
                        }
                      }
                    }
                  });
                  _saveLocations();
                  _saveReminders();
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3D3B8C)),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showRadiusDialog(int index) {
    final location = locations[index];
    int newRadius = location['radius'];
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Set Radius for ${location['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('Radius (m): '),
                  Expanded(
                    child: Slider(
                      value: newRadius.toDouble(),
                      min: 10,
                      max: 1000,
                      divisions: 99,
                      label: '$newRadius',
                      onChanged: (v) => setState(() => newRadius = v.toInt()),
                    ),
                  ),
                  Text('$newRadius'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() => locations[index]['radius'] = newRadius);
                _saveLocations();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3D3B8C)),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF3D3B8C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MenuPage()),
            );
          },
        ),
        title: const Text('CARRY GO',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isTrackingEnabled
                        ? _stopLocationTracking()
                        : _startLocationTracking();
                  });
                },
                icon: Icon(
                    _isTrackingEnabled ? Icons.location_on : Icons.location_off,
                    size: 16,
                    color: Colors.white),
                label: Text(_isTrackingEnabled ? 'Tracking ON' : 'Tracking OFF',
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isTrackingEnabled ? Colors.green : Colors.red),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orange,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey[300],
          tabs: const [
            Tab(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.location_on_outlined),
                  SizedBox(width: 5),
                  Text('LOCATIONS')
                ])),
            Tab(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.notifications_outlined),
                  SizedBox(width: 5),
                  Text('REMINDER')
                ])),
          ],
        ),
      ),
      body: TabBarView(
          controller: _tabController,
          children: [_buildLocationsTab(), _buildReminderTab()]),
    );
  }

  Widget _buildMapWidget() {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: currentLocation,
        initialZoom: 15,
        minZoom: 2,
        maxZoom: 18,
        onTap: (tapPosition, point) =>
            _onMapTapped(ll.LatLng(point.latitude, point.longitude)),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.carrygo',
        ),
        ...locations.map((location) => CircleLayer(
              circles: [
                CircleMarker(
                  point: ll.LatLng(location['lat'], location['lng']),
                  radius: location['radius'].toDouble(),
                  useRadiusInMeter: true,
                  color: const Color(0x333D3B8C),
                  borderColor: const Color(0x803D3B8C),
                  borderStrokeWidth: 3,
                ),
              ],
            )),
        MarkerLayer(
          markers: [
            Marker(
              point: currentLocation,
              width: 80,
              height: 80,
              alignment: Alignment.topCenter,
              child: Column(
                children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(17.5),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.blue.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2)
                      ],
                    ),
                    child: const Icon(Icons.my_location,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(3)),
                    child: const Text('You',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            ...locations.map((location) {
              final iconData = _stringToIconData(location['icon'] as String);
              return Marker(
                point: ll.LatLng(location['lat'], location['lng']),
                width: 80,
                height: 80,
                alignment: Alignment.topCenter,
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3D3B8C),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(iconData, color: Colors.white, size: 20),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.87),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(location['name'],
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationsTab() {
    return Stack(
      children: [
        _buildMapWidget(),
        Positioned(
          top: 20,
          right: 20,
          child: FloatingActionButton(
            onPressed: () {
              mapController.move(currentLocation, mapController.camera.zoom);
            },
            backgroundColor: const Color(0xFF3D3B8C),
            tooltip: 'Center on my location',
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 15),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Tap on the map to add a new location',
                      style: TextStyle(fontSize: 14, color: Colors.grey)),
                ),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: locations.length,
                  itemBuilder: (context, index) {
                    final location = locations[index];
                    final iconData =
                        _stringToIconData(location['icon'] as String);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                                color: const Color(0xFF3D3B8C),
                                borderRadius: BorderRadius.circular(8)),
                            child:
                                Icon(iconData, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(location['name'],
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500)),
                                Text('Radius: ${location['radius']}m',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[600])),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'radius') {
                                _showRadiusDialog(index);
                              } else if (value == 'edit') {
                                _showEditLocationDialog(index);
                              } else if (value == 'delete') {
                                setState(() => locations.removeAt(index));
                                _saveLocations();
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'radius',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_location_alt, size: 20),
                                    SizedBox(width: 10),
                                    Text('Set Radius'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 20),
                                    SizedBox(width: 10),
                                    Text('Edit Name & Icon'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete,
                                        size: 20, color: Colors.red),
                                    SizedBox(width: 10),
                                    Text('Delete',
                                        style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                            icon:
                                const Icon(Icons.more_vert, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReminderTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ElevatedButton.icon(
          onPressed: _showAddReminderDialog,
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3D3B8C),
              padding: const EdgeInsets.symmetric(vertical: 12)),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('ADD REMINDER',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 20),
        ...reminders.asMap().entries.map((entry) {
          int index = entry.key;
          final reminder = entry.value;
          final String? currentLocationValue = locations
                  .map((loc) => loc['name'] as String)
                  .contains(reminder['location'])
              ? reminder['location']
              : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) {
                          setState(() => reminder['title'] = value);
                          _saveReminders();
                        },
                        decoration: InputDecoration(
                          hintText: reminder['title'].isEmpty
                              ? 'Reminder title'
                              : reminder['title'],
                          hintStyle: const TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: () {
                        setState(() => reminders.removeAt(index));
                        _saveReminders();
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      underline: Container(),
                      value: currentLocationValue,
                      hint: currentLocationValue == null
                          ? const Text('Location deleted - select new')
                          : null,
                      items: locations
                          .map((loc) => DropdownMenuItem(
                              value: loc['name'] as String,
                              child: Text(loc['name'] as String)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => reminder['location'] = value);
                          _saveReminders();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      underline: Container(),
                      value: reminder['trigger'],
                      items: const [
                        DropdownMenuItem(
                            value: 'on entry', child: Text('On Entry')),
                        DropdownMenuItem(
                            value: 'on exit', child: Text('On Exit')),
                        DropdownMenuItem(value: 'both', child: Text('Both')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => reminder['trigger'] = value);
                          _saveReminders();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                      .asMap()
                      .entries
                      .map((e) {
                    final dayIndex = e.key;
                    final day = e.value;
                    final isActive = reminder['days'][dayIndex] as bool;
                    return GestureDetector(
                      onTap: () {
                        setState(() => reminder['days'][dayIndex] =
                            !reminder['days'][dayIndex]);
                        _saveReminders();
                      },
                      child: Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF3D3B8C)
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Center(
                          child: Text(day,
                              style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.grey[700],
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _showAddReminderDialog() {
    String reminderTitle = '';
    String? selectedLocation =
        locations.isNotEmpty ? locations[0]['name'] as String : null;
    String selectedTrigger = 'on entry';
    List<bool> selectedDays = [
      true,
      true,
      true,
      true,
      true,
      false,
      false
    ]; // Default: weekdays only
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Reminder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (value) => reminderTitle = value,
                  decoration: const InputDecoration(
                      hintText: 'Reminder name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                Container(
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      underline: Container(),
                      value: selectedLocation,
                      hint: const Text('No locations added yet'),
                      items: locations
                          .map((loc) => DropdownMenuItem(
                              value: loc['name'] as String,
                              child: Text(loc['name'] as String)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => selectedLocation = value),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      underline: Container(),
                      value: selectedTrigger,
                      items: const [
                        DropdownMenuItem(
                            value: 'on entry', child: Text('On Entry')),
                        DropdownMenuItem(
                            value: 'on exit', child: Text('On Exit')),
                        DropdownMenuItem(value: 'both', child: Text('Both')),
                      ],
                      onChanged: (value) =>
                          setState(() => selectedTrigger = value ?? 'on entry'),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Active on days:'),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                      .asMap()
                      .entries
                      .map((e) {
                    final dayIndex = e.key;
                    final day = e.value;
                    final isActive = selectedDays[dayIndex];
                    return GestureDetector(
                      onTap: () {
                        setState(() =>
                            selectedDays[dayIndex] = !selectedDays[dayIndex]);
                      },
                      child: Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF3D3B8C)
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Center(
                          child: Text(day,
                              style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.grey[700],
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 25),
                const Center(
                  child: Text(
                    'Please turn on location tracking (in the app bar) for reminders to work.',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (reminderTitle.isNotEmpty && selectedLocation != null) {
                  setState(() {
                    reminders.add({
                      'title': reminderTitle,
                      'location': selectedLocation,
                      'trigger': selectedTrigger,
                      'days': selectedDays,
                    });
                  });
                  _saveReminders();
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D3B8C)),
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
