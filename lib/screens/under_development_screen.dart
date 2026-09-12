import 'package:flutter/material.dart';

class UnderDevelopmentScreen extends StatelessWidget {
  final String title;

  const UnderDevelopmentScreen({
    super.key,
    this.title = "Feature Under Development",
  });

  @override
  Widget build(BuildContext Context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.grey.shade100,
        title: Text(title),
        centerTitle: true,
      ),

      backgroundColor: const Color(0xFFF3F4F6),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.construction,
                size: 100,
                color: Colors.green,
              ),
              const SizedBox(height: 25),

              const Text(
               "This feature is under development",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                "Please check again later for updates",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black
                ),
              ),
              const SizedBox(height: 30),

              ElevatedButton(
                  onPressed: (){
                    Navigator.pop(Context);
                  },
                  child: const Text("Go Back")
              ),
            ],
          ),
        ),
      ),
    );
  }
}


    