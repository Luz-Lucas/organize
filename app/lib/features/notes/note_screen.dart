import 'package:flutter/material.dart';

class NoteScreen extends StatelessWidget {
  const NoteScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar());
}
