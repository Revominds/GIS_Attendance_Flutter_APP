import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class InactivityDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onInactive;
  final Duration timeout;

  const InactivityDetector({
    super.key,
    required this.child,
    required this.onInactive,
    this.timeout = const Duration(minutes: 10), required , // Default to 5 minutes
  });

  @override
  State<InactivityDetector> createState() => _InactivityDetectorState();
}

class _InactivityDetectorState extends State<InactivityDetector> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, widget.onInactive);
  }

  void _handleUserInteraction(PointerEvent event) {
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    // Listener widget detects all pointer events in its subtree.
    return Listener(
      onPointerDown: _handleUserInteraction,
      onPointerMove: _handleUserInteraction,
      onPointerUp: _handleUserInteraction,
      child: widget.child,
    );
  }
}
