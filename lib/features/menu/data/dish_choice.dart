import '../../cart/data/cart.dart';
import 'menu.dart';

/// The choices being made in the dish sheet: a size, add-ons and a quantity.
///
/// Follows the web's sheet: the first variant is pre-selected, "choose one" groups pre-select
/// their first add-on, and each group must end up with between `minSelect` and `maxSelect`.
class DishChoice {
  DishChoice._(this.dish, this.variant, this.selected, this.quantity);

  factory DishChoice.initial(Dish dish) =>
      DishChoice._(dish, dish.variants.isEmpty ? null : dish.variants.first, {
        for (final g in dish.addonGroups)
          g.id: g.isSingleChoice && g.addons.isNotEmpty ? {g.addons.first.id} : <int>{},
      }, 1);

  final Dish dish;
  final Variant? variant;

  /// Addon group id -> chosen addon ids.
  final Map<int, Set<int>> selected;
  final int quantity;

  DishChoice withVariant(Variant v) => DishChoice._(dish, v, selected, quantity);

  DishChoice withQuantity(int q) => DishChoice._(dish, variant, selected, q.clamp(1, 20));

  /// Ticks or unticks [addon] in [group]. A single-choice group swaps; a group at its maximum
  /// ignores more ticks.
  DishChoice toggle(AddonGroup group, Addon addon) {
    final current = {...?selected[group.id]};
    if (group.isSingleChoice) {
      current
        ..clear()
        ..add(addon.id);
    } else if (current.contains(addon.id)) {
      current.remove(addon.id);
    } else if (current.length < group.maxSelect) {
      current.add(addon.id);
    }
    return DishChoice._(dish, variant, {...selected, group.id: current}, quantity);
  }

  bool isChosen(AddonGroup group, Addon addon) => selected[group.id]?.contains(addon.id) ?? false;

  bool isFull(AddonGroup group) =>
      !group.isSingleChoice && (selected[group.id]?.length ?? 0) >= group.maxSelect;

  List<Addon> get addons => [
    for (final g in dish.addonGroups)
      for (final a in g.addons)
        if (isChosen(g, a)) a,
  ];

  /// The first group that still needs a pick, if any.
  AddonGroup? get missing {
    for (final g in dish.addonGroups) {
      if ((selected[g.id]?.length ?? 0) < g.minSelect) return g;
    }
    return null;
  }

  bool get isValid => dish.available && (dish.variants.isEmpty || variant != null) && missing == null;

  int get unitPricePaise => CartLine.unitPrice(dish, variant: variant, addons: addons);

  int get totalPaise => unitPricePaise * quantity;

  CartLine toLine() => CartLine.fromChoice(dish, variant: variant, addons: addons, quantity: quantity);
}
