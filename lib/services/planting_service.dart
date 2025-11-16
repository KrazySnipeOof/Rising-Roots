import 'package:rising_roots/models/ag_models.dart';

abstract class PlantingService {
  Future<PlantingWindow> computeOptimalWindow({
    required String crop,
    required double latitude,
    required double longitude,
  });

  Future<double> calculateGrowingDegreeDays({
    required double tMin,
    required double tMax,
    required double baseTemp,
  });

  Stream<PlantingWindow> watchRecommendations(String fieldId);
}

