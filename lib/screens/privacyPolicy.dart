import 'package:flutter/material.dart';

class PrivacyConsentScreen extends StatelessWidget {
  final VoidCallback onAccepted;

  const PrivacyConsentScreen({super.key, required this.onAccepted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Privacy & Data Usage",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            const Text(
              "This app uses facial recognition and location data strictly for attendance verification. "
                  "No raw images are permanently stored, and data is not shared with third parties.",
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: onAccepted,
              child: const Text("Accept & Continue"),
            )
          ],
        ),
      ),
    );
  }
}