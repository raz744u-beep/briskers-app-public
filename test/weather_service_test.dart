import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/services/weather_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('weather service geocodes shop address, parses and caches weather',
      () async {
    SharedPreferences.setMockInitialValues({});
    var forecastCalls = 0;

    final service = BriskersWeatherService(
      forceOffline: () => false,
      businessSettingsLoader: (_) async => {
        'address': {
          'formatted': '1400 Stumpf Blvd, Gretna, LA, 70053',
        },
        'latitude': null,
        'longitude': null,
      },
      jsonLoader: (uri) async {
        if (uri.host == 'geocoding-api.open-meteo.com') {
          expect(uri.queryParameters['name'], 'Gretna');
          return {
            'results': [
              {
                'name': 'Gretna',
                'admin1': 'Louisiana',
                'latitude': 29.9146,
                'longitude': -90.0539,
              },
            ],
          };
        }
        forecastCalls += 1;
        return {
          'current': {
            'temperature_2m': 82.6,
            'apparent_temperature': 87.1,
            'precipitation': 0.02,
            'rain': 0.02,
            'weather_code': 61,
            'wind_speed_10m': 8.0,
          },
        };
      },
    );

    final snapshot = await service.load(
      'business-1',
      forceRefresh: true,
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.condition, 'Rain');
    expect(snapshot.iconKey, 'rain');
    expect(snapshot.message, 'Rain now');
    expect(snapshot.temperatureF, 82.6);
    expect(snapshot.locationLabel, 'Gretna, Louisiana');
    expect(forecastCalls, 1);

    final cached = await service.loadCached('business-1');
    expect(cached, isNotNull);
    expect(cached!.temperatureF, 82.6);
    expect(cached.condition, 'Rain');
  });

  test('weather condition mapping keeps severe conditions visible', () {
    expect(
      BriskersWeatherService.conditionForCode(95),
      ('Thunderstorms', 'storm'),
    );
    expect(
      BriskersWeatherService.messageForWeather(
        95,
        precipitation: 0,
        rain: 0,
      ),
      'Storms nearby',
    );
  });
}
