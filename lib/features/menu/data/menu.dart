import '../../../core/api/api_client.dart';

/// `GET /menu`: sections in display order, each with its dishes.
class Menu {
  const Menu(this.sections);

  factory Menu.fromJson(Json json) =>
      Menu([for (final s in json['sections']! as List) MenuSection.fromJson(s as Json)]);

  final List<MenuSection> sections;

  Iterable<Dish> get dishes => sections.expand((s) => s.items);

  Dish? dish(int id) {
    for (final d in dishes) {
      if (d.id == id) return d;
    }
    return null;
  }

  List<Dish> get bestsellers => [
    for (final d in dishes)
      if (d.bestseller && d.available) d,
  ];

  /// The menu filtered for the search box and the veg-only switch. Empty sections drop out.
  List<MenuSection> filter({String query = '', bool vegOnly = false}) {
    final q = query.trim().toLowerCase();
    return [
      for (final section in sections)
        if (section.items.where((d) => _matches(d, q, vegOnly)).toList() case final items
            when items.isNotEmpty)
          MenuSection(id: section.id, name: section.name, slug: section.slug, items: items),
    ];
  }

  static bool _matches(Dish d, String q, bool vegOnly) {
    if (vegOnly && !d.veg) return false;
    if (q.isEmpty) return true;
    return d.name.toLowerCase().contains(q) || d.description.toLowerCase().contains(q);
  }
}

class MenuSection {
  const MenuSection({required this.id, required this.name, required this.slug, required this.items});

  factory MenuSection.fromJson(Json json) => MenuSection(
    id: json['id']! as int,
    name: json['name']! as String,
    slug: json['slug']! as String,
    items: [for (final i in json['items']! as List) Dish.fromJson(i as Json)],
  );

  final int id;
  final String name;
  final String slug;
  final List<Dish> items;

  /// A photo to stand for the section on the home page's tiles.
  String? get coverPhoto {
    for (final d in items) {
      if (d.photoUrl != null) return d.photoUrl;
    }
    return null;
  }
}

class Dish {
  const Dish({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.pricePaise,
    required this.fromPricePaise,
    required this.veg,
    required this.spice,
    required this.bestseller,
    required this.available,
    required this.photoUrl,
    required this.variants,
    required this.addonGroups,
  });

  factory Dish.fromJson(Json json) => Dish(
    id: json['id']! as int,
    slug: json['slug'] as String? ?? '',
    name: json['name']! as String,
    description: json['description'] as String? ?? '',
    pricePaise: json['pricePaise']! as int,
    fromPricePaise: json['fromPricePaise'] as int? ?? json['pricePaise']! as int,
    veg: json['veg'] as bool? ?? false,
    spice: json['spice'] as int? ?? 0,
    bestseller: json['bestseller'] as bool? ?? false,
    available: json['available'] as bool? ?? true,
    photoUrl: json['photoUrl'] as String?,
    variants: [for (final v in json['variants'] as List? ?? const []) Variant.fromJson(v as Json)],
    addonGroups: [
      for (final g in json['addonGroups'] as List? ?? const []) AddonGroup.fromJson(g as Json),
    ],
  );

  final int id;
  final String slug;
  final String name;
  final String description;
  final int pricePaise;

  /// The lowest price, for "from ₹260" labels.
  final int fromPricePaise;
  final bool veg;

  /// 0 (not spicy) to 3.
  final int spice;
  final bool bestseller;

  /// False when sold out: shown greyed out, cannot be ordered.
  final bool available;
  final String? photoUrl;
  final List<Variant> variants;
  final List<AddonGroup> addonGroups;

  /// Whether adding it needs the dish sheet (a size or a choice to make).
  bool get hasOptions => variants.isNotEmpty || addonGroups.isNotEmpty;

  Dish copyWith({bool? available}) => Dish(
    id: id,
    slug: slug,
    name: name,
    description: description,
    pricePaise: pricePaise,
    fromPricePaise: fromPricePaise,
    veg: veg,
    spice: spice,
    bestseller: bestseller,
    available: available ?? this.available,
    photoUrl: photoUrl,
    variants: variants,
    addonGroups: addonGroups,
  );
}

class Variant {
  const Variant({required this.id, required this.name, required this.pricePaise});

  factory Variant.fromJson(Json json) => Variant(
    id: json['id']! as int,
    name: json['name']! as String,
    pricePaise: json['pricePaise']! as int,
  );

  final int id;
  final String name;
  final int pricePaise;
}

class AddonGroup {
  const AddonGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.addons,
  });

  factory AddonGroup.fromJson(Json json) => AddonGroup(
    id: json['id']! as int,
    name: json['name']! as String,
    minSelect: json['minSelect'] as int? ?? 0,
    maxSelect: json['maxSelect'] as int? ?? 1,
    addons: [for (final a in json['addons']! as List) Addon.fromJson(a as Json)],
  );

  final int id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<Addon> addons;

  /// "Choose one" groups behave like radio buttons.
  bool get isSingleChoice => minSelect == 1 && maxSelect == 1;

  String get hint {
    if (isSingleChoice) return 'Choose one';
    if (minSelect == 0) return 'Optional · up to $maxSelect';
    if (minSelect == maxSelect) return 'Choose $minSelect';
    return 'Choose $minSelect to $maxSelect';
  }
}

class Addon {
  const Addon({required this.id, required this.name, required this.pricePaise});

  factory Addon.fromJson(Json json) => Addon(
    id: json['id']! as int,
    name: json['name']! as String,
    pricePaise: json['pricePaise'] as int? ?? 0,
  );

  final int id;
  final String name;
  final int pricePaise;
}
