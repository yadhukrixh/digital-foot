
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const ScrollTrekApp());
}

class ScrollTrekApp extends StatelessWidget {
  const ScrollTrekApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Scroll Trek',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101410),
        useMaterial3: true,
      ),
      home: const ScrollDashboard(),
    );
  }
}

class ScrollDashboard extends StatefulWidget {
  const ScrollDashboard({super.key});

  @override
  State<ScrollDashboard> createState() => _ScrollDashboardState();
}

class _ScrollDashboardState extends State<ScrollDashboard>
    with WidgetsBindingObserver {
  static const MethodChannel channel =
      MethodChannel('scroll_trek/measurements');

  int totalAbsDeltaY = 0;
  int totalAbsDeltaX = 0;
  int latestDeltaY = 0;
  int validEvents = 0;
  int zeroEvents = 0;
  int unmeasurableEvents = 0;

  double estimatedDistanceMeters = 0.0;

  String activeApp = 'Waiting for scroll events';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    channel.setMethodCallHandler(_handleNativeCall);

    loadSavedStats();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'scrollUpdate') return;

    final data = Map<String, dynamic>.from(
      call.arguments as Map,
    );

    if (!mounted) return;

    setState(() {
      activeApp =
          data['sourcePackage']?.toString() ?? activeApp;

      latestDeltaY =
          (data['deltaY'] as num?)?.toInt() ?? 0;

      totalAbsDeltaY =
          (data['totalAbsDeltaY'] as num?)?.toInt() ??
              totalAbsDeltaY;

      totalAbsDeltaX =
          (data['totalAbsDeltaX'] as num?)?.toInt() ??
              totalAbsDeltaX;

      validEvents =
          (data['validEvents'] as num?)?.toInt() ??
              validEvents;

      zeroEvents =
          (data['zeroEvents'] as num?)?.toInt() ??
              zeroEvents;

      unmeasurableEvents =
          (data['unmeasurableEvents'] as num?)?.toInt() ??
              unmeasurableEvents;

      estimatedDistanceMeters =
          (data['estimatedDistanceMeters'] as num?)
                  ?.toDouble() ??
              estimatedDistanceMeters;

      isLoading = false;
    });
  }

  Future<void> loadSavedStats() async {
    try {
      final result =
          await channel.invokeMapMethod<String, dynamic>(
        'getStats',
      );

      if (!mounted) return;

      // The native service returns one device-wide statistics object.
      final rawStats = result?['device'];

      if (rawStats is! Map) {
        setState(() => isLoading = false);
        return;
      }

      final stats = Map<String, dynamic>.from(rawStats);

      setState(() {
        totalAbsDeltaY =
            (stats['totalAbsDeltaY'] as num?)?.toInt() ?? 0;

        totalAbsDeltaX =
            (stats['totalAbsDeltaX'] as num?)?.toInt() ?? 0;

        validEvents =
            (stats['validEvents'] as num?)?.toInt() ?? 0;

        zeroEvents =
            (stats['zeroEvents'] as num?)?.toInt() ?? 0;

        unmeasurableEvents =
            (stats['unmeasurableEvents'] as num?)?.toInt() ?? 0;

        estimatedDistanceMeters =
            (stats['estimatedDistanceMeters'] as num?)
                    ?.toDouble() ??
                0.0;

        isLoading = false;
      });
    } on PlatformException catch (e) {
      debugPrint('Failed to load saved stats: ${e.message}');

      if (mounted) {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Unexpected error loading stats: $e');

      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadSavedStats();
    }
  }

  String formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }

    return '${meters.toStringAsFixed(2)} m';
  }

  Widget metricCard(
    String title,
    String value,
    String subtitle, {
    IconData? icon,
  }) {
    return Card(
      color: const Color(0xFF1B211C),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.greenAccent),
              const SizedBox(height: 12),
            ],
            Text(
              title,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scroll Trek'),
        backgroundColor: const Color(0xFF101410),
        actions: [
          IconButton(
            tooltip: 'Refresh saved measurements',
            onPressed: loadSavedStats,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF1B211C),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DEVICE-WIDE SCROLL TRACKER',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      letterSpacing: 1.2,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isLoading
                        ? 'Loading measurements…'
                        : '$totalAbsDeltaY px',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Total accumulated vertical scroll movement',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(
                        Icons.route,
                        color: Colors.greenAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatDistance(estimatedDistanceMeters),
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'Estimated screen-scale equivalent',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Totals are shared across apps and restored '
                    'from saved native statistics.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: metricCard(
                  'Measured events',
                  '$validEvents',
                  'Events with usable movement',
                  icon: Icons.show_chart,
                ),
              ),
              Expanded(
                child: metricCard(
                  'Unmeasurable',
                  '$unmeasurableEvents',
                  'Events without usable vertical data',
                  icon: Icons.help_outline,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: metricCard(
                  'Zero movement',
                  '$zeroEvents',
                  'Events with no measured movement',
                  icon: Icons.horizontal_rule,
                ),
              ),
              Expanded(
                child: metricCard(
                  'Horizontal delta',
                  '$totalAbsDeltaX px',
                  'Accumulated horizontal movement',
                  icon: Icons.swap_horiz,
                ),
              ),
            ],
          ),
          Card(
            color: const Color(0xFF1B211C),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LATEST ACTIVITY',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      letterSpacing: 1,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activeApp,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Latest vertical delta: $latestDeltaY px',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            color: Color(0xFF1B211C),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Important: Scroll Trek can count only movement '
                'that Android exposes and the accessibility service '
                'can measure. The meter value is an estimate based '
                'on display density, not a verified physical distance. '
                'Some apps or screens may not expose usable scroll '
                'data, so the total may not include every scroll.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
