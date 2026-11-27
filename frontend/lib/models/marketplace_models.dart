class MarketplaceCategory {
  final String id;
  final String name;
  final String scope;
  final int sortOrder;
  final bool active;

  MarketplaceCategory({
    required this.id,
    required this.name,
    required this.scope,
    required this.sortOrder,
    required this.active,
  });

  factory MarketplaceCategory.fromJson(Map<String, dynamic> json) =>
      MarketplaceCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        scope: json['scope'] as String,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        active: (json['active'] as bool?) ?? true,
      );
}

class MarketplaceSeller {
  final String id;
  final String name;
  final String? profilePic;

  MarketplaceSeller({
    required this.id,
    required this.name,
    this.profilePic,
  });

  factory MarketplaceSeller.fromJson(Map<String, dynamic> json) =>
      MarketplaceSeller(
        id: json['id'] as String,
        name: json['name'] as String,
        profilePic: json['profilePic'] as String?,
      );
}

class CommunityAd {
  final String id;
  final String sellerId;
  final String categoryId;
  final String? categoryName;
  final String title;
  final String description;
  final List<String> images;
  final int priceCents;
  final String condition;
  final String location;
  final String? contactPhone;
  final String? contactEmail;
  final String status;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MarketplaceSeller? seller;

  CommunityAd({
    required this.id,
    required this.sellerId,
    required this.categoryId,
    this.categoryName,
    required this.title,
    required this.description,
    required this.images,
    required this.priceCents,
    required this.condition,
    required this.location,
    this.contactPhone,
    this.contactEmail,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
    this.seller,
  });

  factory CommunityAd.fromJson(Map<String, dynamic> json) => CommunityAd(
        id: json['id'] as String,
        sellerId: json['sellerId'] as String,
        categoryId: json['categoryId'] as String,
        categoryName: json['categoryName'] as String?,
        title: json['title'] as String,
        description: (json['description'] as String?) ?? '',
        images: (json['images'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        priceCents: (json['priceCents'] as num).toInt(),
        condition: json['condition'] as String,
        location: json['location'] as String,
        contactPhone: json['contactPhone'] as String?,
        contactEmail: json['contactEmail'] as String?,
        status: json['status'] as String,
        rejectionReason: json['rejectionReason'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        seller: json['seller'] != null
            ? MarketplaceSeller.fromJson(json['seller'] as Map<String, dynamic>)
            : null,
      );

  String get priceLabel =>
      '\$${(priceCents / 100).toStringAsFixed(priceCents % 100 == 0 ? 0 : 2)}';

  bool get isSold => status == 'sold';
}

class ShopProduct {
  final String id;
  final String? categoryId;
  final String? categoryName;
  final String title;
  final String description;
  final List<String> images;
  final int priceCents;
  final bool active;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  ShopProduct({
    required this.id,
    this.categoryId,
    this.categoryName,
    required this.title,
    required this.description,
    required this.images,
    required this.priceCents,
    required this.active,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) => ShopProduct(
        id: json['id'] as String,
        categoryId: json['categoryId'] as String?,
        categoryName: json['categoryName'] as String?,
        title: json['title'] as String,
        description: (json['description'] as String?) ?? '',
        images: (json['images'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        priceCents: (json['priceCents'] as num).toInt(),
        active: (json['active'] as bool?) ?? true,
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  String get priceLabel =>
      '\$${(priceCents / 100).toStringAsFixed(priceCents % 100 == 0 ? 0 : 2)}';
}