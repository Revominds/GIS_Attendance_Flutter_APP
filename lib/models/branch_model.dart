class Department {
  final int id;
  final String name;

  Department({required this.id, required this.name});

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] is String ? int.parse(json['id']) : json['id'],
      name: json['name'] ?? '',
    );
  }
}

class Branch {
  final int id;
  final String name;
  final List<Department> departments;

  Branch({required this.id, required this.name, required this.departments});

  factory Branch.fromJson(Map<String, dynamic> json) {
    var deptsFromJson = json['departments'] as List? ?? [];
    List<Department> deptList = deptsFromJson.map((i) => Department.fromJson(i)).toList();

    return Branch(
      id: json['id'] is String ? int.parse(json['id']) : json['id'],
      name: json['name'] ?? '',
      departments: deptList,
    );
  }
}