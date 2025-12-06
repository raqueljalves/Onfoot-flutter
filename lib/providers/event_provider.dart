import 'package:flutter/material.dart';
import 'package:onfoot_app/models/event_model.dart';
import 'package:onfoot_app/services/event_service.dart';

class EventProvider extends ChangeNotifier {
  final EventService _service = EventService();

  List<Event> events = [];
  bool isLoading = false;

  Future<void> loadEvents() async {
    isLoading = true;
    notifyListeners();

    events = await _service.getEvents();

    isLoading = false;
    notifyListeners();
  }
}
