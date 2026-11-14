class Community {
  final String id;
  final String creatorId;
  final String name;
  final String description;
  final DateTime createdAt;
  final String status;
  final bool isAdmin;

  const Community({
    required this.id,
    required this.creatorId,
    required this.name,
    required this.description,
    required this.createdAt,
    this.status = '',
    this.isAdmin = false,
  });

  factory Community.fromJson(Map<String, dynamic> json) => Community(
        id: json['id'] as String,
        creatorId: json['creatorId'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        status: json['status'] as String? ?? '',
        isAdmin: json['isAdmin'] as bool? ?? false,
      );
}

class CommunityMembership {
  final String id;
  final String communityId;
  final String userId;
  final String userName;
  final String status;
  final bool isAdmin;

  const CommunityMembership({
    required this.id,
    required this.communityId,
    required this.userId,
    required this.userName,
    required this.status,
    required this.isAdmin,
  });

  factory CommunityMembership.fromJson(Map<String, dynamic> json) =>
      CommunityMembership(
        id: json['id'] as String,
        communityId: json['communityId'] as String,
        userId: json['userId'] as String,
        userName: json['userName'] as String? ?? 'User',
        status: json['status'] as String,
        isAdmin: json['isAdmin'] as bool? ?? false,
      );
}

class CommunityMessage {
  final String id;
  final String communityId;
  final int seq;
  final String? userId;
  final String authorName;
  final String? authorPic;
  final String content;
  final DateTime createdAt;

  const CommunityMessage({
    required this.id,
    required this.communityId,
    required this.seq,
    this.userId,
    required this.authorName,
    this.authorPic,
    required this.content,
    required this.createdAt,
  });

  factory CommunityMessage.fromJson(Map<String, dynamic> json) =>
      CommunityMessage(
        id: json['id'] as String,
        communityId: json['communityId'] as String,
        seq: (json['seq'] as num).toInt(),
        userId: json['userId'] as String?,
        authorName: json['authorName'] as String? ?? 'User',
        authorPic: json['authorPic'] as String?,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class CommunityCursorPage {
  final List<CommunityMessage> data;
  final bool hasMore;

  const CommunityCursorPage({required this.data, required this.hasMore});

  factory CommunityCursorPage.fromJson(Map<String, dynamic> json) =>
      CommunityCursorPage(
        data: (json['data'] as List)
            .map((item) =>
                CommunityMessage.fromJson(item as Map<String, dynamic>))
            .toList(),
        hasMore: json['hasMore'] as bool? ?? false,
      );
}
