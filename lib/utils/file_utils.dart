import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<String> saveImageBytesToFile(Uint8List bytes, String fileName) async {
  try {
    final Directory tempDir = await getTemporaryDirectory();
    final String filePath = '${tempDir.path}/$fileName';
    final File file = File(filePath);
    await file.writeAsBytes(bytes);
    return filePath;
  } catch (e) {
    throw Exception("Error saving image: $e");
  }
}
