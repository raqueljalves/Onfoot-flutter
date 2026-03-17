import 'package:flutter/material.dart';

class EmojiSelectorScreen extends StatelessWidget {
  final List<String> emojis = [
    '🚶‍♀️', '🚶', '🏃‍♀️', '🏃',
    '🐱', '🐶', '🦊', '🐻', '🐼',
    '🌟', '⚡', '🔥', '💎', '✨',
    '🎯', '🧭', '📍', '🗺️',
    '☕', '📚', '🎸', '🍕', '🎨',
  ];

  EmojiSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Emoji'),
        backgroundColor: const Color(0xFF9CAF88),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: emojis.map((emoji) =>
            GestureDetector(
              onTap: () => Navigator.pop(context, emoji),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 40)),
                ),
              ),
            )
          ).toList(),
        ),
      ),
    );
  }
}