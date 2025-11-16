import 'package:rising_roots/models/ag_models.dart';

abstract class WeatherService {
  Future<WeatherSnapshot> fetchPrimaryForecast({
    required double latitude,
    required double longitude,
  });

  Future<WeatherSnapshot> fetchBackupForecast({
    required double latitude,
    required double longitude,
  });

  Future<double> calculateDailyEtc({
    required ForecastDay forecast,
    required double cropCoefficient,
  });

  Stream<WeatherSnapshot> watchLatestSnapshot(String fieldId);

  Future<void> saveSnapshot(String fieldId, WeatherSnapshot snapshot);
}

