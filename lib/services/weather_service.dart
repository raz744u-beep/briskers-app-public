import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection_mode.dart';
import 'briskers_api.dart';

typedef BriskersBusinessSettingsLoader =
    Future<Map<String, dynamic>> Function(String businessId);
typedef BriskersWeatherJsonLoader =
    Future<Map<String, dynamic>> Function(Uri uri);

class BriskersWeatherSnapshot {
  const BriskersWeatherSnapshot({
    required this.temperatureF,
    required this.apparentTemperatureF,
    required this.weatherCode,
    required this.condition,
    required this.iconKey,
    required this.message,
    required this.locationLabel,
    required this.fetchedAt,
  });

  final num temperatureF;
  final num apparentTemperatureF;
  final int weatherCode;
  final String condition;
  final String iconKey;
  final String message;
  final String locationLabel;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
        'temperature_f': temperatureF,
        'apparent_temperature_f': apparentTemperatureF,
        'weather_code': weatherCode,
        'condition': condition,
        'icon_key': iconKey,
        'message': message,
        'location_label': locationLabel,
        'fetched_at': fetchedAt.toUtc().toIso8601String(),
      };

  static BriskersWeatherSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final temperature =
        num.tryParse(map['temperature_f']?.toString() ?? '');
    final apparent =
        num.tryParse(map['apparent_temperature_f']?.toString() ?? '');
    final code = int.tryParse(map['weather_code']?.toString() ?? '');
    final fetchedAt =
        DateTime.tryParse(map['fetched_at']?.toString() ?? '');
    if (temperature == null ||
        apparent == null ||
        code == null ||
        fetchedAt == null) {
      return null;
    }
    return BriskersWeatherSnapshot(
      temperatureF: temperature,
      apparentTemperatureF: apparent,
      weatherCode: code,
      condition: map['condition']?.toString() ?? 'Weather',
      iconKey: map['icon_key']?.toString() ?? 'cloud',
      message: map['message']?.toString() ?? '',
      locationLabel: map['location_label']?.toString() ?? '',
      fetchedAt: fetchedAt.toUtc(),
    );
  }
}

class BriskersWeatherService {
  BriskersWeatherService({
    BriskersBusinessSettingsLoader? businessSettingsLoader,
    BriskersWeatherJsonLoader? jsonLoader,
    bool Function()? forceOffline,
  })  : _businessSettingsLoader =
            businessSettingsLoader ?? const BriskersApi().businessSettings,
        _jsonLoader = jsonLoader ?? _httpJson,
        _forceOffline = forceOffline ??
            (() => BriskersConnectionModeController.instance.forceOffline);

  static const Duration cacheLifetime = Duration(minutes: 30);

  final BriskersBusinessSettingsLoader _businessSettingsLoader;
  final BriskersWeatherJsonLoader _jsonLoader;
  final bool Function() _forceOffline;

  String _cacheKey(String businessId) =>
      'briskers_home_weather_$businessId';

  Future<BriskersWeatherSnapshot?> loadCached(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(businessId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return BriskersWeatherSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(
    String businessId,
    BriskersWeatherSnapshot snapshot,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey(businessId),
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<BriskersWeatherSnapshot?> load(
    String businessId, {
    bool forceRefresh = false,
  }) async {
    final cached = await loadCached(businessId);
    if (_forceOffline()) return cached;

    if (!forceRefresh &&
        cached != null &&
        DateTime.now().toUtc().difference(cached.fetchedAt) <
            cacheLifetime) {
      return cached;
    }

    try {
      final settings = await _businessSettingsLoader(businessId);
      var latitude =
          num.tryParse(settings['latitude']?.toString() ?? '');
      var longitude =
          num.tryParse(settings['longitude']?.toString() ?? '');
      final address = _addressText(settings['address']);
      var locationLabel = _locationLabel(address);

      if (latitude == null || longitude == null) {
        final query = _geocodeQuery(address);
        if (query.isEmpty) return cached;
        final geocode = await _jsonLoader(
          Uri.https(
            'geocoding-api.open-meteo.com',
            '/v1/search',
            {
              'name': query,
              'count': '1',
              'language': 'en',
              'format': 'json',
              'countryCode': 'US',
            },
          ),
        );
        final results = geocode['results'];
        if (results is! List || results.isEmpty || results.first is! Map) {
          return cached;
        }
        final first = Map<String, dynamic>.from(results.first as Map);
        latitude = num.tryParse(first['latitude']?.toString() ?? '');
        longitude = num.tryParse(first['longitude']?.toString() ?? '');
        final city = first['name']?.toString().trim() ?? '';
        final state = first['admin1']?.toString().trim() ?? '';
        locationLabel = <String>[
          if (city.isNotEmpty) city,
          if (state.isNotEmpty) state,
        ].join(', ');
      }

      if (latitude == null || longitude == null) return cached;

      final forecast = await _jsonLoader(
        Uri.https(
          'api.open-meteo.com',
          '/v1/forecast',
          {
            'latitude': latitude.toString(),
            'longitude': longitude.toString(),
            'current':
                'temperature_2m,apparent_temperature,precipitation,rain,weather_code,wind_speed_10m',
            'temperature_unit': 'fahrenheit',
            'wind_speed_unit': 'mph',
            'precipitation_unit': 'inch',
            'timezone': 'auto',
            'forecast_days': '1',
          },
        ),
      );

      final currentRaw = forecast['current'];
      if (currentRaw is! Map) return cached;
      final current = Map<String, dynamic>.from(currentRaw);
      final temperature =
          num.tryParse(current['temperature_2m']?.toString() ?? '');
      final apparent =
          num.tryParse(current['apparent_temperature']?.toString() ?? '');
      final precipitation =
          num.tryParse(current['precipitation']?.toString() ?? '') ?? 0;
      final rain = num.tryParse(current['rain']?.toString() ?? '') ?? 0;
      final code = int.tryParse(current['weather_code']?.toString() ?? '');

      if (temperature == null || code == null) return cached;
      final condition = conditionForCode(code);
      final snapshot = BriskersWeatherSnapshot(
        temperatureF: temperature,
        apparentTemperatureF: apparent ?? temperature,
        weatherCode: code,
        condition: condition.$1,
        iconKey: condition.$2,
        message: messageForWeather(
          code,
          precipitation: precipitation,
          rain: rain,
        ),
        locationLabel: locationLabel,
        fetchedAt: DateTime.now().toUtc(),
      );
      await _save(businessId, snapshot);
      return snapshot;
    } catch (_) {
      return cached;
    }
  }

  static (String, String) conditionForCode(int code) {
    if (code == 0) return ('Clear', 'sunny');
    if (code == 1) return ('Mostly clear', 'partly_cloudy');
    if (code == 2) return ('Partly cloudy', 'partly_cloudy');
    if (code == 3) return ('Cloudy', 'cloud');
    if (code == 45 || code == 48) return ('Fog', 'fog');
    if ({51, 53, 55, 56, 57}.contains(code)) {
      return ('Drizzle', 'rain');
    }
    if ({61, 63, 65, 66, 67, 80, 81, 82}.contains(code)) {
      return ('Rain', 'rain');
    }
    if ({71, 73, 75, 77, 85, 86}.contains(code)) {
      return ('Snow', 'snow');
    }
    if ({95, 96, 99}.contains(code)) {
      return ('Thunderstorms', 'storm');
    }
    return ('Weather', 'cloud');
  }

  static String messageForWeather(
    int code, {
    required num precipitation,
    required num rain,
  }) {
    if ({95, 96, 99}.contains(code)) return 'Storms nearby';
    if (rain > 0 || precipitation > 0) return 'Rain now';
    if ({61, 63, 65, 66, 67, 80, 81, 82}.contains(code)) {
      return 'Rain possible';
    }
    if ({71, 73, 75, 77, 85, 86}.contains(code)) {
      return 'Wintry weather';
    }
    if (code == 45 || code == 48) return 'Low visibility';
    return '';
  }

  static String _addressText(Object? raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      return map['formatted']?.toString().trim() ??
          map['address']?.toString().trim() ??
          '';
    }

    final text = raw?.toString().trim() ?? '';
    if (text.startsWith('{') && text.endsWith('}')) {
      final match = RegExp(r'formatted:\s*([^}]+)').firstMatch(text);
      if (match != null) return match.group(1)?.trim() ?? '';
    }
    return text;
  }

  static String _geocodeQuery(String address) {
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 4) return parts[1];
    if (parts.length >= 2) return parts.first;
    return address.trim();
  }

  static String _locationLabel(String address) {
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 4) {
      return '${parts[1]}, ${parts[2]}';
    }
    if (parts.length >= 2) {
      return '${parts[0]}, ${parts[1]}';
    }
    return parts.isEmpty ? '' : parts.first;
  }

  static Future<Map<String, dynamic>> _httpJson(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Briskers/1.0 weather',
      );
      final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Weather request failed with HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Weather response is not an object.');
      }
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }
}
