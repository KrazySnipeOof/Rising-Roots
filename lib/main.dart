import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'services/et_calculator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'firebase_options.dart';
import 'models/ag_models.dart' show WeatherAlert, ChatMessage, ForecastDay, WeatherSource, SoilWaterBalance;
import 'services/gemini_service.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadEnv();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => RegenerativeState(),
      child: const RisingRootsApp(),
    ),
  );
}

Future<void> _loadEnv() async {
  const candidates = ['.env', 'env.example'];
  for (final file in candidates) {
    try {
      await dotenv.load(fileName: file);
      debugPrint('Loaded environment configuration from $file');
      return;
    } catch (_) {
      continue;
    }
  }
  debugPrint('No env file found. Falling back to injected environment variables.');
}

Future<void> _configureFirebaseMessaging() async {
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await messaging.getToken();
    }
  } catch (error) {
    debugPrint('Unable to configure Firebase Messaging: $error');
  }
}


class RisingRootsApp extends StatelessWidget {
  const RisingRootsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<RegenerativeState>();
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1D4ED8));

    return MaterialApp(
      title: 'MeteoFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
              bodyColor: const Color(0xFF2D1E2F),
              displayColor: const Color(0xFF2D1E2F),
            ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: scheme.surface,
          foregroundColor: scheme.primary,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D4ED8), brightness: Brightness.dark),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
      ),
      themeMode: app.themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
        Locale('fr'),
        Locale('de'),
        Locale('pt'),
        Locale('hi'),
      ],
      locale: Locale(app.languageCode),
      home: const RisingRootsHome(),
    );
  }
}

class RisingRootsHome extends StatefulWidget {
  const RisingRootsHome({super.key});

  @override
  State<RisingRootsHome> createState() => _RisingRootsHomeState();
}

class _RisingRootsHomeState extends State<RisingRootsHome> {
  int _selectedIndex = 0;
  bool _bootstrapping = true;
  double _bootstrapProgress = 0;
  String _bootstrapStatus = 'Preparing launch systems…';
  bool _promptedNotifications = false;

  final List<_SectionDescriptor> _sections = [
    _SectionDescriptor(
      label: 'Dashboard',
      icon: Icons.auto_graph_rounded,
      builder: (_) => const DashboardView(),
    ),
    _SectionDescriptor(
      label: 'Field Map',
      icon: Icons.map_rounded,
      builder: (_) => const FieldMapView(),
    ),
    _SectionDescriptor(
      label: 'Weather intelligence',
      icon: Icons.cloud_sync_rounded,
      builder: (_) => const WeatherPage(),
    ),
    _SectionDescriptor(
      label: 'Satellite imagery',
      icon: Icons.satellite_alt_rounded,
      builder: (_) => const SatelliteImageryPage(),
    ),
    _SectionDescriptor(
      label: 'Planting schedule',
      icon: Icons.grass_rounded,
      builder: (_) => const PlantingSchedulePage(),
    ),
    _SectionDescriptor(
      label: 'Field management',
      icon: Icons.agriculture_rounded,
      builder: (_) => const FieldManagementPage(),
    ),
    _SectionDescriptor(
      label: 'Discussion forum',
      icon: Icons.forum_rounded,
      builder: (_) => const DiscussionForumPage(),
    ),
    _SectionDescriptor(
      label: 'Notifications',
      icon: Icons.notifications_active_rounded,
      builder: (_) => const NotificationsPage(),
    ),
    _SectionDescriptor(
      label: 'Reports',
      icon: Icons.description_rounded,
      builder: (_) => const ReportsPage(),
    ),
    _SectionDescriptor(
      label: 'Settings',
      icon: Icons.settings_rounded,
      builder: (_) => const SettingsPage(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapApp());
  }

  Future<void> _bootstrapApp() async {
    final state = context.read<RegenerativeState>();
    final tasks = [
      _BootstrapTask(
        label: 'Syncing grower profile',
        runner: () => state.syncUserProfile(),
      ),
      _BootstrapTask(
        label: 'Loading mapped fields',
        runner: () => state.preloadFieldData(),
      ),
      _BootstrapTask(
        label: 'Calibrating climate models',
        runner: () => state.primeWeatherModels(),
      ),
      _BootstrapTask(
        label: 'Fetching local forecast',
        runner: () => state.refreshWeather(),
      ),
      _BootstrapTask(
        label: 'Resolving map location',
        runner: () => state.updateCityLabel(state.mapAnchor),
      ),
      _BootstrapTask(
        label: 'Hydrating AI assistant',
        runner: () => state.hydrateChatbotMemory(),
      ),
      _BootstrapTask(
        label: 'Spooling community feed',
        runner: () => state.prefetchCommunityThreads(),
    ),
  ];

    for (var i = 0; i < tasks.length; i++) {
      setState(() {
        _bootstrapStatus = tasks[i].label;
        _bootstrapProgress = i / tasks.length;
      });
      await tasks[i].runner();
    }

    setState(() {
      _bootstrapProgress = 1;
      _bootstrapping = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return RisingRootsLoader(
        progress: _bootstrapProgress,
        status: _bootstrapStatus,
      );
    }

    final appState = context.watch<RegenerativeState>();

    if (!_promptedNotifications) {
      _promptedNotifications = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _configureFirebaseMessaging();
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = constraints.maxWidth >= 900;
        final currentSection = _sections[_selectedIndex];

        final settingsIndex = _sections.indexWhere((section) => section.label == 'Settings');

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MeteoFlow'),
                Text(
                  appState.cityStateLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_active_rounded),
                onPressed: () {
                  final notificationIndex = _sections.indexWhere((section) => section.label == 'Notifications');
                  if (notificationIndex != -1) {
                    setState(() => _selectedIndex = notificationIndex);
                  }
                },
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: settingsIndex == -1
                    ? null
                    : () => setState(() => _selectedIndex = settingsIndex),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                icon: const Icon(Icons.person),
                label: const Text('Profile'),
                        ),
              const SizedBox(width: 16),
            ],
          ),
          drawer: showRail
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'Navigate',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                        for (int i = 0; i < _sections.length; i++)
                          ListTile(
                            leading: Icon(_sections[i].icon),
                            title: Text(_sections[i].label),
                            selected: _selectedIndex == i,
                            onTap: () {
                              setState(() => _selectedIndex = i);
                              Navigator.of(context).pop();
                            },
                ),
                      ],
                    ),
                  ),
          ),
          body: Stack(
            children: [
              Row(
                children: [
                  if (showRail)
                    _SidebarNav(
                      sections: _sections.where((section) => section.label != 'Notifications' && section.label != 'AI chatbot').toList(),
                      sectionIndices: [
                        for (var i = 0; i < _sections.length; i++)
                          if (_sections[i].label != 'Notifications' && _sections[i].label != 'AI chatbot') i,
                      ],
                  selectedIndex: _selectedIndex,
                      onSelected: (index) => setState(() => _selectedIndex = index),
                    ),
                  Expanded(child: currentSection.builder(context)),
                ],
                        ),
              const _ChatDock(),
            ],
                ),
        );
      },
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RegenerativeState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              _HeroPanel(
                title: 'MeteoFlow Lab',
                subtitle: 'Living blueprints for regenerative farming collectives.',
                highlight: 'Current experiment: Mycelial water routing pilot',
                metricLabel: 'Regenerative impact',
                metricValue: '${state.impactScore.toStringAsFixed(1)} pts',
                onRebalance: state.regeneratePulse,
              ),
              _AmbientPanel(
                solarRadiation: state.solarRadiation,
                temperatureF: state.temperatureF,
                humidityPercent: state.humidityPercent,
                precipForecastInches: state.precipForecastInches,
                windSpeedMph: state.windSpeedMph,
                solarTrend: state.solarTrend,
                temperatureTrend: state.temperatureTrend,
                humidityTrend: state.humidityTrend,
                precipTrend: state.precipTrend,
                windTrend: state.windTrend,
              ),
              const _SatellitePreviewCard(),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final singleColumn = constraints.maxWidth < 900;

              final ritualsCard = _InsightCard(
                      title: 'Upcoming field rituals',
                      child: Column(
                        children: state.upcomingActions
                            .map(
                              (task) => ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  child: Icon(task.icon, color: Theme.of(context).colorScheme.primary),
                                ),
                                title: Text(task.title),
                                subtitle: Text('${DateFormat.MMMd().format(task.when)} • ${task.location}'),
                                trailing: Text(task.owner),
                              ),
                            )
                            .toList(),
                      ),
              );

              final pulseCard = _InsightCard(
                title: 'Precipitation (Tuskegee, AL)',
                trailing: IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => context.read<RegenerativeState>().refreshWeather(),
                ),
                child: SizedBox(
                  height: 260,
                  child: PrecipChart(days: state.forecast, units: state.units),
                ),
              );

              if (singleColumn) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    pulseCard,
                    const SizedBox(height: 24),
                    ritualsCard,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: pulseCard),
                  const SizedBox(width: 24),
                  Expanded(child: ritualsCard),
                ],
              );
            },
          ),
          if (state.mappedFields.isNotEmpty) ...[
            const SizedBox(height: 24),
            _MappedFieldsOverview(fields: state.mappedFields),
          ],
          const SizedBox(height: 24),
          const _CropCalendarPanel(),
        ],
      ),
    );
  }
}

class FieldMapView extends StatefulWidget {
  const FieldMapView({super.key});

  @override
  State<FieldMapView> createState() => _FieldMapViewState();
}

class _FieldMapViewState extends State<FieldMapView> {
  bool _isDrawing = false;
  bool _isLocating = false;
  String? _locationError;
  LatLng? _userLocation;
  double? _locationAccuracyMeters;
  GoogleMapController? _mapController;
  final List<LatLng> _draftPoints = [];

  Future<void> _labelDraftField(BuildContext context, RegenerativeState state) async {
    if (_draftPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least three vertices to outline a field.')),
      );
      return;
    }

    final nameController = TextEditingController();
    final cropController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Label new field'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Field name'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Enter a name' : null,
              ),
              TextFormField(
                controller: cropController,
                decoration: const InputDecoration(labelText: 'Crop / ritual focus'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('Save field'),
          ),
        ],
      ),
    );

    final name = nameController.text.trim();
    final crop = cropController.text.trim();
    nameController.dispose();
    cropController.dispose();

    if (!context.mounted) return;

    if (shouldSave == true) {
      state.addMappedField(name: name, crop: crop, boundary: List<LatLng>.from(_draftPoints));
      setState(() {
        _draftPoints.clear();
        _isDrawing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mapped $name')),
      );
    }
  }

  Future<void> _editField(BuildContext context, RegenerativeState state, MappedField field) async {
    final nameController = TextEditingController(text: field.name);
    final cropController = TextEditingController(text: field.crop);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Customize field'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Field name'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Enter a name' : null,
              ),
              TextFormField(
                controller: cropController,
                decoration: const InputDecoration(labelText: 'Crop / notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    );

    final name = nameController.text.trim();
    final crop = cropController.text.trim();
    nameController.dispose();
    cropController.dispose();

    if (!context.mounted) return;

    if (saved == true) {
      state.updateFieldDetails(field.id, name: name, crop: crop);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated $name')),
      );
    }
  }

  Future<void> _requestPreciseLocation(RegenerativeState state) async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    String? failure;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Enable location services to use precise mapping.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      final latLng = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _userLocation = latLng;
          _locationAccuracyMeters = position.accuracy;
        });
      }

      await state.updateMapAnchor(latLng);
      await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 18));
    } catch (error) {
      failure = error is Exception
          ? error.toString().replaceFirst('Exception: ', '')
          : 'Unable to access precise location.';
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
          _locationError = failure;
        });
      }
      if (failure != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure)),
        );
      }
    }
  }

  Future<void> _centerOnUser() async {
    if (_userLocation == null) return;
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_userLocation!, 18),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RegenerativeState>();

    final polygons = state.mappedFields
        .map(
          (field) => Polygon(
            polygonId: PolygonId(field.id),
            points: field.boundary,
            fillColor: field.color.withOpacity(0.24),
            strokeColor: field.color,
            strokeWidth: 3,
          ),
        )
        .toSet();

    if (_draftPoints.length >= 2) {
      polygons.add(
        Polygon(
          polygonId: const PolygonId('draft'),
          points: _draftPoints,
          fillColor: Colors.white.withOpacity(0.15),
          strokeColor: Colors.white,
          strokeWidth: 2,
        ),
      );
    }

    final markers = <Marker>{};
    if (_userLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user-location'),
          position: _userLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Precise location'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Field atlas',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('Use the live map to trace fields, label blocks, and align rituals spatially.'),
          const SizedBox(height: 24),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 1100;

                final mapCard = Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(target: state.mapAnchor, zoom: 17),
                        mapType: MapType.hybrid,
                        myLocationButtonEnabled: false,
                        compassEnabled: false,
                        tiltGesturesEnabled: false,
                        zoomControlsEnabled: false,
                        polygons: polygons,
                        markers: markers,
                        onMapCreated: (controller) => _mapController = controller,
                        onTap: (position) {
                          if (_isDrawing) {
                            setState(() => _draftPoints.add(position));
                          }
                        },
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.45),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'Tap to drop vertices • follow the Dawning Harvest flow • snap loops before saving',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _MapToolbar(
                              isDrawing: _isDrawing,
                              canUndo: _draftPoints.isNotEmpty,
                              canSave: _draftPoints.length >= 3,
                              onStartDrawing: () {
                                setState(() {
                                  _draftPoints.clear();
                                  _isDrawing = true;
                                });
                              },
                              onUndoPoint: () {
                                if (_draftPoints.isNotEmpty) {
                                  setState(() => _draftPoints.removeLast());
                                }
                              },
                              onResetDraft: () => setState(_draftPoints.clear),
                              onCancelDrawing: () {
                                setState(() {
                                  _draftPoints.clear();
                                  _isDrawing = false;
                                });
                              },
                              onSaveDraft: () => _labelDraftField(context, state),
                            ),
                            const SizedBox(height: 12),
                            _PrecisionPrompt(
                              hasFix: _userLocation != null,
                              isLocating: _isLocating,
                              error: _locationError,
                              accuracyMeters: _locationAccuracyMeters,
                              onRequest: () => _requestPreciseLocation(state),
                              onRecenter: _centerOnUser,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                final ledger = _FieldLedger(
                  fields: state.mappedFields,
                  onEdit: (field) => _editField(context, state, field),
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      SizedBox(height: 420, child: mapCard),
                      const SizedBox(height: 20),
                      ledger,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: mapCard),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: ledger),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MapToolbar extends StatelessWidget {
  const _MapToolbar({
    required this.isDrawing,
    required this.canUndo,
    required this.canSave,
    required this.onStartDrawing,
    required this.onUndoPoint,
    required this.onResetDraft,
    required this.onCancelDrawing,
    required this.onSaveDraft,
  });

  final bool isDrawing;
  final bool canUndo;
  final bool canSave;
  final VoidCallback onStartDrawing;
  final VoidCallback onUndoPoint;
  final VoidCallback onResetDraft;
  final VoidCallback onCancelDrawing;
  final VoidCallback onSaveDraft;

  @override
  Widget build(BuildContext context) {
    if (!isDrawing) {
      return FilledButton.icon(
        onPressed: onStartDrawing,
        icon: const Icon(Icons.add_chart_rounded),
        label: const Text('Sketch new field'),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: canSave ? onSaveDraft : null,
          icon: const Icon(Icons.check),
          label: const Text('Label field'),
        ),
        OutlinedButton.icon(
          onPressed: canUndo ? onUndoPoint : null,
          icon: const Icon(Icons.undo),
          label: const Text('Undo point'),
        ),
        TextButton.icon(
          onPressed: onResetDraft,
          icon: const Icon(Icons.refresh),
          label: const Text('Reset'),
        ),
        TextButton.icon(
          onPressed: onCancelDrawing,
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _PrecisionPrompt extends StatelessWidget {
  const _PrecisionPrompt({
    required this.hasFix,
    required this.isLocating,
    required this.error,
    required this.accuracyMeters,
    required this.onRequest,
    required this.onRecenter,
  });

  final bool hasFix;
  final bool isLocating;
  final String? error;
  final double? accuracyMeters;
  final VoidCallback onRequest;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasFix ? Icons.my_location_rounded : Icons.location_searching_rounded,
                color: hasFix ? const Color(0xFF2563EB) : Colors.black54,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasFix
                      ? 'Precise location locked. Recenter to keep mapping around you.'
                      : 'Share precise location to sketch fields exactly where you stand.',
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              hasFix
                  ? TextButton.icon(
                      onPressed: onRecenter,
                      icon: const Icon(Icons.center_focus_strong_rounded),
                      label: const Text('Recenter'),
                    )
                  : FilledButton.icon(
                      onPressed: isLocating ? null : onRequest,
                      icon: isLocating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.shutter_speed_rounded),
                      label: Text(isLocating ? 'Requesting...' : 'Use precise location'),
                  ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error!,
              style: textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
          ] else if (hasFix && accuracyMeters != null) ...[
            const SizedBox(height: 6),
            Text(
              'Accuracy ±${accuracyMeters!.toStringAsFixed(1)} m',
              style: textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldLedger extends StatelessWidget {
  const _FieldLedger({
    required this.fields,
    required this.onEdit,
  });

  final List<MappedField> fields;
  final ValueChanged<MappedField> onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Field ledger', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text('${fields.length} mapped blocks', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            Expanded(
              child: fields.isEmpty
                  ? const Center(
                      child: Text('Trace a field on the map to start cataloging plots.'),
                    )
                  : ListView.separated(
                      itemCount: fields.length,
                      separatorBuilder: (_, __) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final field = fields[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: field.color,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    field.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(field.areaLabel),
                                IconButton(
                                  onPressed: () => onEdit(field),
                                  icon: const Icon(Icons.edit_note_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              field.crop.isEmpty ? 'Unassigned crop / ritual' : field.crop,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ],
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

class _ModulePage extends StatelessWidget {
  const _ModulePage({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          ...children.map(
            (child) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.description,
    this.badges = const [],
    this.child,
  });

  final String title;
  final String description;
  final List<String> badges;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Card(
              elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (badges.isNotEmpty)
          Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: badges
                .map(
                          (badge) => Chip(
                            label: Text(badge),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
        ],
            ),
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(color: Colors.black87)),
            if (child != null) ...[
              const SizedBox(height: 16),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.trend,
  });

  final String label;
  final String value;
  final String trend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (trend.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              trend,
              style: const TextStyle(color: Colors.blueGrey),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.isUser, required this.text});

  final bool isUser;
  final String text;

  @override
  Widget build(BuildContext context) {
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = isUser
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = isUser ? Colors.white : Colors.black87;
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text, style: TextStyle(color: textColor)),
      ),
    );
  }
}

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final TextEditingController _alertController = TextEditingController();
  final TextEditingController _rainController = TextEditingController();
  final TextEditingController _irrigationController = TextEditingController();
  CropType _selectedCrop = CropType.corn;
  GrowthStage _selectedStage = GrowthStage.mid;

  @override
  void initState() {
    super.initState();
    // Kick off an initial load the first time the page is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<RegenerativeState>();
      if (state.forecast.isEmpty && !state.isWeatherLoading) {
        state.refreshWeather();
      }
    });
  }

  @override
  void dispose() {
    _alertController.dispose();
    _rainController.dispose();
    _irrigationController.dispose();
    super.dispose();
  }

  void _addAlert() {
    final text = _alertController.text.trim();
    if (text.isEmpty) return;
    context.read<RegenerativeState>().addWeatherAlert(text);
    _alertController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<RegenerativeState>();
    final irrigationActions = appState.upcomingActions;

    final alerts = context.watch<RegenerativeState>().weatherAlerts;

    return _ModulePage(
      title: 'Weather & climate intelligence',
      subtitle: 'Switch between Metostat and NASA POWER for your 7‑day outlook.',
      children: [
        _ModuleCard(
          title: '7-day forecast',
          description: 'Temperature, humidity, rainfall, wind, and solar radiation every day.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
              SegmentedButton<WeatherSource>(
                segments: const [
                  ButtonSegment(
                    value: WeatherSource.metostat,
                    label: Text('Metostat'),
                  ),
                  ButtonSegment(
                    value: WeatherSource.nasaPower,
                    label: Text('NASA POWER (observed)'),
                  ),
                ],
                selected: {appState.weatherSource},
                showSelectedIcon: false,
                onSelectionChanged: (set) {
                  final target = set.first;
                  context.read<RegenerativeState>().setWeatherSource(target);
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Note: NASA POWER shows recent observed daily aggregates at coarse resolution; '
                'Metostat provides local forecast. NASA dates use the last 7 fully completed UTC days.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              if (appState.isWeatherLoading)
                Row(
                  children: const [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Loading forecast…'),
                  ],
                )
              else if (appState.weatherError != null)
                Row(
                      children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(appState.weatherError!)),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => context.read<RegenerativeState>().refreshWeather(),
                      child: const Text('Retry'),
                    ),
                  ],
                )
              else if (appState.forecast.isEmpty)
                FilledButton.tonal(
                  onPressed: () => context.read<RegenerativeState>().refreshWeather(),
                  child: const Text('Load forecast'),
                )
              else
                ...appState.forecast.map((ForecastDay f) {
                  final label = DateFormat.E().format(f.date);
                  final highF = (f.maxTempC * 9 / 5 + 32).round();
                  final lowF = (f.minTempC * 9 / 5 + 32).round();
                  final rainIn = (f.rainMm / 25.4);
                  final icon = rainIn > 0.01 ? Icons.cloudy_snowing : Icons.wb_sunny_rounded;
    return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 16),
                        Expanded(child: Text(label)),
                        Text('$highF° / $lowF°'),
                        const SizedBox(width: 12),
                        Text('Rain ${rainIn.toStringAsFixed(2)}"', style: const TextStyle(color: Colors.blueGrey)),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        const _ModuleCard(
          title: 'Evapotranspiration',
          description: 'FAO-56 Penman-Monteith ETc drives irrigation thresholds.',
          child: Column(
            children: [
              _MetricRow(label: 'Today ETc', value: '0.18 in', trend: '+4% vs avg'),
              _MetricRow(label: 'Reference ETo', value: '0.21 in', trend: ''),
              _MetricRow(label: 'Crop coefficient', value: '0.82', trend: ''),
            ],
          ),
        ),
        Builder(
          builder: (context) {
            final appState = context.watch<RegenerativeState>();
            if (appState.forecast.isEmpty) {
              return const _ModuleCard(
                title: 'Crop water requirement (FAO‑56)',
                description: 'Load a forecast to calculate ET₀, ETc, and irrigation needs.',
                child: Text('No forecast loaded yet. Choose a source above to begin.'),
              );
            }
            final today = appState.forecast.first;
            final lat = appState.mapAnchor.latitude;
            final et0Mm = EtCalculator.computeETo(
              date: today.date,
              tMinC: today.minTempC,
              tMaxC: today.maxTempC,
              rhMean: today.humidity,
              windSpeedMs: today.windSpeedMs,
              solarRadMjM2: today.solarRadiation,
              latitudeDeg: lat,
            );
            final kc = RegenerativeState.kcFor(_selectedCrop, _selectedStage);
            final etcMm = et0Mm * kc;
            final forecastRainMm = today.rainMm;
            final extraRainMm = double.tryParse(_rainController.text.trim()) ?? 0.0;
            final irrigationMm = double.tryParse(_irrigationController.text.trim()) ?? 0.0;
            final totalRainMm = (forecastRainMm + extraRainMm).clamp(0.0, double.infinity).toDouble();
            final netMm = (etcMm - totalRainMm - irrigationMm).clamp(0.0, double.infinity);
            final netIn = netMm / 25.4;

            void saveRecord() {
              context.read<RegenerativeState>().recordSoilWaterBalance(
                    date: today.date,
                    crop: _selectedCrop,
                    stage: _selectedStage,
                    et0Mm: et0Mm,
                    etcMm: etcMm,
                    rainfallMm: totalRainMm,
                    irrigationMm: irrigationMm,
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saved today\'s crop water balance.')),
              );
            }

            return _ModuleCard(
              title: 'Crop water requirement (FAO‑56)',
              description:
                  'Reference ET₀, crop coefficient (Kc), and ETc for the selected crop and stage. Recommendations use forecast rain plus your logged irrigation.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      DropdownButton<CropType>(
                        value: _selectedCrop,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedCrop = value);
                        },
                        items: CropType.values
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.label),
                              ),
                            )
                            .toList(),
                      ),
                      DropdownButton<GrowthStage>(
                        value: _selectedStage,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedStage = value);
                        },
                        items: GrowthStage.values
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(s.label),
                              ),
                            )
                            .toList(),
                      ),
                    ],
          ),
                        const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rainController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Additional rainfall (mm)',
                            helperText: 'Forecast rain: ${forecastRainMm.toStringAsFixed(1)} mm',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _irrigationController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Irrigation applied (mm)',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _miniMetric('ET₀', '${et0Mm.toStringAsFixed(1)} mm/day'),
                      _miniMetric('Kc', kc.toStringAsFixed(2)),
                      _miniMetric('ETc', '${etcMm.toStringAsFixed(1)} mm/day'),
                      _miniMetric('Recommended irrigation',
                          '${netMm.toStringAsFixed(1)} mm (${netIn.toStringAsFixed(2)}")'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: saveRecord,
                      icon: const Icon(Icons.save_alt_rounded),
                      label: const Text('Save today to history'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        _ModuleCard(
          title: 'Alert center',
          description: 'Drought, frost, heat stress, and wind alerts consolidated in one feed.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
              if (alerts.isEmpty)
                const Text('No alerts yet. Add your first custom alert below.')
              else
                ListView.separated(
                  itemCount: alerts.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final alert = alerts[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.campaign_rounded),
                      title: Text(alert.message),
                      subtitle: Text(DateFormat.yMMMd().add_jm().format(alert.timestamp)),
                    );
                  },
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _alertController,
                decoration: const InputDecoration(
                  labelText: 'Add custom alert',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 2,
                onSubmitted: (_) => _addAlert(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _addAlert,
                  icon: const Icon(Icons.add_alert_rounded),
                  label: const Text('Save alert'),
            ),
          ),
        ],
                      ),
                    ),
        Builder(
          builder: (context) {
            final fields = context.watch<RegenerativeState>().mappedFields;
            return _ModuleCard(
              title: 'Field vulnerability',
              description: 'Scores combine historical frequency, topography, and crop tolerance.',
              child: Column(
                children: fields
                    .map(
                      (field) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(backgroundColor: field.color, child: Text(field.name.characters.first)),
                        title: Text(field.name),
                        subtitle: const Text('Drought • Flood • Heat • Frost'),
                        trailing: const Text('Overall: Medium'),
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
        const _ModuleCard(
          title: 'Seasonal outlook',
          description: 'NOAA CPC anomalies inform cropping plans and contingency budgets.',
        ),
      ],
    );
  }
}

class SatelliteImageryPage extends StatelessWidget {
  const SatelliteImageryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fields = context.watch<RegenerativeState>().mappedFields;
    return _ModulePage(
      title: 'Satellite imagery & crop health',
      subtitle: 'Sentinel-2 and Landsat feeds with NDVI/NDMI/NDRE/VHI analytics.',
      children: [
        const _ModuleCard(
          title: 'Interactive Earth Engine app',
          description: 'Explore meteorological layers powered by Google Earth Engine (embedded).',
          child: EarthEngineEmbed(
            url: 'https://olakanmieniola10.users.earthengine.app/view/meteoflow',
            height: 640,
          ),
        ),
        _ModuleCard(
          title: 'Vegetation indices',
          description: 'Color-coded zones highlight stress from drought, pests, or nutrient issues.',
          badges: const ['NDVI', 'NDMI', 'NDRE', 'VHI'],
          child: Column(
            children: fields
                .map(
                  (field) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: field.color.withOpacity(0.2), child: const Icon(Icons.terrain)),
                    title: Text(field.name),
                    subtitle: Text(field.crop),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('NDVI 0.74'),
                        Text('NDMI 0.32', style: TextStyle(color: Colors.blueGrey)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const _ModuleCard(
          title: 'Time-series comparison',
          description: 'Swipe or split-view imagery across two dates to spot sudden NDVI drops.',
        ),
        const _ModuleCard(
          title: 'Automated stress alerts',
          description: 'Trigger alerts whenever NDVI drops >8% within 72 hours.',
        ),
      ],
    );
  }
}

class PlantingSchedulePage extends StatelessWidget {
  const PlantingSchedulePage({super.key});

  @override
  Widget build(BuildContext context) => const _PlantingScheduleContent();
}

class _PlantingScheduleContent extends StatefulWidget {
  const _PlantingScheduleContent({super.key});

  @override
  State<_PlantingScheduleContent> createState() => _PlantingScheduleContentState();
}

class _PlantingScheduleContentState extends State<_PlantingScheduleContent> {
  List<Map<String, String>> _rows = const [];
  String? _selectedCrop;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCsv();
  }

  String _prettyCsvKey(String key) {
    final cleaned = key.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return key;
    return cleaned.split(' ').map((w) {
      if (w.isEmpty) return w;
      final head = w[0].toUpperCase();
      final tail = w.length > 1 ? w.substring(1) : '';
      return '$head$tail';
    }).join(' ');
  }

  Future<void> _loadCsv() async {
    try {
      final csv = await DefaultAssetBundle.of(context).loadString('assets/crop_stage_calendar.csv');
      final lines = const LineSplitter().convert(csv).where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) {
        setState(() {
          _rows = const [];
          _loading = false;
        });
        return;
      }
      final header = _splitCsvLine(lines.first);
      final rows = <Map<String, String>>[];
      for (var i = 1; i < lines.length; i++) {
        final cols = _splitCsvLine(lines[i]);
        final map = <String, String>{};
        for (var j = 0; j < header.length; j++) {
          final key = header[j].trim();
          final val = j < cols.length ? cols[j].trim() : '';
          map[key] = val;
        }
        rows.add(map);
      }
      setState(() {
        _rows = rows;
        _selectedCrop = rows.isNotEmpty ? (rows.first['crop'] ?? '').trim() : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"'); // escaped quote
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final crops = _rows
        .map((r) => (r['crop'] ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final selectedRows = _rows.where((r) => (r['crop'] ?? '').trim() == (_selectedCrop ?? '').trim()).toList();

    return _ModulePage(
      title: 'Planting schedule optimizer',
      subtitle: 'Select a crop to view stages, dates, and coefficients.',
      children: [
        _ModuleCard(
          title: 'Select crop',
          description: 'Data driven from crop_stage_calendar.csv',
          child: _loading
              ? const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : _error != null
                  ? Text('Failed to load CSV: $_error')
                  : DropdownButton<String>(
                      value: _selectedCrop,
                      isExpanded: true,
                      hint: const Text('Choose a crop'),
                      items: crops.map((c) {
                        final first = _rows.firstWhere(
                          (r) => ((r['crop'] ?? '').trim()) == c,
                          orElse: () => const {},
                        );
                        final start = first['crop_start_date'] ?? first['start_date'] ?? '';
                        final stage = first['planting_stage'] ?? first['stage'] ?? '';
                        return DropdownMenuItem(
                          value: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                              Text(c, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (start.isNotEmpty || stage.isNotEmpty)
                                Text(
                                  [if (start.isNotEmpty) 'Start $start', if (stage.isNotEmpty) 'Stage $stage'].join(' • '),
                                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedCrop = v),
                    ),
        ),
        if (!_loading && _error == null && (_selectedCrop ?? '').isNotEmpty)
          _ModuleCard(
            title: 'Calendar • $_selectedCrop',
            description: 'Stages, dates, Kc, and notes',
            child: Column(
              children: selectedRows.map((row) {
                final cropName = row['crop'] ?? '—';
                final safe = Map<String, String>.from(row)
                  ..removeWhere((k, v) => (v).trim().isEmpty)
                  ..remove('crop');
                final coreKeys = [
                  // Common/expected keys
                  'planting_date',
                  'stage_id',
                  'stage',
                  'start_day',
                  'end_day',
                  'stage_start_date',
                  'stage_end_date',
                  // Fall-back/alt naming support
                  'crop_start_date',
                  'start_date',
                  'end_date',
                  'planting_stage',
                  'planting_id',
                  'id',
                  'kc',
                  'notes',
                ];
                // Order known keys first, then any extras from the CSV.
                final ordered = <MapEntry<String, String>>[
                  for (final k in coreKeys)
                    if (safe.containsKey(k)) MapEntry(k, safe[k]!),
                  ...safe.entries.where((e) => !coreKeys.contains(e.key)),
                ];
                return Card(
              elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: const Icon(Icons.spa, color: Colors.black87),
                    ),
                            const SizedBox(width: 12),
                    Expanded(
                              child: Text(
                                cropName,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
          ),
          const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 10,
                          children: ordered.map((e) {
                            final label = _prettyCsvKey(e.key);
                            return _miniMetric(label, e.value);
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ClimateRiskPage has been merged into WeatherPage.

class FieldManagementPage extends StatelessWidget {
  const FieldManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fields = context.watch<RegenerativeState>().mappedFields;
    return _ModulePage(
      title: 'Field management',
      subtitle: 'Add, edit, and analyze every block in the cooperative.',
      children: [
        _ModuleCard(
          title: 'Directory',
          description: 'Metadata, crop, irrigation method, and benchmarks.',
                      child: Column(
            children: fields
                .map(
                  (field) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: field.color,
                        child: const Icon(Icons.park, color: Colors.white),
                      ),
                      title: Text(field.name),
                      subtitle: Text('${field.crop} • ${field.areaLabel}'),
                      trailing: const Icon(Icons.edit_note_rounded),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const _ModuleCard(
          title: 'Data fields',
          description: 'Soil series, crop history, irrigation hardware, compliance docs.',
        ),
      ],
    );
  }
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({super.key});

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class EarthEngineEmbed extends StatefulWidget {
  const EarthEngineEmbed({
    super.key,
    required this.url,
    this.height = 600,
  });
  final String url;
  final double height;

  @override
  State<EarthEngineEmbed> createState() => _EarthEngineEmbedState();
}

class _EarthEngineEmbedState extends State<EarthEngineEmbed> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'ee-iframe-${DateTime.now().microsecondsSinceEpoch}';
    if (kIsWeb) {
      // Register an iframe factory for this instance
      // ignore: undefined_prefixed_name
      ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final iframe = html.IFrameElement()
          ..src = widget.url
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '${widget.height}px';
        return iframe;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SizedBox(
        height: widget.height,
        child: HtmlElementView(viewType: _viewType),
      );
    }
    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
        const Text('This embed is available on the web build.'),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () {},
          child: const Text('Open in browser'),
        ),
      ],
    );
  }
}

class _ChatPanelState extends State<_ChatPanel> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;
  final FocusNode _inputFocus = FocusNode();

  void focusInput() {
    if (mounted && !_inputFocus.hasFocus) {
      _inputFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    _controller.clear();
    try {
      await context.read<RegenerativeState>().sendChatMessage(text);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<RegenerativeState>().chatHistory;
    final theme = Theme.of(context);
    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          ListTile(
            title: const Text('AI agronomy assistant', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              'Context-aware answers referencing your fields and knowledge base.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
                      children: [
                ...history.map((message) => _ChatBubble(isUser: message.role == 'user', text: message.content)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Ask anything…',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isSending ? null : _handleSend,
                  icon: _isSending
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DiscussionForumPage extends StatefulWidget {
  const DiscussionForumPage({super.key});

  @override
  State<DiscussionForumPage> createState() => _DiscussionForumPageState();
}

class _DiscussionForumPageState extends State<DiscussionForumPage> {
  int _selectedScope = 0;
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  bool _canPost = false;
  int _seenLocationVersion = 0;

  @override
  void initState() {
    super.initState();
    _topicController.addListener(_updateCanPost);
    _detailsController.addListener(_updateCanPost);
  }

  @override
  void dispose() {
    _topicController.removeListener(_updateCanPost);
    _detailsController.removeListener(_updateCanPost);
    _topicController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _updateCanPost() {
    final next = _topicController.text.trim().isNotEmpty && _detailsController.text.trim().isNotEmpty;
    if (next != _canPost) {
      setState(() => _canPost = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<RegenerativeState>();
    final groups = appState.discussionGroups;
    if (_seenLocationVersion != appState.locationVersion) {
      _seenLocationVersion = appState.locationVersion;
      _selectedScope = 0;
    }
    final active = groups[_selectedScope];
    return _ModulePage(
      title: 'Discussion forum',
      subtitle: 'Host grower-to-grower dialogues across the cooperative.',
      children: [
        SegmentedButton<int>(
          segments: [
            for (var i = 0; i < groups.length; i++)
              ButtonSegment(value: i, label: Text(groups[i].title)),
          ],
          selected: <int>{_selectedScope},
          onSelectionChanged: (selection) => setState(() => _selectedScope = selection.first),
        ),
        _ModuleCard(
          title: active.title,
          description: active.subtitle,
          child: Column(
            children: [
              for (final thread in active.threads)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(thread.origin.characters.first),
                ),
                title: Text(thread.title),
                subtitle: Text('${thread.origin} • ${thread.summary}'),
                    trailing: Text('${thread.replies} replies'),
                  ),
                ),
              const Divider(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Share an update with ${active.title.toLowerCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
                        const SizedBox(height: 12),
              TextField(
                controller: _topicController,
                decoration: const InputDecoration(labelText: 'Conversation title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detailsController,
                decoration: const InputDecoration(labelText: 'Details / context'),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _canPost
                      ? () {
                          appState.addDiscussionThread(
                            scope: DiscussionScope.values[_selectedScope],
                            title: _topicController.text,
                            summary: _detailsController.text,
                          );
                          _topicController.clear();
                          _detailsController.clear();
                        }
                      : null,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Post'),
                ),
              ),
            ],
          ),
        ),
        const _ModuleCard(
          title: 'Moderation & tags',
          description: 'Auto-tag conversations by crop, risk, or practice to streamline filtering.',
        ),
      ],
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = context.watch<RegenerativeState>().upcomingActions;
    return _ModulePage(
      title: 'Notifications & alerts',
      subtitle: 'Review past alerts and configure daily push schedules.',
                  children: [
        _ModuleCard(
          title: 'Recent alerts',
          description: 'FCM push at 7 AM plus weather & compliance reminders.',
          child: SizedBox(
            height: 220,
            child: ListView.separated(
              itemCount: actions.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final task = actions[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(task.icon, color: Theme.of(context).colorScheme.primary),
                  title: Text(task.title),
                  subtitle: Text(DateFormat.yMMMd().add_jm().format(task.when)),
                  trailing: const Text('Sent'),
                );
              },
                ),
              ),
            ),
        const _ModuleCard(
          title: 'Preferences',
          description: 'Choose channels (SMS, email, push) and quiet hours.',
        ),
      ],
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ModulePage(
      title: 'Reports & exports',
      subtitle: 'Generate seasonal summaries for lenders and sustainability programs.',
      children: [
        _ModuleCard(
          title: 'Seasonal performance',
          description: 'Yield, resource use, climate risk, and regenerative impact.',
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Open seasonal report'),
                ),
              ),
            ),
        _ModuleCard(
          title: 'Export center',
          description: 'PDF, CSV, or API push to partner systems.',
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () {},
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF'),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () {},
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Export CSV'),
          ),
        ],
      ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<String> _services = [
    'Metostat',
    'NASA POWER',
    'AI',
  ];

  final Map<String, TextEditingController> _apiControllers = {};
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  TextEditingController _controllerFor(String service, String value) {
    final controller = _apiControllers.putIfAbsent(service, () => TextEditingController());
    if (controller.text != value) {
      controller.text = value;
      controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
    }
    return controller;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    for (final controller in _apiControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<RegenerativeState>();
    final apiKeys = appState.apiKeys;

    return _ModulePage(
      title: 'Settings & profile',
      subtitle: 'Farm details, integrations, and app configuration.',
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 600;
                final content = <Widget>[
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.person, size: 48, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Welcome ${_firstNameController.text.isEmpty ? 'Farmer' : _firstNameController.text}!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(appState.cityStateLabel, style: const TextStyle(color: Colors.black54)),
                ];

                final fields = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(labelText: 'First name'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(labelText: 'Last name'),
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ...content,
                      const SizedBox(height: 16),
                      fields,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: content,
                    ),
                    SizedBox(width: constraints.maxWidth * 0.4, child: fields),
                  ],
                );
              },
            ),
          ),
        ),
        _ModuleCard(
          title: 'Farm profile',
          description: 'Update headquarters, acreage, and contact details.',
          child: Column(
            children: [
              const TextField(decoration: InputDecoration(labelText: 'Farm name')),
              const SizedBox(height: 12),
              _ReadOnlyField(label: 'Location', value: appState.cityStateLabel),
              const SizedBox(height: 12),
              const TextField(decoration: InputDecoration(labelText: 'Primary email')),
            ],
          ),
        ),
        _ModuleCard(
          title: 'Integrations',
          description: 'Manage API keys for Metostat, NASA POWER, and AI.',
          child: Column(
            children: _services
        .map(
                  (service) {
                    final controller = _controllerFor(service, apiKeys[service] ?? '');
                    final label = service == 'AI' ? 'AI API key' : '$service API key';
    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: label,
                          hintText: 'Paste your $label',
                          suffixIcon: controller.text.isNotEmpty
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : null,
                        ),
                        onChanged: (value) => context.read<RegenerativeState>().updateApiKey(service, value),
                      ),
                    );
                  },
                )
                .toList(),
          ),
        ),
        const _ModuleCard(
          title: 'Application preferences',
          description: 'Theme, measurement units, language, and notification defaults.',
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: {appState.themeMode},
                  onSelectionChanged: (s) => appState.setThemeMode(s.first),
                ),
                const SizedBox(height: 16),
                Text('Measurement units', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButton<Units>(
                  value: appState.units,
                  items: Units.values
                      .map((u) => DropdownMenuItem(value: u, child: Text(u.label)))
                      .toList(),
                  onChanged: (u) {
                    if (u != null) appState.setUnits(u);
                  },
                ),
                const SizedBox(height: 16),
                Text('Language', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: appState.languageCode,
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'es', child: Text('Español')),
                  ],
                  onChanged: (code) {
                    if (code != null) appState.setLanguage(code);
                  },
                ),
                const SizedBox(height: 16),
                Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: appState.notificationsEnabled,
                  onChanged: (v) {
                    appState.setNotificationsEnabled(v);
                    if (v) {
                      _configureFirebaseMessaging();
                    }
                  },
                  title: const Text('Enable push notifications'),
                  subtitle: Text('Default time ${appState.notificationTime}'),
                ),
                Row(
                  children: [
                    const Icon(Icons.schedule),
                    const SizedBox(width: 8),
                    Text('Default alert time'),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: () async {
                        final parts = appState.notificationTime.split(':');
                        final initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
                        final picked = await showTimePicker(context: context, initialTime: initial);
                        if (picked != null) {
                          final hh = picked.hour.toString().padLeft(2, '0');
                          final mm = picked.minute.toString().padLeft(2, '0');
                          appState.setNotificationTime('$hh:$mm');
                        }
                      },
                      child: Text(appState.notificationTime),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            border: Border.all(color: Colors.black12),
          ),
          child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _MappedFieldsOverview extends StatelessWidget {
  const _MappedFieldsOverview({required this.fields});

  final List<MappedField> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recentFields = fields.reversed.take(3).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
        children: [
          const Text(
                  'Latest field blocks',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${fields.length} total',
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...recentFields.map(
              (field) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: field.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.terrain_rounded, color: field.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(field.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            field.crop.isEmpty ? 'Unassigned rotation' : field.crop,
                            style: const TextStyle(color: Colors.black54),
                          ),
                  ],
                ),
              ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(field.areaLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${field.boundary.length} pts', style: const TextStyle(color: Colors.black45)),
        ],
                    ),
                  ],
                ),
              ),
            ),
            if (fields.length > recentFields.length)
              Text(
                '+${fields.length - recentFields.length} more mapped on Field atlas',
                style: const TextStyle(color: Colors.black54),
              ),
          ],
        ),
      ),
    );
  }
}

class PrecipChart extends StatelessWidget {
  const PrecipChart({super.key, required this.days, required this.units});

  final List<ForecastDay> days;
  final Units units;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Center(child: Text('No precipitation data loaded.'));
    }
    final values = days.map((d) => d.rainMm).toList();
    final maxMm = values.fold<double>(0, (m, v) => v > m ? v : m);
    final maxY = (maxMm * (units == Units.metric ? 1 : 1 / 25.4)).clamp(0.0, double.infinity);
    final spots = <FlSpot>[];
    for (var i = 0; i < days.length; i++) {
      final mm = days[i].rainMm;
      final yRaw = units == Units.metric ? mm : mm / 25.4;
      final y = yRaw < 0 ? 0.0 : yRaw;
      spots.add(FlSpot(i.toDouble(), y));
    }

    String leftLabel(double v) {
      if (units == Units.metric) {
        return '${v.toStringAsFixed(1)} mm';
      }
      return '${v.toStringAsFixed(2)}"';
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: (maxY == 0 ? 1.0 : maxY) * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              reservedSize: 56,
              showTitles: true,
              getTitlesWidget: (value, _) => Text(leftLabel(value)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, _) {
                final idx = value.clamp(0, days.length - 1).round();
                final label = DateFormat.E().format(days[idx].date);
                return Text(label, style: const TextStyle(fontSize: 12));
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            color: Theme.of(context).colorScheme.primary,
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
            ),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _BootstrapTask {
  const _BootstrapTask({required this.label, required this.runner});

  final String label;
  final Future<void> Function() runner;
}

class _SectionDescriptor {
  const _SectionDescriptor({
    required this.label,
    required this.icon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

enum DiscussionScope { county, state, region, global }
enum WeatherDataSource { metostat, nasaPower }

class _SidebarNav extends StatelessWidget {
  const _SidebarNav({
    required this.sections,
    required this.sectionIndices,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_SectionDescriptor> sections;
  final List<int> sectionIndices;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 132,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(color: colorScheme.surfaceContainerHighest),
        ),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
                itemCount: sections.length,
                itemBuilder: (context, index) {
                  final section = sections[index];
                  final globalIndex = sectionIndices[index];
                  final isSelected = globalIndex == selectedIndex;
                  final bgColor = isSelected ? colorScheme.primary.withOpacity(0.12) : Colors.transparent;
                  final iconColor = isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;
                  final textColor = isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onSelected(globalIndex),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Icon(section.icon, color: iconColor),
                            const SizedBox(height: 6),
                            Text(
                              section.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: textColor,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('New'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatDock extends StatefulWidget {
  const _ChatDock();

  @override
  State<_ChatDock> createState() => _ChatDockState();
}

class _ChatDockState extends State<_ChatDock> with SingleTickerProviderStateMixin {
  bool _open = false;
  final GlobalKey<_ChatPanelState> _chatKey = GlobalKey();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _controller.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) => _chatKey.currentState?.focusInput());
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isNarrow = media.size.width < 600;
    final bottomInset = media.padding.bottom;
    final chatCard = SizeTransition(
      sizeFactor: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      axisAlignment: -1,
      child: Align(
        alignment: Alignment.bottomRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isNarrow ? media.size.width - 32 : 420,
            maxHeight: media.size.height * 0.65,
          ),
          child: Padding(
            padding: const EdgeInsets.only(right: 24, bottom: 96),
            child: _ChatPanel(key: _chatKey),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        if (_open)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_open,
              child: chatCard,
            ),
          ),
        Positioned(
          right: 24,
          bottom: 24 + bottomInset,
          child: FloatingActionButton(
            heroTag: 'chat-dock',
            tooltip: _open ? 'Close chat' : 'Open AI assistant',
            onPressed: _toggle,
            child: Icon(_open ? Icons.close_rounded : Icons.chat_bubble_rounded),
          ),
        ),
      ],
    );
  }
}

class RisingRootsLoader extends StatelessWidget {
  const RisingRootsLoader({super.key, required this.progress, required this.status});

  final double progress;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.surfaceContainerHighest,
              colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth < 440 ? constraints.maxWidth - 48 : 440.0;
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 38,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(Icons.grass_rounded, size: 32, color: colorScheme.primary),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'MeteoFlow',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'MeteoFlow is loading…',
                          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        _AnimatedProgressBar(value: progress),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(Icons.wifi_protected_setup_rounded, size: 18, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                status,
                                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.primary),
                              ),
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
      ),
    );
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      builder: (context, animatedValue, _) {
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: animatedValue,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [colorScheme.primary, colorScheme.secondary],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(animatedValue * 100).clamp(0, 100).toStringAsFixed(0)}% ready',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.title,
    required this.subtitle,
    required this.highlight,
    required this.metricLabel,
    required this.metricValue,
    required this.onRebalance,
  });

  final String title;
  final String subtitle;
  final String highlight;
  final String metricLabel;
  final String metricValue;
  final VoidCallback onRebalance;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1D4ED8),
            Color(0xFF38BDF8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.85))),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(highlight, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            metricLabel.toUpperCase(),
            style: TextStyle(color: Colors.white.withOpacity(0.8), letterSpacing: 1.2),
          ),
          Text(
            metricValue,
            style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              foregroundColor: Colors.white,
            ),
            onPressed: onRebalance,
            icon: const Icon(Icons.bolt),
            label: const Text('Rebalance terrain'),
          ),
        ],
      ),
    );
  }
}

class _AmbientPanel extends StatelessWidget {
  const _AmbientPanel({
    required this.solarRadiation,
    required this.temperatureF,
    required this.humidityPercent,
    required this.precipForecastInches,
    required this.windSpeedMph,
    required this.solarTrend,
    required this.temperatureTrend,
    required this.humidityTrend,
    required this.precipTrend,
    required this.windTrend,
  });

  final double solarRadiation;
  final double temperatureF;
  final double humidityPercent;
  final double precipForecastInches;
  final double windSpeedMph;
  final double solarTrend;
  final double temperatureTrend;
  final double humidityTrend;
  final double precipTrend;
  final double windTrend;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Field climate brief', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AmbientMetric(
                  label: 'Solar radiation',
                  value: '${solarRadiation.toStringAsFixed(1)} kWh/m²',
                  trend: solarTrend,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AmbientMetric(
                  label: 'Temperature',
                  value: context.watch<RegenerativeState>().formatTemperature(temperatureF),
                  trend: temperatureTrend,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AmbientMetric(
                  label: 'Relative humidity',
                  value: '${humidityPercent.toStringAsFixed(0)}%',
                  trend: humidityTrend,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AmbientMetric(
                  label: 'Precipitation',
                  value: '${context.watch<RegenerativeState>().formatPrecip(precipForecastInches)} forecast',
                  trend: precipTrend,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AmbientMetric(
                  label: 'Wind speed',
                  value: '${context.watch<RegenerativeState>().formatWind(windSpeedMph)} SW',
                  trend: windTrend,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmbientMetric extends StatelessWidget {
  const _AmbientMetric({
    required this.label,
    required this.value,
    required this.trend,
  });

  final String label;
  final String value;
  final double trend;

  @override
  Widget build(BuildContext context) {
    final color = trend >= 0 ? const Color(0xFF2563EB) : Colors.deepOrange;
    final icon = trend >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 4),
              Text(
                '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(right: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _SatellitePreviewCard extends StatelessWidget {
  const _SatellitePreviewCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final previewUrl = context.watch<RegenerativeState>().satellitePreviewUrl;
    // Compact preview size so it fits neatly beside the Field climate brief panel.
    const maxWidth = 420.0;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SatelliteImageryPage()),
          );
        },
        child: SizedBox(
          width: maxWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Row(
            children: [
                    Icon(Icons.satellite_alt_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('Satellite snapshot', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: previewUrl != null
                        ? Image.network(previewUrl, fit: BoxFit.cover)
                        : Container(
                            color: colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported_outlined),
                          ),
                  ),
                ),
              ),
          const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Text(
                  'Tap to open the Satellite imagery page',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _miniMetric(String label, String value) {
  return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
            children: [
      Text(label, style: const TextStyle(color: Colors.black54)),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _CropCalendarPanel extends StatefulWidget {
  const _CropCalendarPanel({super.key});

  @override
  State<_CropCalendarPanel> createState() => _CropCalendarPanelState();
}

class _CropCalendarPanelState extends State<_CropCalendarPanel> {
  List<Map<String, String>> _rows = const [];
  String? _selectedCrop;
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCsv();
  }

  Future<void> _loadCsv() async {
    try {
      final csv = await DefaultAssetBundle.of(context).loadString('assets/crop_stage_calendar.csv');
      final lines = const LineSplitter().convert(csv).where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) {
        setState(() {
          _rows = const [];
          _loading = false;
        });
        return;
      }
      final header = _splitCsvLine(lines.first);
      final rows = <Map<String, String>>[];
      for (var i = 1; i < lines.length; i++) {
        final cols = _splitCsvLine(lines[i]);
        final map = <String, String>{};
        for (var j = 0; j < header.length; j++) {
          final key = header[j].trim();
          final val = j < cols.length ? cols[j].trim() : '';
          map[key] = val;
        }
        rows.add(map);
      }
      rows.sort((a, b) => (a['crop'] ?? '').toLowerCase().compareTo((b['crop'] ?? '').toLowerCase()));
      setState(() {
        _rows = rows;
        _selectedCrop = rows.isNotEmpty ? (rows.first['crop'] ?? '').trim() : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final crops = _rows
        .map((r) => (r['crop'] ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .where((name) => name.toLowerCase().contains(_query.toLowerCase()))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final selectedRows = _rows.where((r) => (r['crop'] ?? '').trim() == (_selectedCrop ?? '').trim()).toList();

    return _InsightCard(
      title: 'Crop calendar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search crops'),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_error != null)
                Text('CSV error: $_error', style: TextStyle(color: theme.colorScheme.error))
              else
                DropdownButton<String>(
                  value: _selectedCrop != null && crops.contains(_selectedCrop) ? _selectedCrop : (crops.isNotEmpty ? crops.first : null),
                  hint: const Text('Select crop'),
                  items: crops.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _selectedCrop = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_loading && _error == null && (_selectedCrop ?? '').isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: ExpansionPanelList.radio(
                elevation: 0,
                materialGapSize: 8,
                expandedHeaderPadding: EdgeInsets.zero,
                children: selectedRows.map((row) {
                  final stage = row['stage'] ?? 'Stage';
                  final start = row['stage_start_date'] ?? row['start_date'] ?? '';
                  final end = row['stage_end_date'] ?? row['end_date'] ?? '';
                  final startDay = row['start_day'] ?? '';
                  final endDay = row['end_day'] ?? '';
                  final title = '$stage • ${start.isNotEmpty && end.isNotEmpty ? '$start – $end' : 'Dates TBD'}';
                  final safe = Map<String, String>.from(row)..removeWhere((k, v) => v.trim().isEmpty);
                  return ExpansionPanelRadio(
                    value: title,
                    headerBuilder: (ctx, isOpen) {
                      return ListTile(
                        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Days $startDay–$endDay'),
                      );
                    },
                    body: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 10,
                        children: safe.entries.map((e) {
                          if (e.key == 'crop') return const SizedBox.shrink();
                          return _miniMetric(_prettyKey(e.key), e.value);
                        }).toList(),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ),
        ],
      ),
    );
  }

  String _prettyKey(String key) {
    final cleaned = key.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return key;
    return cleaned.split(' ').map((w) {
      if (w.isEmpty) return w;
      final head = w[0].toUpperCase();
      final tail = w.length > 1 ? w.substring(1) : '';
      return '$head$tail';
    }).join(' ');
  }
}

enum CropType { corn, soybean, cotton }

enum GrowthStage { initial, mid, late }

extension CropTypeLabel on CropType {
  String get label {
    switch (this) {
      case CropType.corn:
        return 'Corn';
      case CropType.soybean:
        return 'Soybean';
      case CropType.cotton:
        return 'Cotton';
    }
  }
}

extension GrowthStageLabel on GrowthStage {
  String get label {
    switch (this) {
      case GrowthStage.initial:
        return 'Initial';
      case GrowthStage.mid:
        return 'Mid-season';
      case GrowthStage.late:
        return 'Late';
    }
  }
}

class RegenerativeState extends ChangeNotifier {
  RegenerativeState();

  final _random = Random();
  // Preferences
  ThemeMode _themeMode = ThemeMode.light;
  Units _units = Units.imperial;
  String _languageCode = 'en';
  bool _notificationsEnabled = true;
  String _notificationTime = '07:00';
  String? _satellitePreviewUrl =
      'https://staticmap.openstreetmap.de/staticmap.php?center=32.4296,-85.7073&zoom=7&size=720x540&maptype=mapnik';
  WeatherSource _weatherSource = WeatherSource.nasaPower;
  bool _weatherLoading = false;
  String? _weatherError;
  List<ForecastDay> _forecast = const [];

  final List<SoilHealthReading> _soilReadings = List.generate(
    6,
    (index) => SoilHealthReading(
      date: DateTime(2025, DateTime.january + index, 1 + index * 3),
      organicMatter: 3 + index * 0.7 + Random().nextDouble(),
      infiltration: 2 + index * 0.3 + Random().nextDouble(),
    ),
  );

  final List<RegenerativeBlueprint> _blueprints = [
    RegenerativeBlueprint(
      name: 'Dune Orchard',
      biome: 'Arid coast',
      description: 'Fog-net orchards that capture saline mist and redirect carbon-rich dew.',
      focus: const ['Fog nets', 'Agroforestry', 'Bioceramics'],
      duration: 8,
      carbonScore: 86,
    ),
    RegenerativeBlueprint(
      name: 'Lumen Valley',
      biome: 'Temperate highland',
      description: 'Light-bending terraces that wake soil microbes at sunrise.',
      focus: const ['Light wells', 'Mycelial mats', 'Contour guilds'],
      duration: 6,
      carbonScore: 92,
    ),
    RegenerativeBlueprint(
      name: 'Cloud Meadow',
      biome: 'Humid prairie',
      description: 'Breathable biofabric capturing humidity for slow-release irrigation.',
      focus: const ['Biofabric', 'Prairie guilds'],
      duration: 5,
      carbonScore: 78,
    ),
  ];

  final List<ActivationTask> _upcomingActions = [
    ActivationTask(
      title: 'Prime mycelial channels',
      location: 'Lab plot C',
      owner: 'Nia',
      icon: Icons.science_rounded,
      when: DateTime.now().add(const Duration(hours: 6)),
    ),
    ActivationTask(
      title: 'Deploy fog nets',
      location: 'Dune Orchard ridge',
      owner: 'Milo',
      icon: Icons.cloud_rounded,
      when: DateTime.now().add(const Duration(hours: 26)),
    ),
    ActivationTask(
      title: 'Biodiversity census',
      location: 'North basin',
      owner: 'Aria',
      icon: Icons.auto_awesome_rounded,
      when: DateTime.now().add(const Duration(days: 2)),
    ),
  ];

  final List<MarketListing> _marketListings = [
    MarketListing(
      title: 'Soil listening kit',
      description: 'Acoustic probes that translate microbial chatter into spectral maps.',
      creditLabel: '32 regen credits',
      delivery: 'Ships in 2 days',
      icon: Icons.graphic_eq_rounded,
    ),
    MarketListing(
      title: 'Biochar mist blend',
      description: 'High surface-area biochar suspended in aloe for foliar feeding.',
      creditLabel: '11 regen credits',
      delivery: 'Pickup: Lab 06',
      icon: Icons.local_florist_rounded,
    ),
    MarketListing(
      title: 'Commons residency',
      description: 'Residency slot for a neighboring farm to co-create carbon rituals.',
      creditLabel: 'Invite-only',
      delivery: 'Seasonal block',
      icon: Icons.handshake_rounded,
    ),
  ];

  final List<MappedField> _mappedFields = [
    const MappedField(
      id: 'north-ridge',
      name: 'Soybean',
      crop: 'Soybean',
      color: Color(0xFF2563EB),
      boundary: [
        LatLng(32.4310, -85.7085),
        LatLng(32.4312, -85.7068),
        LatLng(32.4302, -85.7066),
        LatLng(32.4300, -85.7080),
      ],
    ),
    const MappedField(
      id: 'biochar-terrace',
      name: 'Corn',
      crop: 'Corn',
      color: Color(0xFF38BDF8),
      boundary: [
        LatLng(32.4288, -85.7092),
        LatLng(32.4291, -85.7079),
        LatLng(32.4281, -85.7077),
        LatLng(32.4279, -85.7090),
      ],
    ),
    const MappedField(
      id: 'wetland-braid',
      name: 'Cotton',
      crop: 'Cotton',
      color: Color(0xFF4ADE80),
      boundary: [
        LatLng(32.4305, -85.7098),
        LatLng(32.4307, -85.7086),
        LatLng(32.4298, -85.7084),
        LatLng(32.4296, -85.7096),
      ],
    ),
  ];
  final _fieldPalette = [
    const Color(0xFF2563EB),
    const Color(0xFF38BDF8),
    const Color(0xFF4ADE80),
    const Color(0xFFF472B6),
    const Color(0xFFFACC15),
    const Color(0xFFFB923C),
    const Color(0xFFA855F7),
  ];
  int _fieldColorCursor = 0;
  LatLng _mapAnchor = const LatLng(32.4296, -85.7073); // Tuskegee University, AL

  final List<NetworkThread> _threads = [
    NetworkThread(
      title: 'Does anyone have wind data from ridge tunnels?',
      origin: 'Isla, Coastal Node',
      summary: 'Testing vented wind harps and need comparative baselines.',
      replies: 14,
      recencyLabel: '15m ago',
    ),
    NetworkThread(
      title: 'Microclover understory results',
      origin: 'Portland Collective',
      summary: 'Sharing 3-month water retention numbers + drone imagery.',
      replies: 32,
      recencyLabel: '1h ago',
    ),
    NetworkThread(
      title: 'Looking for carbon credit co-signers',
      origin: 'Kinship Farm',
      summary: 'Need partners for a 240-acre blended fiber grant.',
      replies: 9,
      recencyLabel: '1d ago',
    ),
  ];

  double _impactScore = 74;
  double _regenRate = 5.8;
  double _carbonOffset = 18.6;
  double _solarRadiation = 5.6;
  double _temperatureF = 86;
  double _humidityPercent = 62;
  double _precipForecastInches = 0.15;
  double _windSpeedMph = 12;
  double _solarTrend = 3.2;
  double _temperatureTrend = 1.8;
  double _humidityTrend = 5.8;
  double _precipTrend = 0.8;
  double _windTrend = -0.9;
  final List<SoilWaterBalance> _soilWaterHistory = [];
  final List<ChatMessage> _chatHistory = [
    ChatMessage(
      id: 'seed_u_1',
      role: 'user',
      content: 'Should I delay irrigation on Field B after last night’s storm?',
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
    ),
    ChatMessage(
      id: 'seed_a_1',
      role: 'assistant',
      content:
          'Radar logged 0.35". Soil deficit now 18%. Delay the pivot run until Friday unless highs exceed 92°F or the wind stays above 15 mph.',
      timestamp: DateTime.now().subtract(const Duration(minutes: 9)),
    ),
  ];
  String _cityStateLabel = 'Locating…';
  final Map<String, String> _apiKeys = {
    'Metostat': dotenv.env['METOSTAT_API_KEY'] ?? '',
    'NASA POWER': dotenv.env['NASA_POWER_API_KEY'] ?? '',
    'AI': dotenv.env['GOOGLE_GEMINI_API_KEY'] ?? '',
  };
  final List<WeatherAlert> _weatherAlerts = [
    WeatherAlert(
      message: 'Moderate drought risk through Nov 25 • No frost threat next 14 days.',
      timestamp: DateTime.now(),
    ),
  ];
  GeminiService? _geminiClient;
  final Map<DiscussionScope, List<NetworkThread>> _customThreads = {
    for (final scope in DiscussionScope.values) scope: [],
  };
  String? _countyNameReal;
  String? _stateNameReal;
  String? _countryName;
  String? _regionLabel;
  int _locationVersion = 0;

  List<SoilHealthReading> get soilReadings => List.unmodifiable(_soilReadings);
  List<RegenerativeBlueprint> get blueprints => List.unmodifiable(_blueprints);
  List<ActivationTask> get upcomingActions => List.unmodifiable(_upcomingActions);
  List<MarketListing> get marketListings => List.unmodifiable(_marketListings);
  List<MappedField> get mappedFields => List.unmodifiable(_mappedFields);
  LatLng get mapAnchor => _mapAnchor;
  List<NetworkThread> get networkThreads => List.unmodifiable(_threads);
  Map<String, String> get apiKeys => Map.unmodifiable(_apiKeys);
  ThemeMode get themeMode => _themeMode;
  Units get units => _units;
  String get languageCode => _languageCode;
  bool get notificationsEnabled => _notificationsEnabled;
  String get notificationTime => _notificationTime;
  String? get satellitePreviewUrl => _satellitePreviewUrl;
  String get cityStateLabel => _cityStateLabel;
  String? get countyNameResolved => _countyNameReal;
  String? get stateNameResolved => _stateNameReal;
  String? get regionNameResolved => _regionLabel;
  int get locationVersion => _locationVersion;
  List<WeatherAlert> get weatherAlerts => List.unmodifiable(_weatherAlerts);
  WeatherSource get weatherSource => _weatherSource;
  bool get isWeatherLoading => _weatherLoading;
  String? get weatherError => _weatherError;
  List<ForecastDay> get forecast => List.unmodifiable(_forecast);
  List<DiscussionGroup> get discussionGroups => DiscussionScope.values.map(_buildDiscussionGroup).toList();
  void addDiscussionThread({
    required DiscussionScope scope,
    required String title,
    required String summary,
  }) {
    final trimmedTitle = title.trim();
    final trimmedSummary = summary.trim();
    if (trimmedTitle.isEmpty || trimmedSummary.isEmpty) return;
    final origin = _scopeOrigin(scope);
    final thread = NetworkThread(
      title: trimmedTitle,
      origin: origin,
      summary: trimmedSummary,
      replies: 0,
      recencyLabel: 'just now',
    );
    _customThreads[scope]!.insert(0, thread);
    notifyListeners();
  }
  List<ChatMessage> get chatHistory => List.unmodifiable(_chatHistory);
  double get regenRate => _regenRate;
  double get carbonOffset => _carbonOffset;
  double get impactScore => _impactScore;
  double get solarRadiation => _solarRadiation;
  double get temperatureF => _temperatureF;
  double get humidityPercent => _humidityPercent;
  double get precipForecastInches => _precipForecastInches;
  double get windSpeedMph => _windSpeedMph;
  double get solarTrend => _solarTrend;
  double get temperatureTrend => _temperatureTrend;
  double get humidityTrend => _humidityTrend;
  double get precipTrend => _precipTrend;
  double get windTrend => _windTrend;
  List<SoilWaterBalance> get soilWaterHistory => List.unmodifiable(_soilWaterHistory);
  void addWeatherAlert(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    _weatherAlerts.insert(
      0,
      WeatherAlert(
        message: trimmed,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void updateApiKey(String service, String value) {
    if (_apiKeys[service] == value.trim()) return;
    _apiKeys[service] = value.trim();
    if (service == 'Gemini') {
      _geminiClient = null;
    }
    notifyListeners();
  }


  void regeneratePulse() {
    final delta = _random.nextDouble() * 6 - 3;
    _impactScore = (_impactScore + delta).clamp(60, 98);
    _regenRate = (_regenRate + _random.nextDouble()).clamp(3, 9);
    _carbonOffset = (_carbonOffset + _random.nextDouble()).clamp(15, 32);

    _soilReadings.removeAt(0);
    _soilReadings.add(
      SoilHealthReading(
        date: DateTime(
          _soilReadings.last.date.year,
          _soilReadings.last.date.month + 1,
          _soilReadings.last.date.day,
        ),
        organicMatter: _soilReadings.last.organicMatter + _random.nextDouble() * 0.4,
        infiltration: _soilReadings.last.infiltration + _random.nextDouble() * 0.2,
      ),
    );
    notifyListeners();
  }

  void toggleBlueprintPin(RegenerativeBlueprint blueprint) {
    blueprint.isPinned = !blueprint.isPinned;
    notifyListeners();
  }

  void addMappedField({required String name, String? crop, required List<LatLng> boundary}) {
    if (boundary.length < 3) return;
    final color = _fieldPalette[_fieldColorCursor % _fieldPalette.length];
    _fieldColorCursor++;
    _mappedFields.add(
      MappedField(
        id: 'field_${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim().isEmpty ? 'Unnamed block' : name.trim(),
        crop: crop?.trim() ?? '',
        color: color,
        boundary: List.unmodifiable(boundary),
      ),
    );
    notifyListeners();
  }

  void updateFieldDetails(String fieldId, {String? name, String? crop}) {
    final index = _mappedFields.indexWhere((field) => field.id == fieldId);
    if (index == -1) return;
    final trimmedName = name?.trim();
    final trimmedCrop = crop?.trim();
    _mappedFields[index] = _mappedFields[index].copyWith(
      name: trimmedName != null && trimmedName.isNotEmpty ? trimmedName : null,
      crop: trimmedCrop ?? _mappedFields[index].crop,
    );
    notifyListeners();
  }

  Future<void> updateMapAnchor(LatLng anchor) async {
    _mapAnchor = anchor;
    updateClimateFromLocation(anchor, notify: false);
    notifyListeners();
    await updateCityLabel(anchor);
    await refreshWeather();
  }

  void updateClimateFromLocation(LatLng anchor, {bool notify = true}) {
    final lat = anchor.latitude;
    final lon = anchor.longitude;
    final noisy = (_random.nextDouble() - 0.5) * 0.5;
    _solarRadiation = (5 + (lat.abs() % 1.8) + noisy).clamp(4.0, 7.5);
    _temperatureF = (70 + (lat + lon) % 18 + noisy * 10).clamp(55, 102);
    _humidityPercent = (55 + (lat.abs() % 20) + noisy * 10).clamp(30, 95);
    _precipForecastInches = (0.05 * ((lon.abs() % 3) + _random.nextDouble())).clamp(0, 0.6);
    _windSpeedMph = (8 + (lon.abs() % 6) + noisy * 5).clamp(2, 25);

    _solarTrend = (_random.nextDouble() * 4) - 1.5;
    _temperatureTrend = (_random.nextDouble() * 3);
    _humidityTrend = (_random.nextDouble() * 6);
    _precipTrend = (_random.nextDouble() * 1.5);
    _windTrend = (_random.nextDouble() * 2) - 1.2;

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> updateCityLabel(LatLng anchor) async {
    try {
      if (!kIsWeb) {
        final placemarks = await geocoding.placemarkFromCoordinates(anchor.latitude, anchor.longitude);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          _assignLocationData(
            city: place.locality ?? place.subAdministrativeArea,
            county: place.subAdministrativeArea,
            state: place.administrativeArea,
            country: place.country,
          );
          return;
        }
      } else {
        final uri = Uri.https(
          'nominatim.openstreetmap.org',
          '/reverse',
          {
            'format': 'jsonv2',
            'lat': anchor.latitude.toString(),
            'lon': anchor.longitude.toString(),
          },
        );
        final response = await http.get(uri, headers: {'User-Agent': 'RisingRootsApp/1.0'});
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final address = data['address'] as Map<String, dynamic>? ?? {};
          _assignLocationData(
            city: address['city'] ?? address['town'] ?? address['village'] ?? address['hamlet'],
            county: address['county'],
            state: address['state'] ?? address['region'],
            country: address['country'],
          );
          return;
        }
      }
    } catch (error) {
      debugPrint('Unable to resolve city/state: $error');
    }
    final fallback = '${anchor.latitude.toStringAsFixed(2)}, ${anchor.longitude.toStringAsFixed(2)}';
    _assignLocationData(
      city: fallback,
      county: null,
      state: null,
      country: _countryName,
    );
  }


  Future<void> sendChatMessage(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;
    final userMessage = ChatMessage(
      id: _generateId(),
      role: 'user',
      content: trimmed,
      timestamp: DateTime.now(),
    );
    _chatHistory.add(userMessage);
    notifyListeners();

    ChatMessage response;
    try {
      final client = await _ensureGeminiClient();
      if (client != null) {
        response = await client.sendMessage(
          history: _chatHistory,
          prompt: trimmed,
          fieldId: _mappedFields.isNotEmpty ? _mappedFields.first.id : 'default-field',
        );
      } else {
        response = ChatMessage(
          id: _generateId(),
          role: 'assistant',
          content: _buildChatbotResponse(trimmed),
          timestamp: DateTime.now(),
        );
      }
    } catch (error) {
      response = ChatMessage(
        id: _generateId(),
        role: 'assistant',
        content: 'Gemini error: ${error.toString()}',
        timestamp: DateTime.now(),
      );
    }

    _chatHistory.add(response);
    notifyListeners();
  }

  String _buildChatbotResponse(String prompt) {
    final buffer = StringBuffer()
      ..writeln('Location: $countyName, $stateName • Soil deficit ${_regenRate.toStringAsFixed(1)}%.')
      ..writeln('Solar radiation ${_solarRadiation.toStringAsFixed(1)} kWh/m², temp ${_temperatureF.toStringAsFixed(0)}°F, RH ${_humidityPercent.toStringAsFixed(0)}%.')
      ..writeln('Precip forecast ${_precipForecastInches.toStringAsFixed(2)}" and wind ${_windSpeedMph.toStringAsFixed(1)} mph.');
    if (prompt.toLowerCase().contains('irrigation')) {
      buffer.writeln('Recommend waiting until deficit exceeds 35% or rain probability drops below 30%.');
    } else if (prompt.toLowerCase().contains('cover crop')) {
      buffer.writeln('Millet + cowpea + sunn hemp mix anchors sand, fixes N, and handles late-summer heat.');
    } else {
      buffer.writeln('Log sensor observations and I’ll adapt the schedule accordingly.');
    }
    return buffer.toString();
  }

  DiscussionGroup _buildDiscussionGroup(DiscussionScope scope) {
    final label = _scopeTitle(scope);
    final subtitle = _scopeSubtitle(scope);
    final base = _seedThreadsForScope(scope);
    final custom = _customThreads[scope]!;
    return DiscussionGroup(
      title: label,
      subtitle: subtitle,
      threads: [...custom, ...base],
    );
  }

  List<NetworkThread> _seedThreadsForScope(DiscussionScope scope) {
    final origin = _scopeOrigin(scope);
    switch (scope) {
      case DiscussionScope.county:
        return [
          NetworkThread(
            title: 'Cover crop mixes that survived last freeze?',
            origin: origin,
            summary: 'Share your blends and seeding rates for Macon County plots.',
            replies: 12,
            recencyLabel: '8m ago',
          ),
          NetworkThread(
            title: 'Irrigation timing after 0.3" rainfall',
            origin: origin,
            summary: 'How long did you delay pivots on sandy fields this week?',
            replies: 21,
            recencyLabel: '35m ago',
          ),
          NetworkThread(
            title: 'Best local supplier for drip tape repairs',
            origin: origin,
            summary: 'Looking for next‑day pickup near Tuskegee.',
            replies: 6,
            recencyLabel: '2h ago',
          ),
        ];
      case DiscussionScope.state:
        return [
          NetworkThread(
            title: 'Alabama corn earworm pressure 2025',
            origin: origin,
            summary: 'Scouting notes and thresholds across central AL.',
            replies: 33,
            recencyLabel: '1h ago',
          ),
          NetworkThread(
            title: 'Buying group for fuel and fertilizers',
            origin: origin,
            summary: 'Statewide cooperative pricing interest check.',
            replies: 18,
            recencyLabel: '3h ago',
          ),
          NetworkThread(
            title: 'Soil lab recommendations: Auburn vs private labs',
            origin: origin,
            summary: 'Turnaround time and accuracy feedback.',
            replies: 9,
            recencyLabel: '5h ago',
          ),
        ];
      case DiscussionScope.region:
        return [
          NetworkThread(
            title: 'Southeast drought outlook and forage plans',
            origin: origin,
            summary: 'Adjusting grazing and hay cutting schedules.',
            replies: 27,
            recencyLabel: '42m ago',
          ),
          NetworkThread(
            title: 'Cotton defoliation strategies in humid weeks',
            origin: origin,
            summary: 'Rates, timing, and weather windows.',
            replies: 11,
            recencyLabel: '2h ago',
          ),
          NetworkThread(
            title: 'Peanut disease triangle: what’s working this season?',
            origin: origin,
            summary: 'Fungicide rotations and varieties.',
            replies: 22,
            recencyLabel: '6h ago',
          ),
        ];
      case DiscussionScope.global:
        return [
          NetworkThread(
            title: 'Best practices for Sentinel‑2 cloud masking',
            origin: origin,
            summary: 'Share code snippets and QA tips for ag fields.',
            replies: 54,
            recencyLabel: '10m ago',
          ),
          NetworkThread(
            title: 'Open‑source tools for ET₀ and irrigation analytics',
            origin: origin,
            summary: 'Comparing FAO‑56 implementations and calibration methods.',
            replies: 39,
            recencyLabel: '1h ago',
          ),
          NetworkThread(
            title: 'Carbon programs: verification timelines worldwide',
            origin: origin,
            summary: 'Experiences from US/EU/AU producers.',
            replies: 25,
            recencyLabel: '4h ago',
          ),
        ];
    }
  }

  String get countyName {
    return _countyNameReal ?? 'Local county';
  }

  String get stateName {
    return _stateNameReal ?? 'Local state';
  }

  String get regionName {
    return _regionLabel ?? 'Regional corridor';
  }

  String _generateId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _assignLocationData({
    required String? city,
    required String? county,
    required String? state,
    required String? country,
  }) {
    final formatted = _formatCityState(city, state);
    final region = _deriveRegion(state, country);
    final changed = formatted != _cityStateLabel ||
        county != _countyNameReal ||
        state != _stateNameReal ||
        country != _countryName ||
        region != _regionLabel;
    _cityStateLabel = formatted.isNotEmpty ? formatted : _cityStateLabel;
    _countyNameReal = county ?? _countyNameReal;
    _stateNameReal = state ?? _stateNameReal;
    _countryName = country ?? _countryName;
    _regionLabel = region ?? _regionLabel;
    if (changed) {
      _locationVersion++;
      notifyListeners();
    }
  }

  String? _deriveRegion(String? state, String? country) {
    if (country == null) return null;
    if (country.toUpperCase() == 'UNITED STATES' || country.toUpperCase() == 'UNITED STATES OF AMERICA') {
      final code = _stateAbr(state);
      return _usRegionMap[code] ?? 'United States';
    }
    return country;
  }

  String? _stateAbr(String? state) {
    if (state == null) return null;
    final normalized = state.trim();
    if (normalized.length == 2) return normalized.toUpperCase();
    return _stateNameToCode[normalized] ?? normalized;
  }

  static const Map<String, String> _stateNameToCode = {
    'Alabama': 'AL',
    'Alaska': 'AK',
    'Arizona': 'AZ',
    'Arkansas': 'AR',
    'California': 'CA',
    'Colorado': 'CO',
    'Connecticut': 'CT',
    'Delaware': 'DE',
    'District of Columbia': 'DC',
    'Florida': 'FL',
    'Georgia': 'GA',
    'Hawaii': 'HI',
    'Idaho': 'ID',
    'Illinois': 'IL',
    'Indiana': 'IN',
    'Iowa': 'IA',
    'Kansas': 'KS',
    'Kentucky': 'KY',
    'Louisiana': 'LA',
    'Maine': 'ME',
    'Maryland': 'MD',
    'Massachusetts': 'MA',
    'Michigan': 'MI',
    'Minnesota': 'MN',
    'Mississippi': 'MS',
    'Missouri': 'MO',
    'Montana': 'MT',
    'Nebraska': 'NE',
    'Nevada': 'NV',
    'New Hampshire': 'NH',
    'New Jersey': 'NJ',
    'New Mexico': 'NM',
    'New York': 'NY',
    'North Carolina': 'NC',
    'North Dakota': 'ND',
    'Ohio': 'OH',
    'Oklahoma': 'OK',
    'Oregon': 'OR',
    'Pennsylvania': 'PA',
    'Rhode Island': 'RI',
    'South Carolina': 'SC',
    'South Dakota': 'SD',
    'Tennessee': 'TN',
    'Texas': 'TX',
    'Utah': 'UT',
    'Vermont': 'VT',
    'Virginia': 'VA',
    'Washington': 'WA',
    'West Virginia': 'WV',
    'Wisconsin': 'WI',
    'Wyoming': 'WY',
  };

  static const Map<String, String> _usRegionMap = {
    'CT': 'Northeast corridor',
    'ME': 'Northeast corridor',
    'MA': 'Northeast corridor',
    'NH': 'Northeast corridor',
    'RI': 'Northeast corridor',
    'VT': 'Northeast corridor',
    'NJ': 'Mid-Atlantic',
    'NY': 'Mid-Atlantic',
    'PA': 'Mid-Atlantic',
    'IL': 'Midwest',
    'IN': 'Midwest',
    'MI': 'Midwest',
    'OH': 'Midwest',
    'WI': 'Midwest',
    'IA': 'Upper Midwest',
    'KS': 'Upper Midwest',
    'MN': 'Upper Midwest',
    'MO': 'Upper Midwest',
    'NE': 'Upper Midwest',
    'ND': 'Upper Midwest',
    'SD': 'Upper Midwest',
    'DE': 'Mid-Atlantic',
    'DC': 'Mid-Atlantic',
    'AL': 'Southeast',
    'AR': 'Southeast',
    'FL': 'Southeast',
    'GA': 'Southeast',
    'KY': 'Southeast',
    'LA': 'Southeast',
    'MS': 'Southeast',
    'NC': 'Southeast',
    'SC': 'Southeast',
    'TN': 'Southeast',
    'VA': 'Southeast',
    'WV': 'Southeast',
    'AZ': 'Southwest',
    'CO': 'Mountain West',
    'ID': 'Mountain West',
    'MT': 'Mountain West',
    'NV': 'Mountain West',
    'NM': 'Southwest',
    'UT': 'Mountain West',
    'WY': 'Mountain West',
    'AK': 'Pacific & Alaska',
    'CA': 'Pacific & Alaska',
    'HI': 'Pacific & Alaska',
    'OR': 'Pacific Northwest',
    'WA': 'Pacific Northwest',
    'OK': 'South Plains',
    'TX': 'South Plains',
  };

  String _scopeTitle(DiscussionScope scope) {
    switch (scope) {
      case DiscussionScope.county:
        return '$countyName growers';
      case DiscussionScope.state:
        return '$stateName producers';
      case DiscussionScope.region:
        return '$regionName corridor';
      case DiscussionScope.global:
        return 'Global cooperative';
    }
  }

  String _scopeSubtitle(DiscussionScope scope) {
    switch (scope) {
      case DiscussionScope.county:
        return 'Neighbors collaborating within $countyName.';
      case DiscussionScope.state:
        return 'State-wide intelligence sharing for $stateName.';
      case DiscussionScope.region:
        return 'Regional conversations spanning $regionName.';
      case DiscussionScope.global:
        return 'Worldwide insights across the MeteoFlow network.';
    }
  }

  String _scopeOrigin(DiscussionScope scope) {
    switch (scope) {
      case DiscussionScope.county:
        return countyName;
      case DiscussionScope.state:
        return stateName;
      case DiscussionScope.region:
        return regionName;
      case DiscussionScope.global:
        return 'Global network';
    }
  }

  String _formatCityState(String? city, String? state) {
    final parts = <String>[];
    if (city != null && city.trim().isNotEmpty) {
      parts.add(city.trim());
    }
    if (state != null && state.trim().isNotEmpty) {
      parts.add(state.trim());
    }
    return parts.join(', ');
  }

  Future<GeminiService?> _ensureGeminiClient() async {
    if (_geminiClient != null) return _geminiClient;
    final apiKey = _apiKeys['Gemini'];
    if (apiKey == null || apiKey.isEmpty) {
      return null;
    }
    try {
      _geminiClient = GoogleGeminiService(apiKey: apiKey);
    } catch (error) {
      debugPrint('Gemini init failed: $error');
      return null;
    }
    return _geminiClient;
  }

  Future<void> syncUserProfile() async {
    await _loadPreferences();
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> preloadFieldData() async {
    await Future.delayed(const Duration(milliseconds: 320));
    notifyListeners();
  }

  Future<void> primeWeatherModels() async {
    updateClimateFromLocation(_mapAnchor, notify: false);
    await Future.delayed(const Duration(milliseconds: 360));
    notifyListeners();
  }

  Future<void> setWeatherSource(WeatherSource source) async {
    if (_weatherSource == source) return;
    _weatherSource = source;
    await refreshWeather();
  }

  Future<void> refreshWeather() async {
    _weatherLoading = true;
    _weatherError = null;
    notifyListeners();
    try {
      switch (_weatherSource) {
        case WeatherSource.nasaPower:
          _forecast = await _loadFromNasaPower(_mapAnchor);
          break;
        case WeatherSource.metostat:
          _forecast = await _loadFromMetostat(_mapAnchor);
          break;
      }
      _applyForecastToCurrentClimate();
    } catch (error) {
      _weatherError = error.toString();
    } finally {
      _weatherLoading = false;
      notifyListeners();
    }
  }

  static double kcFor(CropType crop, GrowthStage stage) {
    // Representative FAO-56 Kc values for common crops and stages.
    switch (crop) {
      case CropType.corn:
        switch (stage) {
          case GrowthStage.initial:
            return 0.45;
          case GrowthStage.mid:
            return 1.20;
          case GrowthStage.late:
            return 0.60;
        }
      case CropType.soybean:
        switch (stage) {
          case GrowthStage.initial:
            return 0.40;
          case GrowthStage.mid:
            return 1.15;
          case GrowthStage.late:
            return 0.55;
        }
      case CropType.cotton:
        switch (stage) {
          case GrowthStage.initial:
            return 0.35;
          case GrowthStage.mid:
            return 1.15;
          case GrowthStage.late:
            return 0.60;
        }
    }
  }

  void recordSoilWaterBalance({
    required DateTime date,
    required CropType crop,
    required GrowthStage stage,
    required double et0Mm,
    required double etcMm,
    required double rainfallMm,
    required double irrigationMm,
  }) {
    final netMm = (etcMm - rainfallMm - irrigationMm).clamp(0.0, double.infinity);
    final netIn = netMm / 25.4;
    _soilWaterHistory.add(
      SoilWaterBalance(
        date: date,
        deficitPercent: 0,
        deficitInches: netIn,
        cropStage: '${crop.label} • ${stage.label}',
        recommendedIrrigationInches: netIn,
      ),
    );
    notifyListeners();
  }

  void _applyForecastToCurrentClimate() {
    if (_forecast.isEmpty) return;
    final today = _forecast.first;
    _temperatureF = (today.maxTempC * 9 / 5 + 32);
    _humidityPercent = today.humidity.clamp(0, 100);
    _precipForecastInches = (today.rainMm / 25.4).clamp(0, 10);
    _windSpeedMph = (today.windSpeedMs * 2.23694).clamp(0, 120);
    _solarRadiation = (today.solarRadiation * 0.277777).clamp(0, 10); // MJ/m²/day ≈ kWh/m²/day
  }

  Future<List<ForecastDay>> _loadFromNasaPower(LatLng anchor) async {
    // Use the last 7 fully completed UTC days to avoid partial-day/off-by-one shifts.
    final utcToday = DateTime.now().toUtc();
    final end = DateTime.utc(utcToday.year, utcToday.month, utcToday.day).subtract(const Duration(days: 1));
    final start = end.subtract(const Duration(days: 6));
    final params = [
      'T2M_MIN',
      'T2M_MAX',
      'RH2M',
      'WS2M',
      'PRECTOTCORR',
      'ALLSKY_SFC_SW_DWN',
    ].join(',');
    final query = {
      'start': DateFormat('yyyyMMdd').format(start),
      'end': DateFormat('yyyyMMdd').format(end),
      'latitude': anchor.latitude.toString(),
      'longitude': anchor.longitude.toString(),
      'community': 'ag',
      'parameters': params,
      'format': 'json',
      'user': 'risingroots',
    };
    final uri = Uri.https('power.larc.nasa.gov', '/api/temporal/daily/point', query);
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw StateError('NASA POWER error ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final props = (data['properties'] as Map<String, dynamic>? ?? {});
    final parameter = (props['parameter'] as Map<String, dynamic>? ?? {});
    List<ForecastDay> days = [];
    for (int i = 0; i < 7; i++) {
      final d = DateTime(start.year, start.month, start.day).add(Duration(days: i));
      final key = DateFormat('yyyyMMdd').format(d);
      final minC = _sanitizePower(_readNum(parameter['T2M_MIN'], key));
      final maxC = _sanitizePower(_readNum(parameter['T2M_MAX'], key));
      final rh = _sanitizePower(_readNum(parameter['RH2M'], key));
      final ws = _sanitizePower(_readNum(parameter['WS2M'], key));
      final rain = _sanitizePower(_readNum(parameter['PRECTOTCORR'], key));
      final sol = _sanitizePower(_readNum(parameter['ALLSKY_SFC_SW_DWN'], key));
      if (minC == null || maxC == null) continue;
      days.add(ForecastDay(
        date: d,
        minTempC: minC,
        maxTempC: maxC,
        humidity: (rh ?? 60).toDouble(),
        windSpeedMs: (ws ?? 0).toDouble(),
        rainMm: (rain ?? 0).toDouble(),
        solarRadiation: (sol ?? 0).toDouble(),
      ));
    }
    return days;
  }

  Future<List<ForecastDay>> _loadFromMetostat(LatLng anchor) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final end = DateTime(now.year, now.month, now.day);
    final key = _apiKeys['Metostat'] ?? '';
    final uri = Uri.https('api.meteostat.net', '/v2/point/daily', {
      'lat': anchor.latitude.toString(),
      'lon': anchor.longitude.toString(),
      'start': DateFormat('yyyy-MM-dd').format(start),
      'end': DateFormat('yyyy-MM-dd').format(end),
    });
    final headers = <String, String>{};
    if (key.isNotEmpty) headers['x-api-key'] = key;
    final resp = await http.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw StateError('Metostat error ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (body['data'] as List<dynamic>? ?? []);
    final days = <ForecastDay>[];
    for (final item in list) {
      final m = (item as Map<String, dynamic>);
      final dateStr = m['date'] as String;
      final d = DateTime.parse(dateStr);
      final tmin = _asDouble(m['tmin']);
      final tmax = _asDouble(m['tmax']);
      final pr = _asDouble(m['prcp']); // mm
      final wspdKmh = _asDouble(m['wspd']); // km/h
      final rh = _asDouble(m['rhum']); // sometimes null
      final sunSec = _asDouble(m['tsun']); // seconds sunshine, may be null
      if (tmin == null || tmax == null) continue;
      final windMs = (wspdKmh ?? 0) / 3.6;
      // Approximate solar radiation from sunshine duration (very rough)
      final solarMj = (sunSec ?? 0) * 0.0036 / 3600.0;
      days.add(ForecastDay(
        date: d,
        minTempC: tmin,
        maxTempC: tmax,
        humidity: (rh ?? 60).toDouble(),
        windSpeedMs: windMs,
        rainMm: (pr ?? 0).toDouble(),
        solarRadiation: solarMj,
      ));
    }
    return days;
  }

  static double? _readNum(dynamic map, String key) {
    if (map is Map<String, dynamic>) {
      final v = map[key];
      return _asDouble(v);
    }
    return null;
  }

  // NASA POWER uses sentinel values like -999, -9999 for missing data.
  static double? _sanitizePower(double? value) {
    if (value == null) return null;
    if (value <= -990) return null;
    return value;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  Future<void> hydrateChatbotMemory() async {
    await Future.delayed(const Duration(milliseconds: 260));
  }

  Future<void> prefetchCommunityThreads() async {
    await Future.delayed(const Duration(milliseconds: 280));
  }
}

enum Units { metric, imperial }

extension UnitsLabel on Units {
  String get label => this == Units.metric ? 'Metric' : 'Imperial';
}

extension Preferences on RegenerativeState {
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _themeMode = ThemeMode.values[prefs.getInt('pref_themeMode') ?? ThemeMode.light.index];
      _units = Units.values[prefs.getInt('pref_units') ?? Units.imperial.index];
      _languageCode = prefs.getString('pref_language') ?? 'en';
      _notificationsEnabled = prefs.getBool('pref_notifications') ?? true;
      _notificationTime = prefs.getString('pref_notification_time') ?? '07:00';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pref_themeMode', _themeMode.index);
      await prefs.setInt('pref_units', _units.index);
      await prefs.setString('pref_language', _languageCode);
      await prefs.setBool('pref_notifications', _notificationsEnabled);
      await prefs.setString('pref_notification_time', _notificationTime);
      if (_satellitePreviewUrl != null) {
        await prefs.setString('pref_sat_preview', _satellitePreviewUrl!);
      }
    } catch (_) {}
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _savePreferences();
    notifyListeners();
  }

  void setSatellitePreviewUrl(String url) {
    _satellitePreviewUrl = url.trim().isEmpty ? null : url.trim();
    _savePreferences();
    notifyListeners();
  }

  void setUnits(Units u) {
    if (_units == u) return;
    _units = u;
    _savePreferences();
    notifyListeners();
  }

  void setLanguage(String code) {
    if (_languageCode == code) return;
    _languageCode = code;
    _savePreferences();
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    _savePreferences();
    notifyListeners();
  }

  void setNotificationTime(String hhmm) {
    _notificationTime = hhmm;
    _savePreferences();
    notifyListeners();
  }

  // Formatting helpers respecting units
  String formatTemperature(double f) {
    if (_units == Units.metric) {
      final c = (f - 32) * 5 / 9;
      return '${c.toStringAsFixed(0)}°C';
    }
    return '${f.toStringAsFixed(0)}°F';
  }

  String formatPrecip(double inches) {
    if (_units == Units.metric) {
      final mm = inches * 25.4;
      return '${mm.toStringAsFixed(1)} mm';
    }
    return '${inches.toStringAsFixed(2)} in';
  }

  String formatWind(double mph) {
    if (_units == Units.metric) {
      final kmh = mph * 1.60934;
      return '${kmh.toStringAsFixed(1)} km/h';
    }
    return '${mph.toStringAsFixed(1)} mph';
  }
}
class SoilHealthReading {
  SoilHealthReading({
    required this.date,
    required this.organicMatter,
    required this.infiltration,
  });

  final DateTime date;
  final double organicMatter;
  final double infiltration;
}

class RegenerativeBlueprint {
  RegenerativeBlueprint({
    required this.name,
    required this.biome,
    required this.description,
    required this.focus,
    required this.duration,
    required this.carbonScore,
    this.isPinned = false,
  });

  final String name;
  final String biome;
  final String description;
  final List<String> focus;
  final int duration;
  final int carbonScore;
  bool isPinned;
}

class ActivationTask {
  ActivationTask({
    required this.title,
    required this.location,
    required this.owner,
    required this.icon,
    required this.when,
  });

  final String title;
  final String location;
  final String owner;
  final IconData icon;
  final DateTime when;
}

class MarketListing {
  MarketListing({
    required this.title,
    required this.description,
    required this.creditLabel,
    required this.delivery,
    required this.icon,
  });

  final String title;
  final String description;
  final String creditLabel;
  final String delivery;
  final IconData icon;
}

class NetworkThread {
  NetworkThread({
    required this.title,
    required this.origin,
    required this.summary,
    required this.replies,
    required this.recencyLabel,
  });

  final String title;
  final String origin;
  final String summary;
  final int replies;
  final String recencyLabel;
}

class MappedField {
  const MappedField({
    required this.id,
    required this.name,
    required this.crop,
    required this.boundary,
    required this.color,
  });

  final String id;
  final String name;
  final String crop;
  final List<LatLng> boundary;
  final Color color;

  double get areaAcres => _computeArea(boundary) / 4046.8564224;

  String get areaLabel {
    if (areaAcres == 0) return '—';
    return '${areaAcres.toStringAsFixed(1)} ac';
  }

  MappedField copyWith({
    String? name,
    String? crop,
    List<LatLng>? boundary,
    Color? color,
  }) {
    return MappedField(
      id: id,
      name: name ?? this.name,
      crop: crop ?? this.crop,
      boundary: boundary ?? this.boundary,
      color: color ?? this.color,
    );
  }

  static double _computeArea(List<LatLng> coords) {
    if (coords.length < 3) return 0;
    const double earthRadius = 6378137; // meters
    final double originLat = coords.first.latitude * pi / 180;
    final double originLon = coords.first.longitude * pi / 180;

    final points = coords
        .map(
          (coord) => Point<double>(
            (coord.longitude * pi / 180 - originLon) * cos(originLat) * earthRadius,
            (coord.latitude * pi / 180 - originLat) * earthRadius,
          ),
        )
        .toList();

    double sum = 0;
    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      sum += current.x * next.y - next.x * current.y;
    }
    return sum.abs() / 2;
  }
}

class DiscussionGroup {
  const DiscussionGroup({
    required this.title,
    required this.subtitle,
    required this.threads,
  });

  final String title;
  final String subtitle;
  final List<NetworkThread> threads;
}


