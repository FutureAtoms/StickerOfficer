import 'dart:convert';

enum StickerPackType {
  staticPack,
  animatedPack;

  bool get isAnimated => this == StickerPackType.animatedPack;

  String get jsonValue => switch (this) {
    StickerPackType.staticPack => 'static',
    StickerPackType.animatedPack => 'animated',
  };

  String get label => switch (this) {
    StickerPackType.staticPack => 'Photo Pack',
    StickerPackType.animatedPack => 'Animated Pack',
  };

  static StickerPackType fromJsonValue(
    String? value, {
    List<String> stickerPaths = const [],
    List<String> tags = const [],
  }) {
    switch (value) {
      case 'animated':
        return StickerPackType.animatedPack;
      case 'static':
        return StickerPackType.staticPack;
      default:
        return infer(stickerPaths: stickerPaths, tags: tags);
    }
  }

  static StickerPackType infer({
    List<String> stickerPaths = const [],
    List<String> tags = const [],
  }) {
    final hasAnimatedTag = tags.any(
      (tag) => tag.toLowerCase().contains('animated'),
    );
    if (hasAnimatedTag) {
      return StickerPackType.animatedPack;
    }

    final hasGif = stickerPaths.any(
      (path) => path.toLowerCase().endsWith('.gif'),
    );
    return hasGif ? StickerPackType.animatedPack : StickerPackType.staticPack;
  }
}

class StickerPack {
  final String id;
  final String name;
  final String authorName;
  final StickerPackType type;
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
    this.type = StickerPackType.staticPack,
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
    StickerPackType? type,
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
      type: type ?? this.type,
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
      'type': type.jsonValue,
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
    final stickerPaths = List<String>.from(json['stickerPaths'] as List? ?? []);
    final tags = List<String>.from(json['tags'] as List? ?? []);

    return StickerPack(
      id: json['id'] as String,
      name: json['name'] as String,
      authorName: json['authorName'] as String,
      type: StickerPackType.fromJsonValue(
        json['type'] as String?,
        stickerPaths: stickerPaths,
        tags: tags,
      ),
      stickerPaths: stickerPaths,
      trayIconPath: json['trayIconPath'] as String?,
      likeCount: json['likeCount'] as int? ?? 0,
      downloadCount: json['downloadCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isPublic: json['isPublic'] as bool? ?? true,
      tags: tags,
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
      'StickerPack(id: $id, name: $name, type: ${type.jsonValue}, '
      'stickers: ${stickerPaths.length}, tags: $tags)';
}
