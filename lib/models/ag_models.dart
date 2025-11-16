import 'package:flutter/foundation.dart';

enum DroughtRisk { low, moderate, high }

enum WeatherSource {
  metostat,
  nasaPower,
}

@immutable
class ForecastDay {
  const ForecastDay({
    required this.date,
    required this.minTempC,
    required this.maxTempC,
    required this.humidity,
    required this.windSpeedMs,
    required this.rainMm,
    required this.solarRadiation,
  });

  final DateTime date;
  final double minTempC;
  final double maxTempC;
  final double humidity;
  final double windSpeedMs;
  final double rainMm;
  final double solarRadiation;
}

@immutable
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.generatedAt,
    required this.forecast,
    required this.etcMillimeters,
    required this.droughtRisk,
  });

  final String locationName;
  final double latitude;
  final double longitude;
  final DateTime generatedAt;
  final List<ForecastDay> forecast;
  final double etcMillimeters;
  final DroughtRisk droughtRisk;
}

@immutable
class VegetationIndices {
  const VegetationIndices({
    required this.capturedAt,
    required this.platform,
    required this.ndvi,
    required this.ndmi,
    required this.ndre,
    required this.vhi,
  });

  final DateTime capturedAt;
  final String platform;
  final double ndvi;
  final double ndmi;
  final double ndre;
  final double vhi;
}

@immutable
class SoilWaterBalance {
  const SoilWaterBalance({
    required this.date,
    required this.deficitPercent,
    required this.deficitInches,
    required this.cropStage,
    required this.recommendedIrrigationInches,
  });

  final DateTime date;
  final double deficitPercent;
  final double deficitInches;
  final String cropStage;
  final double recommendedIrrigationInches;
}

@immutable
class IrrigationEvent {
  const IrrigationEvent({
    required this.timestamp,
    required this.inchesApplied,
    required this.method,
    required this.notes,
  });

  final DateTime timestamp;
  final double inchesApplied;
  final String method;
  final String notes;
}

@immutable
class PlantingWindow {
  const PlantingWindow({
    required this.crop,
    required this.optimalStart,
    required this.optimalEnd,
    required this.gddTarget,
    required this.notes,
  });

  final String crop;
  final DateTime optimalStart;
  final DateTime optimalEnd;
  final double gddTarget;
  final String notes;
}

@immutable
class ClimateRiskScore {
  const ClimateRiskScore({
    required this.droughtFrequency,
    required this.floodRisk,
    required this.heatStressDays,
    required this.frostRisk,
    required this.overall,
  });

  final double droughtFrequency;
  final double floodRisk;
  final double heatStressDays;
  final double frostRisk;
  final double overall;
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  final String id;
  final String role; // user | assistant | system
  final String content;
  final DateTime timestamp;
}

@immutable
class PrecipSample {
  const PrecipSample({
    required this.date,
    required this.precipInches,
  });

  final DateTime date;
  final double precipInches;
}

@immutable
class WeatherAlert {
  const WeatherAlert({
    required this.message,
    required this.timestamp,
  });

  final String message;
  final DateTime timestamp;
}

