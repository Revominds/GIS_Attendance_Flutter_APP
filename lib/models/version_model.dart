// Add this class before the SettingsScreen class or in a separate file
class VersionUpdate {
  final String version;
  final String title;
  final String description;
  final DateTime releaseDate;

  VersionUpdate({
    required this.version,
    required this.title,
    required this.description,
    required this.releaseDate,
  });
}

// Version data - you can update this as needed
List<VersionUpdate> getVersionHistory() {
  return [
    VersionUpdate(
      version: "v1.1.0 -  Current ",
      title: "Biometric Authentication Enhanced",
      description: "Added Face ID and Touch ID support for secure clock-in/out. Improved biometric error handling and user feedback.",
      releaseDate: DateTime(2024, 04, 14),
    ),
    VersionUpdate(
      version: "v1.0.1",
      title: "Location-Based Attendance",
      description: "Implemented geofencing for branch-specific clock-in/out. Real-time location verification added.",
      releaseDate: DateTime(2024, 2, 28),
    ),
    VersionUpdate(
      version: "v1.0.0",
      title: "Initial Release",
      description: "Basic attendance tracking with manual clock-in/out. User profile management and history view.",
      releaseDate: DateTime(2024, 1, 1),
    ),
  ];
}