import 'package:flutter/material.dart';
import 'dart:ui';

class StylishLoadingIndicator extends StatelessWidget {
  const StylishLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    // We use a Stack to layer the blur filter and the loading widget.
    return Stack(
      children: [
        // 1. Frosted Glass/Blur Effect
        // This widget applies a visual filter to the content behind it.
        BackdropFilter(
          // Use ImageFilter.blur for the actual blur effect.
          filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
          child: Container(
            // Use a dark, semi-transparent color for the overlay tint
            // to make the white loader pop and ensure readability.
            color: Colors.black.withValues(alpha: 0.2),
          ),
        ),

        // 2. The Loading Widget in the Center
        Center(
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0), // Rounded corners
              boxShadow: [
                // Subtle shadow for depth
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 15,
                  spreadRadius: 3,
                ),
              ],
            ),
            // The loading animation itself
            child: const SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                // Use the primary color of the app or a vibrant color
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C853)), // Vibrant Green
                strokeWidth: 4.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class StylishLoadingDemo extends StatefulWidget {
  const StylishLoadingDemo({super.key});

  @override
  State<StylishLoadingDemo> createState() => _StylishLoadingDemoState();
}

class _StylishLoadingDemoState extends State<StylishLoadingDemo> {
  // We keep the loading logic here, so this screen demonstrates the loader.
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Simulate a 2-second loading time.
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stylish Loader Demo'),
        backgroundColor: const Color(0xFF00C853),
      ),
      body: Stack(
        children: [
          // Background Content
          ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              Text(
                'Attendance Records',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Divider(height: 30),
              // Dummy content to show the blur effect
              ListTile(
                  leading: CircleAvatar(child: Text('J')),
                  title: Text('John Doe - Clocked In'),
                  subtitle: Text('Time: 08:00 AM')),
              ListTile(
                  leading: CircleAvatar(child: Text('A')),
                  title: Text('Alice Smith - Clocked Out'),
                  subtitle: Text('Time: 05:00 PM')),
              ListTile(
                  leading: CircleAvatar(child: Text('M')),
                  title: Text('Mark Brown - Late In'),
                  subtitle: Text('Time: 09:15 AM')),
              // Add more list items to scroll and show content
              SizedBox(height: 200),
              Center(child: Text('Scroll down to see content hidden by the loader.')),
            ],
          ),

          // Conditional Loading Overlay
          if (_isLoading) const StylishLoadingIndicator(),
        ],
      ),
    );
  }
}