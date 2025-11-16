import 'package:rising_roots/models/ag_models.dart';

abstract class IrrigationService {
  Future<SoilWaterBalance> calculateWaterBalance({
    required String fieldId,
    required DateTime date,
  });

  Future<void> logIrrigationEvent(String fieldId, IrrigationEvent event);

  Stream<List<IrrigationEvent>> watchIrrigationEvents(String fieldId);

  Future<void> scheduleDailyNotification({
    required String fieldId,
    required DateTime triggerTime,
  });

  Future<void> cancelNotifications(String fieldId);
}

