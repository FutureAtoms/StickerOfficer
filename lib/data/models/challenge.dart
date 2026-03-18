import 'dart:convert';

class Challenge {
  final String id;
  final String title;
  final String description;
  final String status; // 'active', 'voting', 'completed'
  final DateTime startDate;
  final DateTime endDate;
  final int submissionCount;
  final String? winnerName;

  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.startDate,
    required this.endDate,
    this.submissionCount = 0,
    this.winnerName,
  });

  Challenge copyWith({
    String? id,
    String? title,
    String? description,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    int? submissionCount,
    String? winnerName,
  }) {
    return Challenge(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      submissionCount: submissionCount ?? this.submissionCount,
      winnerName: winnerName ?? this.winnerName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'submissionCount': submissionCount,
      'winnerName': winnerName,
    };
  }

  factory Challenge.fromJson(Map<String, dynamic> json) {
    return Challenge(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      status: json['status'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      submissionCount: json['submissionCount'] as int? ?? 0,
      winnerName: json['winnerName'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory Challenge.fromJsonString(String source) =>
      Challenge.fromJson(jsonDecode(source) as Map<String, dynamic>);

  bool get isActive => status == 'active';
  bool get isVoting => status == 'voting';
  bool get isCompleted => status == 'completed';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Challenge && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Challenge(id: $id, title: $title, status: $status)';
}
