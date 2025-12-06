import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:onfoot/providers/event_provider.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  @override
  void initState() {
    super.initState();
    Provider.of<EventProvider>(context, listen: false).loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<EventProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Eventos OnFoot")),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: provider.events.length,
              itemBuilder: (_, index) {
                final event = provider.events[index];
                return ListTile(
                  title: Text(event.title),
                  subtitle: Text(event.location),
                  trailing: Text(
                    "${event.date.day}/${event.date.month}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
    );
  }
}
