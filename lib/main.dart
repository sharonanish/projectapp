import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ===== SPLASH SCREEN (IDENTICAL to what you loved) =====
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

// ===== MAIN APP WITH DATA PERSISTENCE =====
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  late TabController _tabController;
  late MapController mapController;
  ll.LatLng mapCenter = const ll.LatLng(40.7128, -74.0060);
  ll.LatLng currentLocation = const ll.LatLng(40.7128, -74.0060);
  Timer? _locationTimer;
  Map<String, bool> _userInsideLocation = {};
  bool _isTrackingEnabled = false;

  List<Map<String, dynamic>> locations = [];
  List<Map<String, dynamic>> reminders = [];

  // ===== PERSISTENCE METHODS =====
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load locations
    final locationsJson = prefs.getString('locations');
    if (locationsJson != null && locationsJson.isNotEmpty) {
      setState(() {
        locations = List<Map<String, dynamic>>.from(jsonDecode(locationsJson));
      });
    } else {
      // Default locations if none saved
      setState(() {
        locations = [
          {
            'name': 'Home',
            'icon': 'home',
            'lat': 40.7128,
            'lng': -74.0060,
            'radius': 100,
          },
          {
            'name': 'Work',
            'icon': 'work',
            'lat': 40.7580,
            'lng': -73.9855,
            'radius': 150,
          },
          {
            'name': 'College',
            'icon': 'school',
            'lat': 40.8075,
            'lng': -73.9626,
            'radius': 200,
          },
        ];
      });
    }

    // Load reminders
    final remindersJson = prefs.getString('reminders');
    if (remindersJson != null && remindersJson.isNotEmpty) {
      setState(() {
        reminders = List<Map<String, dynamic>>.from(jsonDecode(remindersJson));
      });
    } else {
      // Default reminders if none saved
      setState(() {
        reminders = [
          {
            'title': 'Keys',
            'location': 'Home',
            'trigger': 'on entry',
            'days': [true, true, true, true, true, false, false],
          },
          {
            'title': 'Wallet',
            'location': 'Work',
            'trigger': 'on exit',
            'days': [true, true, true, true, true, false, false],
          },
        ];
      });
    }

    // Initialize tracking state
    _initializeLocationTracking();
  }

  Future<void> _saveLocations() async {
    final prefs = await SharedPreferences.getInstance();
    // Convert icons to strings for JSON serialization
    final locationsToSave = locations.map((loc) {
      String iconStr;
      if (loc['icon'] is IconData) {
        iconStr = _iconDataToString(loc['icon'] as IconData);
      } else {
        iconStr = loc['icon'] as String;
      }
      return {
        'name': loc['name'],
        'icon': iconStr,
        'lat': loc['lat'],
        'lng': loc['lng'],
        'radius': loc['radius'],
      };
    }).toList();
    await prefs.setString('locations', jsonEncode(locationsToSave));
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reminders', jsonEncode(reminders));
  }

  String _iconDataToString(IconData icon) {
    if (icon == Icons.home) return 'home';
    if (icon == Icons.work) return 'work';
    if (icon == Icons.school) return 'school';
    return 'location_on';
  }

  IconData _stringToIconData(String iconStr) {
    switch (iconStr) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      case 'school':
        return Icons.school;
      default:
        return Icons.location_on;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    mapController = MapController();
    _initializeNotifications();
    _initializeMap();
    _loadData(); // Load saved data on startup
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _initializeLocationTracking() {
    for (var location in locations) {
      _userInsideLocation[location['name']] = false;
    }
  }

  void _startLocationTracking() {
    if (_isTrackingEnabled) return;
    _isTrackingEnabled = true;
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkLocationAndTriggerReminders();
    });
  }

  void _stopLocationTracking() {
    _isTrackingEnabled = false;
    _locationTimer?.cancel();
  }

  Future<void> _checkLocationAndTriggerReminders() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(
        () =>
            currentLocation = ll.LatLng(position.latitude, position.longitude),
      );

      for (var location in locations) {
        final distance = _calculateDistance(
          currentLocation.latitude,
          currentLocation.longitude,
          location['lat'],
          location['lng'],
        );
        final radius = (location['radius'] as int) / 1000;
        final isInside = distance <= radius;
        final wasInside = _userInsideLocation[location['name']] ?? false;

        if (isInside && !wasInside) {
          _userInsideLocation[location['name']] = true;
          await _triggerRemindersForLocation(location['name'], 'on entry');
        } else if (!isInside && wasInside) {
          _userInsideLocation[location['name']] = false;
          await _triggerRemindersForLocation(location['name'], 'on exit');
        } else {
          _userInsideLocation[location['name']] = isInside;
        }
      }
    } catch (e) {
      print('Error checking location: $e');
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295;
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Future<void> _triggerRemindersForLocation(
    String locationName,
    String triggerType,
  ) async {
    final dayOfWeek = DateTime.now().weekday - 1;
    for (var reminder in reminders) {
      if (reminder['location'] != locationName) continue;
      if (!(reminder['days'][dayOfWeek] as bool)) continue;
      if (reminder['trigger'] == 'both' || reminder['trigger'] == triggerType) {
        await _showNotification(reminder['title'], locationName, triggerType);
      }
    }
  }

  Future<void> _showNotification(
    String title,
    String location,
    String action,
  ) async {
    final androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'location_reminders',
      'Location Reminders',
      channelDescription: 'Notifications for location-based reminders',
      importance: Importance.max,
      priority: Priority.high,
    );
    await flutterLocalNotificationsPlugin.show(
      title.hashCode,
      title,
      'You $action $location',
      NotificationDetails(android: androidPlatformChannelSpecifics),
    );
  }

  void _initializeMap() => _requestLocationPermission();

  Future<void> _requestLocationPermission() async {
    final status = await Geolocator.requestPermission();
    if (status == LocationPermission.whileInUse ||
        status == LocationPermission.always) {
      _getCurrentLocation();
    } else {
      print('Location permission denied');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        currentLocation = ll.LatLng(position.latitude, position.longitude);
        mapCenter = currentLocation;
      });
      _startPositionStream();
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  void _startPositionStream() {
    Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        )
        .listen((Position position) {
          setState(
            () => currentLocation = ll.LatLng(
              position.latitude,
              position.longitude,
            ),
          );
        })
        .onError((error) => print('Location stream error: $error'));
  }

  void _onMapTapped(ll.LatLng position) => _showAddLocationDialog(position);

  void _showAddLocationDialog(ll.LatLng position) {
    final nameController = TextEditingController();
    int radius = 100;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: 'Location name',
                  border: OutlineInputBorder(),
                ),
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
                      onChanged: (value) =>
                          setState(() => radius = value.toInt()),
                    ),
                  ),
                  Text('$radius'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  _addLocationToList(nameController.text, position, radius);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D3B8C),
              ),
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _addLocationToList(String name, ll.LatLng position, int radius) {
    setState(() {
      locations.add({
        'name': name,
        'icon': 'location_on',
        'lat': position.latitude,
        'lng': position.longitude,
        'radius': radius,
      });
    });
    _saveLocations(); // Save after adding
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
              const SizedBox(height: 20),
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
                      onChanged: (value) =>
                          setState(() => newRadius = value.toInt()),
                    ),
                  ),
                  Text('$newRadius'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  locations[index]['radius'] = newRadius;
                });
                _saveLocations(); // Save after updating
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D3B8C),
              ),
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
    _stopLocationTracking();
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
          onPressed: () {},
        ),
        title: const Text(
          'CARRY GO',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    if (_isTrackingEnabled) {
                      _stopLocationTracking();
                    } else {
                      _startLocationTracking();
                    }
                  });
                },
                icon: Icon(
                  _isTrackingEnabled ? Icons.location_on : Icons.location_off,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  _isTrackingEnabled ? 'Tracking ON' : 'Tracking OFF',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTrackingEnabled
                      ? Colors.green
                      : Colors.red,
                ),
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
                  Text('LOCATIONS'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_outlined),
                  SizedBox(width: 5),
                  Text('REMINDER'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildLocationsTab(), _buildReminderTab()],
      ),
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
          // FIXED: Removed extra spaces in URL
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.my_android_app',
          tileSize: 256,
          keepBuffer: 2,
        ),
        ...locations.map(
          (location) => CircleLayer(
            circles: [
              CircleMarker(
                point: ll.LatLng(location['lat'], location['lng']),
                radius: location['radius'].toDouble() / 100,
                useRadiusInMeter: false,
                color: const Color(0xFF3D3B8C).withValues(alpha: 0.2),
                borderColor: const Color(0xFF3D3B8C).withValues(alpha: 0.5),
                borderStrokeWidth: 2,
              ),
            ],
          ),
        ),
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
                          color: Colors.blue.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.my_location,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'You',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        location['name'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
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
          child: FloatingActionButton.extended(
            onPressed: () {},
            backgroundColor: const Color(0xFF3D3B8C),
            label: const Text(
              'ADD LOCATION',
              style: TextStyle(color: Colors.white),
            ),
            icon: const Icon(Icons.add, color: Colors.white),
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
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 15),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: locations.length,
                  itemBuilder: (context, index) {
                    final location = locations[index];
                    final iconData = _stringToIconData(
                      location['icon'] as String,
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3D3B8C),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              iconData,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  location['name'],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Radius: ${location['radius']}m',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton(
                            onSelected: (value) {
                              if (value == 'radius') {
                                _showRadiusDialog(index);
                              } else if (value == 'delete') {
                                setState(() {
                                  locations.removeAt(index);
                                });
                                _saveLocations(); // Save after deletion
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'radius',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 20),
                                    SizedBox(width: 10),
                                    Text('Set Radius'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.grey,
                            ),
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
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'ADD REMINDER',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 25),
        ...reminders.asMap().entries.map((entry) {
          int index = entry.key;
          final reminder = entry.value;
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
                          setState(() {
                            reminder['title'] = value;
                          });
                          _saveReminders(); // Save on change
                        },
                        decoration: InputDecoration(
                          hintText: reminder['title'],
                          hintStyle: const TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          reminders.removeAt(index);
                        });
                        _saveReminders(); // Save after deletion
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      underline: Container(),
                      value: reminder['location'],
                      items: locations
                          .map<DropdownMenuItem<String>>(
                            (loc) => DropdownMenuItem<String>(
                              value: loc['name'] as String,
                              child: Text(loc['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            reminder['location'] = value;
                          });
                          _saveReminders(); // Save on change
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      underline: Container(),
                      value: reminder['trigger'],
                      items: const [
                        DropdownMenuItem(
                          value: 'on entry',
                          child: Text('On Entry'),
                        ),
                        DropdownMenuItem(
                          value: 'on exit',
                          child: Text('On Exit'),
                        ),
                        DropdownMenuItem(value: 'both', child: Text('Both')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            reminder['trigger'] = value;
                          });
                          _saveReminders(); // Save on change
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ...[' M', 'T', 'W', 'T', 'F', 'S', 'S'].asMap().entries.map(
                      (e) {
                        final dayIndex = e.key;
                        final day = e.value;
                        final isActive = reminder['days'][dayIndex];
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              reminder['days'][dayIndex] =
                                  !reminder['days'][dayIndex];
                            });
                            _saveReminders(); // Save on change
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
                              child: Text(
                                day,
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.grey[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ).toList(),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  void _showAddReminderDialog() {
    String reminderTitle = '';
    String selectedLocation = locations.isNotEmpty ? locations[0]['name'] : '';
    String selectedTrigger = 'on entry';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => reminderTitle = value,
                decoration: const InputDecoration(
                  hintText: 'Reminder name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    underline: Container(),
                    hint: const Text('Select location'),
                    value: selectedLocation.isNotEmpty
                        ? selectedLocation
                        : null,
                    items: locations
                        .map<DropdownMenuItem<String>>(
                          (loc) => DropdownMenuItem<String>(
                            value: loc['name'] as String,
                            child: Text(loc['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedLocation = value ?? ''),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    underline: Container(),
                    value: selectedTrigger,
                    items: const [
                      DropdownMenuItem(
                        value: 'on entry',
                        child: Text('On Entry'),
                      ),
                      DropdownMenuItem(
                        value: 'on exit',
                        child: Text('On Exit'),
                      ),
                      DropdownMenuItem(value: 'both', child: Text('Both')),
                    ],
                    onChanged: (value) =>
                        setState(() => selectedTrigger = value ?? 'on entry'),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (reminderTitle.isNotEmpty && selectedLocation.isNotEmpty) {
                  setState(() {
                    reminders.add({
                      'title': reminderTitle,
                      'location': selectedLocation,
                      'trigger': selectedTrigger,
                      'days': [true, true, true, true, true, false, false],
                    });
                  });
                  _saveReminders(); // Save new reminder
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D3B8C),
              ),
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
