
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

class TrekPrediction {
  final String destination;
  final String country;
  final double trailDistanceKm;
  final double estimatedHours;
  final String message;

  const TrekPrediction({
    required this.destination,
    required this.country,
    required this.trailDistanceKm,
    required this.estimatedHours,
    required this.message,
  });
}

class TrekPredictionService {
  TrekPredictionService({
    this.pixelsPerVirtualKm = 100000,
    this.windowDuration = const Duration(hours: 2),
    this.minimumObservationDuration = const Duration(minutes: 5),
    this.minimumActiveDuration = const Duration(seconds: 30),
    this.cooldown = const Duration(minutes: 15),
    this.minimumVirtualKm = 0.05,
    this.minimumSamples = 5,
    this.maxEstimatedHours = 24 * 365,
  }) : _random = Random();

  /// Game scale only; this is not a physical distance conversion.
  final double pixelsPerVirtualKm;

  /// How far back to consider scroll activity.
  final Duration windowDuration;

  /// Require a reasonable observation window before predicting.
  final Duration minimumObservationDuration;

  /// Require at least this much time between the first and last
  /// scrolling samples that contribute to the prediction.
  final Duration minimumActiveDuration;

  /// Base delay between popups. A random multiplier is applied.
  final Duration cooldown;

  final double minimumVirtualKm;
  final int minimumSamples;
  final double maxEstimatedHours;

  final Random _random;
  final List<_ScrollSample> _samples = [];
  final List<String> _recentDestinationIds = [];

  static const int _maxRecentDestinations = 12;

  List<Map<String, dynamic>> _destinations = [];
  DateTime? _lastPopupAt;
  Duration _nextCooldown = Duration.zero;
  bool _isLoaded = false;

  static const _messages = [
    'Your thumb is training for the Olympics! Keep this pace and you could conquer {trail} in {time}.',
    'Forget hiking boots. Your scrolling thumb is ready for {trail} in {time}!',
    'Plot twist: all this scrolling could take you to {trail} in {time}. Touch grass afterwards!',
    'Mountain goat energy detected! {trail} could be yours in {time}.',
    'Your thumb deserves a summit selfie. {trail} is about {time} away at this pace!',
    'Who needs a treadmill? Your thumb is virtually trekking to {trail} in {time}!',
    'Breaking news: local thumb attempts legendary trek. Estimated time to {trail}: {time}!',
    'Keep swiping, future mountaineer! {trail} could be your next virtual adventure in {time}.',
    'A little scroll today, a mountain-sized ego tomorrow. {trail} in {time}!',
    'Sherpa status loading... Your thumb has its sights set on {trail} in {time}!',
    'Your screen time has entered its adventure era. Next stop: {trail}, in {time}!',
    'One does not simply stop scrolling. At this pace, {trail} awaits in {time}!',
    'Your thumb called. It wants a summit medal for reaching {trail} in {time}!',
    'Nature is calling. Your thumb has put it on hold and picked {trail} in {time}!',
  ];

  /// Loads and validates assets/distances.json.
  Future<void> loadDestinations() async {
    final jsonString =
        await rootBundle.loadString('assets/distances.json');

    final decoded = jsonDecode(jsonString);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'distances.json must contain a JSON object.',
      );
    }

    final rawDestinations = decoded['destinations'];

    if (rawDestinations is! List) {
      throw const FormatException(
        'distances.json must contain a destinations array.',
      );
    }

    final validDestinations = <Map<String, dynamic>>[];

    for (final item in rawDestinations) {
      if (item is! Map) continue;

      final destination = Map<String, dynamic>.from(item);
      final name = destination['name'];
      final distance = destination['trailDistanceKm'];

      if (name is! String ||
          name.trim().isEmpty ||
          distance is! num ||
          !distance.toDouble().isFinite ||
          distance <= 0) {
        continue;
      }

      validDestinations.add(destination);
    }

    if (validDestinations.isEmpty) {
      throw StateError(
        'No valid destinations found in assets/distances.json.',
      );
    }

    _destinations = validDestinations;
    _isLoaded = true;
  }

  /// Call with the absolute vertical scroll delta in pixels.
  ///
  /// Returns null until sufficient activity has been collected,
  /// or when the popup cooldown is active.
  TrekPrediction? addScroll({
    required double deltaPixels,
    DateTime? timestamp,
  }) {
    if (!_isLoaded ||
        !deltaPixels.isFinite ||
        deltaPixels <= 0 ||
        pixelsPerVirtualKm <= 0) {
      return null;
    }

    final now = timestamp ?? DateTime.now();

    // Ignore out-of-order events rather than corrupting the window.
    if (_samples.isNotEmpty &&
        now.isBefore(_samples.last.timestamp)) {
      return null;
    }

    _samples.add(
      _ScrollSample(timestamp: now, pixels: deltaPixels),
    );

    final cutoff = now.subtract(windowDuration);
    _samples.removeWhere(
      (sample) => sample.timestamp.isBefore(cutoff),
    );

    if (_samples.length < minimumSamples) return null;

    final firstTime = _samples.first.timestamp;
    final lastTime = _samples.last.timestamp;
    final observationDuration = lastTime.difference(firstTime);

    if (observationDuration < minimumObservationDuration) {
      return null;
    }

    // Estimate active time from the gaps between scroll events.
    // Long idle gaps do not count as active scrolling.
    final activeDuration = _calculateActiveDuration();

    if (activeDuration < minimumActiveDuration) return null;

    final totalPixels = _samples.fold<double>(
      0,
      (total, sample) => total + sample.pixels,
    );

    final virtualKm = totalPixels / pixelsPerVirtualKm;

    if (virtualKm < minimumVirtualKm) return null;

    final activeHours =
        activeDuration.inMilliseconds /
        Duration.millisecondsPerHour;

    if (activeHours <= 0) return null;

    final virtualKmPerHour = virtualKm / activeHours;

    if (!virtualKmPerHour.isFinite || virtualKmPerHour <= 0) {
      return null;
    }

    if (_lastPopupAt != null &&
        now.difference(_lastPopupAt!) < _nextCooldown) {
      return null;
    }

    final destination = _pickDestination();
    final trailKm =
        (destination['trailDistanceKm'] as num).toDouble();

    final estimatedHours = trailKm / virtualKmPerHour;

    if (!estimatedHours.isFinite ||
        estimatedHours <= 0 ||
        estimatedHours > maxEstimatedHours) {
      // Don't display wildly unrealistic predictions.
      return null;
    }

    _lastPopupAt = now;

    // Randomize the time until the next popup.
    final multiplier = 0.7 + _random.nextDouble() * 1.3;
    _nextCooldown = Duration(
      milliseconds: (cooldown.inMilliseconds * multiplier).round(),
    );

    final template =
        _messages[_random.nextInt(_messages.length)];
    final name = destination['name'] as String;

    return TrekPrediction(
      destination: name,
      country: destination['country'] is String
          ? destination['country'] as String
          : '',
      trailDistanceKm: trailKm,
      estimatedHours: estimatedHours,
      message: template
          .replaceAll('{trail}', name)
          .replaceAll('{time}', _formatDuration(estimatedHours)),
    );
  }

  Duration _calculateActiveDuration() {
    if (_samples.length < 2) return Duration.zero;

    var activeMilliseconds = 0;

    for (var i = 1; i < _samples.length; i++) {
      final gap = _samples[i]
          .timestamp
          .difference(_samples[i - 1].timestamp);

      // Count short gaps between events as active time.
      // Do not count long pauses as continuous activity.
      const maximumActiveGap = Duration(seconds: 10);

      if (gap > Duration.zero && gap <= maximumActiveGap) {
        activeMilliseconds += gap.inMilliseconds;
      }
    }

    return Duration(milliseconds: activeMilliseconds);
  }

  Map<String, dynamic> _pickDestination() {
    final available = _destinations.where((destination) {
      final id = _destinationId(destination);
      return !_recentDestinationIds.contains(id);
    }).toList();

    final candidates =
        available.isNotEmpty ? available : _destinations;

    final selected = candidates[_random.nextInt(candidates.length)];
    final id = _destinationId(selected);

    _recentDestinationIds.remove(id);
    _recentDestinationIds.add(id);

    while (_recentDestinationIds.length > _maxRecentDestinations) {
      _recentDestinationIds.removeAt(0);
    }

    return selected;
  }

  String _destinationId(Map<String, dynamic> destination) {
    final id = destination['id'];

    if (id is String && id.isNotEmpty) return id;

    return destination['name'].toString();
  }

  String _formatDuration(double hours) {
    if (!hours.isFinite || hours < 0) return 'a while';

    final totalHours = hours.ceil();

    if (totalHours < 24) {
      return '$totalHours ${totalHours == 1 ? 'hour' : 'hours'}';
    }

    final days = (totalHours / 24).ceil();

    if (days < 30) {
      return '$days ${days == 1 ? 'day' : 'days'}';
    }

    final months = (days / 30).ceil();

    if (months < 12) {
      return '$months ${months == 1 ? 'month' : 'months'}';
    }

    final years = (months / 12).ceil();
    return '$years ${years == 1 ? 'year' : 'years'}';
  }
}

class _ScrollSample {
  final DateTime timestamp;
  final double pixels;

  const _ScrollSample({
    required this.timestamp,
    required this.pixels,
  });
}
