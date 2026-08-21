import 'dart:async';
import 'package:flutter/material.dart';

enum JourneyEndPromptMode { arrival, manualStop }

class JourneyEndPrompt extends StatefulWidget {
  final JourneyEndPromptMode mode;
  final void Function(String status, String? note) onRespond;
  final VoidCallback onAutoDismiss;
  final VoidCallback onDismiss;

  const JourneyEndPrompt({
    super.key,
    required this.mode,
    required this.onRespond,
    required this.onAutoDismiss,
    required this.onDismiss,
  });

  @override
  State<JourneyEndPrompt> createState() => _JourneyEndPromptState();
}

class _JourneyEndPromptState extends State<JourneyEndPrompt> {
  Timer? _autoDismissTimer;
  String? _selectedSecondary; // 'stopped_early' | 'problem'
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.mode == JourneyEndPromptMode.arrival) {
      _autoDismissTimer = Timer(const Duration(seconds: 9), widget.onAutoDismiss);
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  void _cancelTimer() => _autoDismissTimer?.cancel();

  void _selectSecondary(String status) {
    _cancelTimer();
    setState(() => _selectedSecondary = status);
  }

  void _submitNote() {
    final text = _noteController.text.trim();
    widget.onRespond(_selectedSecondary!, text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final isArrival = widget.mode == JourneyEndPromptMode.arrival;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  isArrival ? 'Chegaste bem ao teu destino? 👣' : 'Porque paraste?',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (_selectedSecondary == null) ...[
                  if (isArrival) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _cancelTimer();
                          widget.onRespond('completed', null);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Sim, cheguei bem ✅',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _selectSecondary('stopped_early'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Parei a meio', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _selectSecondary('problem'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Algo correu mal', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                  if (!isArrival) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: widget.onDismiss,
                      child: const Text('Agora não', style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                ] else ...[
                  TextField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      hintText: 'descreve o que aconteceu (opcional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitNote,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6AA57A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Enviar'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
