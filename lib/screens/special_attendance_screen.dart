// import 'package:flutter/material.dart';
// import 'package:camera/camera.dart';
// import 'face_verification_screen.dart';
// import '../services/attendance_service.dart';

// class SpecialAttendanceScreen extends StatefulWidget {
//   final Map<String, dynamic> userProfile;
//   final String? attendanceId;
//   const SpecialAttendanceScreen({super.key, required this.userProfile, required this.attendanceId});

//   @override
//   State<SpecialAttendanceScreen> createState() => _SpecialAttendanceScreenState();
// }

// class _SpecialAttendanceScreenState extends State<SpecialAttendanceScreen> {
//   final TextEditingController _reasonController = TextEditingController();
//   final AttendanceService _attendanceService = AttendanceService();
//   bool _isLoading = false;
//   bool _isClockInAction = true;

//   Future<void> _handleAttendanceAction() async {
//     if (_reasonController.text.trim().isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text("Please provide a reason for special attendance"),
//           behavior: SnackBarBehavior.floating,
//         ),
//       );
//       return;
//     }

//     try {
//       final cameras = await availableCameras();
//       final frontCamera = cameras.firstWhere(
//             (c) => c.lensDirection == CameraLensDirection.front,
//         orElse: () => cameras.first,
//       );

//       final verified = await Navigator.of(context).push<bool>(
//         MaterialPageRoute(
//           builder: (_) => FaceVerificationScreen(
//             camera: frontCamera,
//             userId: widget.userProfile['id'].toString(),
//           ),
//         ),
//       );

//       if (verified == true) {
//         setState(() => _isLoading = true);
//         final result = _isClockInAction
//             ? await _attendanceService.clockIn(
//           userId: widget.userProfile['id'].toString(),
//           comment: "SPECIAL (IN): ${_reasonController.text}",
//           type: "SPECIAL",
//           isSpecial: true,
//         ) :
//         await _attendanceService.clockOut(
//           comment: "SPECIAL (OUT): ${_reasonController.text}", attendanceId: widget.attendanceId.toString(),
//         );

//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(result.message),
//               backgroundColor: result.ok ? Colors.green.shade800 : Colors
//                   .redAccent,
//               behavior: SnackBarBehavior.floating,
//             ),
//           );
//           if (result.ok) {
//             _resetForm();
//           }
//         }
//       }
//     } catch (e) {
//       debugPrint("Special attendance error: $e");
//     } finally {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }

//   void _resetForm() {
//     setState(() {
//       _isLoading = false;
//       _reasonController.clear(); // Clears the text field
//       _isClockInAction = true;   // Resets the toggle to Clock In (Optional)
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF8F9FA),
//       body: Column(
//         children: [
//           _buildModernHeader(),
//           Expanded(
//             child: SingleChildScrollView(
//               padding: const EdgeInsets.all(24.0),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   // --- ACTION SELECTOR ---
//                   const Text(
//                     "Select Action",
//                     style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//                   ),
//                   const SizedBox(height: 12),
//                   Row(
//                     children: [
//                       _buildActionTab("Clock In", Icons.login, _isClockInAction, () {
//                         setState(() => _isClockInAction = true);
//                       }),
//                       const SizedBox(width: 12),
//                       _buildActionTab("Clock Out", Icons.logout, !_isClockInAction, () {
//                         setState(() => _isClockInAction = false);
//                       }),
//                     ],
//                   ),

//                   const SizedBox(height: 30),
//                   const Text(
//                     "Reason / Details",
//                     style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//                   ),
//                   const SizedBox(height: 12),
//                   Container(
//                     decoration: BoxDecoration(
//                       color: Colors.white,
//                       borderRadius: BorderRadius.circular(20),
//                       boxShadow: [
//                         BoxShadow(
//                           color: Colors.black.withValues(alpha: 0.05),
//                           blurRadius: 15,
//                           offset: const Offset(0, 5),
//                         )
//                       ],
//                     ),
//                     child: TextField(
//                       controller: _reasonController,
//                       maxLines: 4,
//                       style: const TextStyle(fontSize: 15),
//                       decoration: InputDecoration(
//                         hintText: "Why are you clocking ${_isClockInAction ? 'in' : 'out'} remotely?",
//                         hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
//                         border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
//                         filled: true,
//                         fillColor: Colors.white,
//                         contentPadding: const EdgeInsets.all(20),
//                       ),
//                     ),
//                   ),

//                   const SizedBox(height: 40),

//                   // Verification Button
//                   SizedBox(
//                     width: double.infinity,
//                     height: 55,
//                     child: ElevatedButton(
//                       onPressed: _isLoading ? null : _handleAttendanceAction,
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: _isClockInAction ? Colors.green.shade700 : Colors.orange.shade800,
//                         foregroundColor: Colors.white,
//                         elevation: 2,
//                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//                       ),
//                       child: _isLoading
//                           ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
//                           : Row(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           const Icon(Icons.face_unlock_rounded),
//                           const SizedBox(width: 12),
//                           Text(
//                             "Verify & ${_isClockInAction ? 'Clock In' : 'Clock Out'}",
//                             style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 20),
//                   const Center(
//                     child: Text("Secure Biometric Verification Required", style: TextStyle(color: Colors.grey, fontSize: 12)),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildActionTab(String label, IconData icon, bool isActive, VoidCallback onTap) {
//     return Expanded(
//       child: GestureDetector(
//         onTap: onTap,
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 250),
//           padding: const EdgeInsets.symmetric(vertical: 16),
//           decoration: BoxDecoration(
//             color: isActive ? (label == "Clock In" ? Colors.green.shade700 : Colors.orange.shade800) : Colors.white,
//             borderRadius: BorderRadius.circular(16),
//             border: Border.all(color: isActive ? Colors.transparent : Colors.grey.shade300),
//           ),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Icon(icon, color: isActive ? Colors.white : Colors.grey, size: 20),
//               const SizedBox(width: 8),
//               Text(
//                 label,
//                 style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontWeight: FontWeight.bold),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildModernHeader() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//           colors: [Colors.green.shade700, Colors.lightGreenAccent.shade700],
//         ),
//         borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
//         boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
//       ),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               GestureDetector(
//                 onTap: () => Navigator.pop(context),
//                 child: Container(
//                   padding: const EdgeInsets.all(10),
//                   decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
//                   child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
//                 ),
//               ),
//               Expanded(
//                 child: Text(
//                   "Special Attendance Service",
//                   style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 20),
//           const Text(
//             "Bypassing location for remote work",
//             textAlign: TextAlign.center,
//             style: TextStyle(color: Colors.white70, fontSize: 14),
//           ),
//         ],
//       ),
//     );
//   }
// }