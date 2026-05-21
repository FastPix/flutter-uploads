import 'package:flutter/material.dart';

import 'upload_screen.dart';

void main() {
  runApp(const FastPixUploaderExampleApp());
}

class FastPixUploaderExampleApp extends StatelessWidget {
  const FastPixUploaderExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FastPix Resumable Uploader Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const UploadScreen(),
    );
  }
}
