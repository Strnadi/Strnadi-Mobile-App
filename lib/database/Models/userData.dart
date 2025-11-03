class UserData {
  String FirstName;
  String LastName;
  String? NickName;

  String? ProfilePic;

  String? format;

  UserData(
      {required this.FirstName,
        required this.LastName,
        this.NickName,
        this.ProfilePic,
        this.format});

  factory UserData.fromJson(Map<String, Object?> json) {
    return UserData(
        FirstName: json['firstName'] as String,
        LastName: json['lastName'] as String,
        NickName: json['nickname'] as String?);
  }
}