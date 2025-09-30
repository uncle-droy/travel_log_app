import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Import the generated file

bool isNew = true;

//----------- DATA MODELS -----------//
class Visit {
  final LatLng point;
  String landmarkName;
  final DateTime startTime;
  Duration duration;
  double moneySpent;
  int rating;
  String notes;
  int itemsPurchased;

  Visit({
    required this.point,
    required this.landmarkName,
    required this.startTime,
    this.duration = Duration.zero,
    this.moneySpent = 0.0,
    this.rating = 0,
    this.notes = '',
    this.itemsPurchased = 0,
  });

  Map<String, dynamic> toJson() => {
    'lat': point.latitude,
    'lng': point.longitude,
    'landmarkName': landmarkName,
    'startTime': startTime.toIso8601String(),
    'duration': duration.inSeconds,
    'moneySpent': moneySpent,
    'rating': rating,
    'notes': notes,
    'itemsPurchased': itemsPurchased,
  };

  static Visit fromJson(Map<String, dynamic> json) => Visit(
    point: LatLng(json['lat'], json['lng']),
    landmarkName: json['landmarkName'],
    startTime: DateTime.parse(json['startTime']),
    duration: Duration(seconds: json['duration']),
    moneySpent: (json['moneySpent'] as num).toDouble(),
    rating: json['rating'] ?? 0,
    notes: json['notes'] ?? '',
    itemsPurchased: json['itemsPurchased'] ?? 0,
  );
}

// In the Trip class

class Trip {
  final String id;
  final DateTime tripDate;
  final List<Visit> visits;
  Duration totalDuration;
  double totalDistanceKm; // ADD THIS LINE
  int get stopCount => visits.length;

  Trip({
    required this.id,
    required this.tripDate,
    required this.visits,
    this.totalDuration = Duration.zero,
    this.totalDistanceKm = 0.0, // ADD THIS LINE
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'tripDate': tripDate.toIso8601String(),
    'visits': visits.map((v) => v.toJson()).toList(),
    'totalDuration': totalDuration.inSeconds,
    'totalDistanceKm': totalDistanceKm, // ADD THIS LINE
  };

  static Trip fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'],
    tripDate: DateTime.parse(json['tripDate']),
    visits: (json['visits'] as List).map((v) => Visit.fromJson(v)).toList(),
    totalDuration: Duration(seconds: json['totalDuration']),
    totalDistanceKm:
        (json['totalDistanceKm'] as num?)?.toDouble() ?? 0.0, // ADD THIS LINE
  );
}

//----------- MAIN APP ENTRY POINT -----------//
Future<void> main() async {
  // These two lines are essential
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trip Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF8B5CF6),
          surface: const Color(0xFFFAFAFA),
          onSurface: const Color(0xFF1F2937),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

//----------- MAIN SCREEN -----------//
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Trip> _trips = [];

  bool _isTracking = false;
  Position? _currentPosition;
  final List<Visit> _currentVisits = [];
  StreamSubscription<Position>? _positionStreamSubscription;
  DateTime? _tripStartTime;

  late List<Widget> _widgetOptions;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  // Add this new function inside the _MainScreenState class

  // In _MainScreenState, modify the _sendAnalyticsData function

  Future<void> _sendAnalyticsData(Trip trip) async {
    final db = FirebaseFirestore.instance;

    // CHANGE THIS: Instead of generating a new ID, use the one from the trip object.
    final tripId = trip.id;

    final tripData = {
      "tripId": tripId,
      "tripDate": trip.tripDate.toIso8601String(),
      "visits": trip.visits.map((v) => v.toJson()).toList(),
      "processed": false,
      "submittedAt": FieldValue.serverTimestamp(),
    };

    // This will now CREATE a document on the first save, and
    // OVERWRITE the same document on all subsequent saves.
    await db.collection('submitted_trips').doc(tripId).set(tripData);
  }

  void _deleteTrip(int index, BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Please Confirm'),
          content: const Text('Are you sure you want to delete this trip?'),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _trips.removeAt(index);
                  _updateWidgetOptions();
                });
                _saveTrips();
                Navigator.of(ctx).pop();
              },
              child: const Text('Yes'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: const Text('No'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final tripsJson = jsonEncode(_trips.map((t) => t.toJson()).toList());
    await prefs.setString('trips', tripsJson);
  }

  Future<void> _loadTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final tripsJson = prefs.getString('trips');
    if (tripsJson != null) {
      final tripsList = jsonDecode(tripsJson) as List;
      _trips.clear();
      _trips.addAll(tripsList.map((t) => Trip.fromJson(t)));
    }
    setState(() {
      _isLoading = false;
      _updateWidgetOptions();
    });
  }

  void _updateWidgetOptions() {
    _widgetOptions = <Widget>[
      RecordScreen(
        isTracking: _isTracking,
        currentPosition: _currentPosition,
        currentVisits: _currentVisits,
        onStart: _startTracking,
        onStop: _stopTracking,
      ),
      const GuideSearchScreen(),
      HistoryScreen(
        trips: _trips,
        onTripsChanged: _saveTrips,
        onDeleteTrip: _deleteTrip,
        onSendAnalytics: _sendAnalyticsData,
      ),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<String> _getLandmarkName(LatLng point) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'com.example.travel_app'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'];
        final poi =
            address?['amenity'] ??
            address?['shop'] ??
            address?['tourism'] ??
            address?['historic'];
        if (poi != null) return poi;
        return address?['road'] ??
            address?['suburb'] ??
            data['display_name'] ??
            'Unknown Area';
      }
    } catch (e) {
      print("Error fetching landmark: $e");
    }
    return 'N/A';
  }

  void _startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    _currentPosition = await Geolocator.getCurrentPosition();

    LocationSettings locationSettings =
        defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 15),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            pauseLocationUpdatesAutomatically: false,
          );

    setState(() {
      _isTracking = true;
      _currentVisits.clear();
      _tripStartTime = DateTime.now();
      _updateWidgetOptions();
    });

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) async {
            final newLatLng = LatLng(position.latitude, position.longitude);
            final currentLandmark = await _getLandmarkName(newLatLng);
            if (!mounted) return;
            setState(() {
              _currentPosition = position;
              if (_currentVisits.isEmpty ||
                  _currentVisits.last.landmarkName != currentLandmark) {
                _currentVisits.add(
                  Visit(
                    point: newLatLng,
                    landmarkName: currentLandmark,
                    startTime: DateTime.now(),
                  ),
                );
              } else {
                _currentVisits.last.duration = DateTime.now().difference(
                  _currentVisits.last.startTime,
                );
              }
              _updateWidgetOptions();
            });
          },
        );
  }

  void _stopTracking() {
    _positionStreamSubscription?.cancel();
    double totalDistanceMeters = 0.0;
    for (int i = 0; i < _currentVisits.length - 1; i++) {
      totalDistanceMeters += Geolocator.distanceBetween(
        _currentVisits[i].point.latitude,
        _currentVisits[i].point.longitude,
        _currentVisits[i + 1].point.latitude,
        _currentVisits[i + 1].point.longitude,
      );
    }
    final double totalDistanceKm = totalDistanceMeters / 1000.0;
    final String tripId = const Uuid().v4();

    final trip = Trip(
      id: tripId,
      tripDate: _tripStartTime!,
      visits: _currentVisits,
      totalDuration: DateTime.now().difference(_tripStartTime!),
      totalDistanceKm: totalDistanceKm,
    );

    setState(() {
      _isTracking = false;
      _trips.insert(0, trip);
      _selectedIndex = 2;
      _updateWidgetOptions();
    });
    _saveTrips();
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF6B7280),
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _widgetOptions),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          maintainBottomViewPadding: false,
          child: Container(
            height: 60, // Reduce from 65 to 60
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  icon: Icons.radio_button_checked,
                  label: 'Record',
                  index: 0,
                  isSelected: _selectedIndex == 0,
                  onTap: () => _onItemTapped(0),
                ),
                _buildNavItem(
                  icon: Icons.history_rounded,
                  label: 'History',
                  index: 2,
                  isSelected: _selectedIndex == 2,
                  onTap: () => _onItemTapped(2),
                ),
                _buildNavItem(
                  icon: Icons.search,
                  label: 'Guide',
                  index: 1,
                  isSelected: _selectedIndex == 1,
                  onTap: () => _onItemTapped(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//----------- 1. RECORD SCREEN -----------//
class RecordScreen extends StatefulWidget {
  final bool isTracking;
  final Position? currentPosition;
  final List<Visit> currentVisits;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const RecordScreen({
    super.key,
    required this.isTracking,
    required this.currentPosition,
    required this.currentVisits,
    required this.onStart,
    required this.onStop,
  });

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final MapController _mapController = MapController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startOrStopTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RecordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPosition != null &&
        widget.currentPosition != oldWidget.currentPosition) {
      _mapController.move(
        LatLng(
          widget.currentPosition!.latitude,
          widget.currentPosition!.longitude,
        ),
        15.0,
      );
    }
    if (widget.isTracking != oldWidget.isTracking) {
      _startOrStopTimer();
    }
  }

  void _startOrStopTimer() {
    _timer?.cancel();
    if (widget.isTracking) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Trip Logger',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
        ),
        centerTitle: true,
        backgroundColor: Colors.white.withOpacity(0.9),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Status Banner
          Container(
            margin: EdgeInsets.fromLTRB(16, 100, 16, 16),
            padding: EdgeInsets.all(0),
            // decoration: BoxDecoration(
            //   gradient: LinearGradient(
            //     colors: widget.isTracking
            //       ? [Color(0xFF10B981), Color(0xFF059669)]
            //       : [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            //     begin: Alignment.topLeft,
            //     end: Alignment.bottomRight,
            //   ),
            //   borderRadius: BorderRadius.circular(20),
            //   boxShadow: [
            //     BoxShadow(
            //       color: (widget.isTracking ? Color(0xFF10B981) : Color(0xFF6366F1)).withOpacity(0.3),
            //       blurRadius: 20,
            //       offset: Offset(0, 8),
            //     ),
            //   ],
            // ),
            // child: Row(
            // children: [
            // Container(
            //   padding: EdgeInsets.all(12),
            //   decoration: BoxDecoration(
            //     color: Colors.white.withOpacity(0.2),
            //     borderRadius: BorderRadius.circular(12),
            //   ),
            //   child: Icon(
            //     widget.isTracking ? Icons.location_on : Icons.location_off,
            //     color: Colors.white,
            //     size: 24,
            //   ),
            // ),
            // SizedBox(width: 16),
            // Expanded(
            //   child: Column(
            //     crossAxisAlignment: CrossAxisAlignment.start,
            //     children: [
            //       Text(
            //         widget.isTracking ? 'Tracking Active' : 'Ready to Track',
            //         style: TextStyle(
            //           color: Colors.white,
            //           fontSize: 18,
            //           fontWeight: FontWeight.w600,
            //         ),
            //       ),
            //       Text(
            //         widget.isTracking
            //           ? '${widget.currentVisits.length} stops recorded'
            //           : 'Tap start to begin your journey',
            //         style: TextStyle(
            //           color: Colors.white.withOpacity(0.9),
            //           fontSize: 14,
            //         ),
            //       ),
            //     ],
            //   ),
            // ),
            // ],
            // ),
          ),

          // Map Container
          Container(
            height: MediaQuery.of(context).size.height * 0.35,
            margin: EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.currentPosition != null
                    ? LatLng(
                        widget.currentPosition!.latitude,
                        widget.currentPosition!.longitude,
                      )
                    : const LatLng(20.5937, 78.9629),
                initialZoom: widget.currentPosition != null ? 15.0 : 5.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.travel_app',
                ),
                if (widget.isTracking) ...[
                  if (widget.currentVisits.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: widget.currentVisits
                              .map((v) => v.point)
                              .toList(),
                          strokeWidth: 5.0,
                          color: Colors.blueAccent,
                        ),
                      ],
                    ),
                  if (widget.currentPosition != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(
                            widget.currentPosition!.latitude,
                            widget.currentPosition!.longitude,
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),

          // Stops Section
          Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              children: [
                Text(
                  "Current Stops",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.currentVisits.length}',
                    style: TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: !widget.isTracking && widget.currentVisits.isEmpty
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20), // Reduced from 24
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.explore,
                          size: 20, // Reduced from 48
                          color: Color(0xFF6366F1),
                        ),
                      ),
                      const SizedBox(height: 12), // Reduced from 16
                      const Text(
                        "Ready for Adventure?",
                        style: TextStyle(
                          fontSize: 18, // Reduced from 20
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 6), // Reduced from 8
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: 60,
                        ), // Add bottom padding to shift up
                        child: const Text(
                          "Press the start button to begin tracking your journey",
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14, // Reduced from 16
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : widget.isTracking && widget.currentVisits.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF6366F1)),
                        SizedBox(height: 16),
                        Text(
                          "Finding your first stop...",
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      85,
                    ), // Changed from 100 to 85
                    itemCount: widget.currentVisits.length,
                    itemBuilder: (context, index) {
                      final visit = widget.currentVisits.reversed
                          .toList()[index];
                      Duration displayDuration =
                          (widget.isTracking && index == 0)
                          ? DateTime.now().difference(visit.startTime)
                          : visit.duration;

                      return Container(
                        margin: EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Color(0xFFE5E7EB)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.all(16),
                          leading: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Color(0xFF6366F1).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.location_on,
                              color: Color(0xFF6366F1),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            visit.landmarkName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Color(0xFF1F2937),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: widget.isTracking && index == 0
                                  ? Color(0xFF10B981).withOpacity(0.1)
                                  : Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _formatDuration(displayDuration),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: widget.isTracking && index == 0
                                    ? Color(0xFF10B981)
                                    : Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (widget.isTracking ? Colors.red : Color(0xFF6366F1))
                  .withOpacity(0.3),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: widget.isTracking ? widget.onStop : widget.onStart,
          backgroundColor: widget.isTracking ? Colors.red : Color(0xFF6366F1),
          foregroundColor: Colors.white,
          icon: Icon(
            widget.isTracking ? Icons.stop : Icons.play_arrow,
            size: 24,
          ),
          label: Text(
            widget.isTracking ? 'Stop Trip' : 'Start Trip',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

//----------- 2. HISTORY SCREEN -----------//
class HistoryScreen extends StatelessWidget {
  final List<Trip> trips;
  final VoidCallback? onTripsChanged;
  final Function(Trip) onSendAnalytics;
  final Function(int, BuildContext) onDeleteTrip;

  const HistoryScreen({
    super.key,
    required this.trips,
    this.onTripsChanged,
    required this.onDeleteTrip,
    required this.onSendAnalytics,
  });

  Widget _buildStatItem(String title, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          title,
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildTripStat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF1F2937),
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text(
          'Trip History',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (trips.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.analytics_outlined),
              onPressed: () {
                // Future: Add trip analytics
              },
            ),
        ],
      ),
      body: trips.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.map_outlined,
                      size: 64,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No Trips Yet',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Start tracking your first trip to see it here',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Summary Stats Card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        'Total Trips',
                        '${trips.length}',
                        Icons.map,
                      ),
                      _buildStatItem(
                        'Total Stops',
                        '${trips.fold(0, (sum, trip) => sum + trip.stopCount)}',
                        Icons.location_on,
                      ),
                      _buildStatItem(
                        'This Month',
                        '${trips.where((t) => t.tripDate.month == DateTime.now().month).length}',
                        Icons.calendar_today,
                      ),
                    ],
                  ),
                ),

                // Trips List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      16,
                    ), // Changed from 100 to 16
                    itemCount: trips.length,
                    itemBuilder: (context, index) {
                      final trip = trips[index];
                      final firstLandmark = trip.visits.isNotEmpty
                          ? trip.visits.first.landmarkName
                          : "Unknown Trip";

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TripDetailScreen(
                                  trip: trip,
                                  onTripEdited: onTripsChanged,
                                  onSendAnalytics: onSendAnalytics,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF6366F1,
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.location_on,
                                        color: Color(0xFF6366F1),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            firstLandmark,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 18,
                                              color: Color(0xFF1F2937),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat(
                                              'MMM d, yyyy',
                                            ).format(trip.tripDate),
                                            style: const TextStyle(
                                              color: Color(0xFF6B7280),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: Colors.red.withOpacity(0.7),
                                      ),
                                      onPressed: () =>
                                          onDeleteTrip(index, context),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    _buildTripStat(
                                      Icons.timer_outlined,
                                      '${trip.totalDuration.inMinutes}m',
                                      'Duration',
                                    ),
                                    const SizedBox(width: 24),
                                    _buildTripStat(
                                      Icons.location_city,
                                      '${trip.stopCount}',
                                      'Stops',
                                    ),
                                    const SizedBox(width: 24),
                                    _buildTripStat(
                                      Icons.route,
                                      '${trip.totalDistanceKm.toStringAsFixed(1)} km',
                                      'Distance',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

//----------- 3. TRIP DETAIL SCREEN -----------//
class TripDetailScreen extends StatefulWidget {
  final Trip trip;
  final VoidCallback? onTripEdited;
  final Function(Trip) onSendAnalytics;
  const TripDetailScreen({
    super.key,
    required this.trip,
    this.onTripEdited,
    required this.onSendAnalytics,
  });

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late double totalSpent;
  late int totalItems;

  @override
  void initState() {
    super.initState();
    _calculateTotals();
  }

  void _calculateTotals() {
    totalSpent = widget.trip.visits.fold(
      0.0,
      (sum, visit) => sum + visit.moneySpent,
    );
    totalItems = widget.trip.visits.fold(
      0,
      (sum, visit) => sum + visit.itemsPurchased,
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    return "${hours}h ${minutes}m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.share)),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                widget.onTripEdited?.call();
                await widget.onSendAnalytics(widget.trip);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Trip data saved and analytics updated!"),
                  ),
                );
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Trip Overview',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    DateFormat(
                      'EEEE, MMMM d, yyyy',
                    ).format(widget.trip.tripDate),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_formatDuration(widget.trip.totalDuration)} • ${widget.trip.stopCount} stops',
                  ),
                  const Divider(height: 32),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Amount Spent:',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${totalSpent.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Items Purchased: ',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$totalItems',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Distance: ',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.trip.totalDistanceKm.toStringAsFixed(2)} km',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Location Details',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ...widget.trip.visits.map(
            (visit) => Card(
              margin: const EdgeInsets.only(bottom: 16.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                visit.landmarkName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '${DateFormat.jm().format(visit.startTime)} • ${_formatDuration(visit.duration)}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            initialValue: visit.rating.toString(),
                            label: 'Rating (1-5)',
                            onChanged: (val) => setState(
                              () => visit.rating = int.tryParse(val) ?? 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            initialValue: visit.itemsPurchased.toString(),
                            label: 'Items Purchased',
                            keyboardType: TextInputType.number,
                            onChanged: (val) => setState(() {
                              visit.itemsPurchased = int.tryParse(val) ?? 0;
                              _calculateTotals();
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            initialValue: visit.moneySpent.toStringAsFixed(2),
                            label: 'Money Spent (₹)',
                            keyboardType: TextInputType.number,
                            onChanged: (val) => setState(() {
                              visit.moneySpent = double.tryParse(val) ?? 0.0;
                              _calculateTotals();
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'Notes',
                      initialValue: visit.notes,
                      maxLines: 3,
                      onChanged: (val) => setState(() => visit.notes = val),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    String initialValue = '',
    int maxLines = 1,
    TextInputType? keyboardType,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      initialValue: initialValue,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
// Add this entire new class to the end of your lib/main.dart file

class GuideSearchScreen extends StatefulWidget {
  const GuideSearchScreen({super.key});

  @override
  State<GuideSearchScreen> createState() => _GuideSearchScreenState();
}

class _GuideSearchScreenState extends State<GuideSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _foundGuides = [];
  bool _isLoading = false;
  String _status = 'Search for a landmark to find local guides.';

  // In _GuideSearchScreenState, REPLACE the entire function

  // In _GuideSearchScreenState, REPLACE the entire function

  // In _GuideSearchScreenState, REPLACE the entire function

  Future<void> _searchForGuides() async {
    final landmarkName = _searchController.text.trim();
    if (landmarkName.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _status = 'Finding guides for "$landmarkName"...';
      _foundGuides = [];
    });

    try {
      final locationKey = landmarkName.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '_',
      );
      final db = FirebaseFirestore.instance;

      final servicesQuery = db
          .collection("guide_services")
          .where("locationKey", isEqualTo: locationKey);
      final servicesSnapshot = await servicesQuery.get();

      if (servicesSnapshot.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _status =
              'No guides found for "$landmarkName". Try searching for an exact landmark name.';
        });
        return;
      }

      List<Map<String, dynamic>> guides = [];
      for (var serviceDoc in servicesSnapshot.docs) {
        final serviceData = serviceDoc.data();
        final guideId = serviceData['guideId'];

        final guideDoc = await db.collection("guides").doc(guideId).get();

        // **** FIX IS HERE: 'exists' is a property, not a function. Removed the parentheses. ****
        if (guideDoc.exists) {
          // **** END OF FIX ****
          guides.add({...guideDoc.data()!, 'price': serviceData['price']});
        }
      }
      setState(() {
        _foundGuides = guides;
        _isLoading = false;
        _status = '';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status =
            'An error occurred. Please check your connection and try again.';
      });
      print("Error searching for guides: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a Guide'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search Bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Enter a landmark (e.g., Central Park)',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _searchForGuides,
                ),
              ),
              onSubmitted: (_) => _searchForGuides(),
            ),
            const SizedBox(height: 16),

            // Status and Results
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _foundGuides.isEmpty
                  ? Center(
                      child: Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _foundGuides.length,
                      itemBuilder: (context, index) {
                        final guide = _foundGuides[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              radius: 24,
                              child: Text(
                                guide['name']?.substring(0, 1) ?? 'G',
                              ),
                            ),
                            title: Text(
                              guide['name'] ?? 'No Name',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              guide['bio'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              '₹${guide['price']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
