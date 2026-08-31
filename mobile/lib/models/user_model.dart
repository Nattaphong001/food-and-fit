class User {
  final int userId;
  final String email;
  final String fullName;
  final String gender;
  final DateTime birthDate;
  final String? phone;
  final String? address;
  final String? profilePic;
  final DateTime createdAt;

  User({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.gender,
    required this.birthDate,
    this.phone,
    this.address,
    this.profilePic,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        userId: json['user_id'] ?? json['id'] ?? 0,
        email: json['email'] ?? '',
        fullName: json['full_name'] ?? '',
        gender: (json['gender'] ?? '').toString(),
        birthDate: DateTime.tryParse(json['birth_date'] ?? '') ?? DateTime.now(),
        phone: json['phone'],
        address: json['address'],
        profilePic: json['profile_pic']?.toString(),
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'email': email,
        'full_name': fullName,
        'gender': gender,
        'birth_date': birthDate.toIso8601String(),
        'phone': phone,
        'address': address,
        'profile_pic': profilePic,
        'created_at': createdAt.toIso8601String(),
      };
}
