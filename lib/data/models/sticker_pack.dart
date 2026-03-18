import 'dart:convert';

class StickerPack {
  final String id;
  final String name;
  final String authorName;
  final List<String> stickerPaths;
  final String? trayIconPath;
  final int likeCount;
  final int downloadCount;
  final DateTime createdAt;
  final bool isPublic;
  final List<String> tags;

  const StickerPack({
    required this.id,
    required this.name,
    required this.authorName,
    this.stickerPaths = const [],
    this.trayIconPath,
    this.likeCount = 0,
    this.downloadCount = 0,
    required this.createdAt,
    this.isPublic = true,
    this.tags = const [],
  });

  StickerPack copyWith({
    String? id,
    String? name,
    String? authorName,
    List<String>? stickerPaths,
    String? trayIconPath,
    int? likeCount,
    int? downloadCount,
    DateTime? createdAt,
    bool? isPublic,
    List<String>? tags,
  }) {
    return StickerPack(
      id: id ?? this.id,
      name: name ?? this.name,
      authorName: authorName ?? this.authorName,
      stickerPaths: stickerPaths ?? this.stickerPaths,
      trayIconPath: trayIconPath ?? this.trayIconPath,
      likeCount: likeCount ?? this.likeCount,
      downloadCount: downloadCount ?? this.downloadCount,
      createdAt: createdAt ?? this.createdAt,
      isPublic: isPublic ?? this.isPublic,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'authorName': authorName,
      'stickerPaths': stickerPaths,
      'trayIconPath': trayIconPath,
      'likeCount': likeCount,
      'downloadCount': downloadCount,
      'createdAt': createdAt.toIso8601String(),
      'isPublic': isPublic,
      'tags': tags,
    };
  }

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    return StickerPack(
      id: json['id'] as String,
      name: json['name'] as String,
      authorName: json['authorName'] as String,
      stickerPaths: List<String>.from(json['stickerPaths'] as List? ?? []),
      trayIconPath: json['trayIconPath'] as String?,
      likeCount: json['likeCount'] as int? ?? 0,
      downloadCount: json['downloadCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isPublic: json['isPublic'] as bool? ?? true,
      tags: List<String>.from(json['tags'] as List? ?? []),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory StickerPack.fromJsonString(String source) =>
      StickerPack.fromJson(jsonDecode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StickerPack && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'StickerPack(id: $id, name: $name, '
      'stickers: ${stickerPaths.length}, tags: $tags)';
}
