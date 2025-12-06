import 'package:onfoot_app/models/event_model.dart';

class EventService {
  Future<List<Event>> getEvents() async {
    await Future.delayed(const Duration(seconds: 1)); // simula network

    return [
      Event(
        id: '1',
        title: 'Trilha Pedra Bonita',
        description: 'Uma trilha clássica com vista incrível.',
        location: 'Rio de Janeiro - RJ',
        date: DateTime.now().add(const Duration(days: 3)),
      ),
      Event(
        id: '2',
        title: 'Caminhada Serra do Japi',
        description: 'Trilha leve em Jundiaí.',
        location: 'Jundiaí - SP',
        date: DateTime.now().add(const Duration(days: 10)),
      ),
    ];
  }
}
