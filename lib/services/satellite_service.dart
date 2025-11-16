import 'dart:ui';

import 'package:rising_roots/models/ag_models.dart';

abstract class SatelliteService {
  Future<VegetationIndices> fetchIndices({
    required String fieldId,
    required DateTime date,
  });

  Future<Image> fetchCompositeImagery({
    required String fieldId,
    required DateTime start,
    required DateTime end,
    bool splitView = false,
  });

  Stream<VegetationIndices> watchIndexSeries(String fieldId);

  Future<void> saveIndices(String fieldId, VegetationIndices indices);

  Future<void> triggerStressAlert({
    required String fieldId,
    required VegetationIndices indices,
  });
}

