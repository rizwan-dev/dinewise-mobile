import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../data/menu.dart';
import '../data/menu_repository.dart';
import 'dish_card.dart';

/// The menu: search, a veg-only switch, section chips that stay on top and follow the scroll,
/// and photo-led dish rows.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key, this.initialSection});

  /// A section slug to open at (from the home page's tiles).
  final String? initialSection;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _chips = ScrollController();
  final _sectionKeys = <String, GlobalKey>{};
  final _chipKeys = <String, GlobalKey>{};
  String _query = '';
  bool _vegOnly = false;
  String? _active;
  String? _pendingJump;

  static const _chipBarHeight = 60.0;

  @override
  void initState() {
    super.initState();
    _pendingJump = widget.initialSection;
    _scroll.addListener(_trackActiveSection);
  }

  @override
  void didUpdateWidget(MenuScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialSection != null && widget.initialSection != old.initialSection) {
      _pendingJump = widget.initialSection;
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingJump());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _chips.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(Map<String, GlobalKey> map, String slug) => map.putIfAbsent(slug, GlobalKey.new);

  /// The scroll offset at which [box] sits just under the pinned chip bar.
  double? _offsetOf(RenderObject? box) {
    if (box == null || !box.attached || !_scroll.hasClients) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(box, 0).offset - _chipBarHeight;
  }

  void _trackActiveSection() {
    if (!_scroll.hasClients) return;
    final position = _scroll.offset;
    String? current;
    for (final entry in _sectionKeys.entries) {
      final offset = _offsetOf(entry.value.currentContext?.findRenderObject());
      if (offset != null && offset <= position + 24) current = entry.key;
    }
    current ??= _sectionKeys.keys.firstOrNull;
    if (current != _active) {
      setState(() => _active = current);
      final chip = _chipKeys[current]?.currentContext;
      if (chip != null) {
        Scrollable.ensureVisible(chip, alignment: 0.5, duration: const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> _jumpTo(String slug, {bool animate = true}) async {
    final offset = _offsetOf(_sectionKeys[slug]?.currentContext?.findRenderObject());
    if (offset == null) return;
    final target = offset.clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.removeListener(_trackActiveSection);
    setState(() => _active = slug);
    try {
      if (animate && !MediaQuery.disableAnimationsOf(context)) {
        await _scroll.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      } else {
        _scroll.jumpTo(target);
      }
    } finally {
      _scroll.addListener(_trackActiveSection);
    }
  }

  void _consumePendingJump() {
    final slug = _pendingJump;
    if (slug == null || !_scroll.hasClients) return;
    if (_sectionKeys[slug]?.currentContext == null) return;
    _pendingJump = null;
    _jumpTo(slug, animate: false);
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (menu) {
          AsyncValue(:final value?) => _buildMenu(context, value),
          AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(menuProvider)),
          _ => Column(
            children: [
              _Header(search: _search, vegOnly: _vegOnly, onQuery: (_) {}, onVegOnly: (_) {}),
              Expanded(child: SingleChildScrollView(child: const MenuSkeleton(rows: 6))),
            ],
          ),
        },
      ),
    );
  }

  Widget _buildMenu(BuildContext context, Menu menu) {
    final sections = menu.filter(query: _query, vegOnly: _vegOnly);
    // Drop keys of sections that are filtered out, so the chip tracking ignores them.
    _sectionKeys.removeWhere((slug, _) => !sections.any((s) => s.slug == slug));
    if (_pendingJump != null) WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingJump());

    return RefreshIndicator(
      onRefresh: () => ref.refresh(menuProvider.future),
      edgeOffset: 140,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              search: _search,
              vegOnly: _vegOnly,
              onQuery: (q) => setState(() => _query = q),
              onVegOnly: (v) => setState(() => _vegOnly = v),
            ),
          ),
          if (sections.isNotEmpty)
            SliverPersistentHeader(
              pinned: true,
              delegate: _ChipBar(
                height: _chipBarHeight,
                child: _SectionChips(
                  controller: _chips,
                  sections: sections,
                  active: _active ?? sections.first.slug,
                  keyFor: (slug) => _keyFor(_chipKeys, slug),
                  onTap: _jumpTo,
                ),
              ),
            ),
          if (sections.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView(
                icon: Icons.search_off_rounded,
                title: 'Nothing matches',
                message: _vegOnly && _query.isEmpty
                    ? 'No vegetarian dishes right now.'
                    : 'Try another word${_vegOnly ? ', or turn off Veg only' : ''}.',
                action: OutlinedButton(
                  onPressed: () {
                    _search.clear();
                    setState(() {
                      _query = '';
                      _vegOnly = false;
                    });
                  },
                  child: const Text('Show the whole menu'),
                ),
              ),
            )
          else
            // Built in one go (41 dishes) so every section can be scrolled to precisely.
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final section in sections) ...[
                    Padding(
                      key: _keyFor(_sectionKeys, section.slug),
                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 2),
                      child: Row(
                        children: [
                          Semantics(
                            header: true,
                            child: Text(section.name, style: context.text.headlineSmall),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${section.items.length}',
                            style: context.text.labelLarge!.copyWith(color: context.palette.subtle),
                          ),
                        ],
                      ),
                    ),
                    for (final (i, dish) in section.items.indexed) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      DishCard(dish: dish),
                    ],
                  ],
                  const SizedBox(height: 120),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.search, required this.vegOnly, required this.onQuery, required this.onVegOnly});

  final TextEditingController search;
  final bool vegOnly;
  final ValueChanged<String> onQuery;
  final ValueChanged<bool> onVegOnly;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text('Menu', style: context.text.displaySmall)),
              ),
              FilterChip(
                selected: vegOnly,
                onSelected: onVegOnly,
                avatar: Icon(Icons.eco_rounded, size: 18, color: vegOnly ? palette.success : palette.subtle),
                label: const Text('Veg only'),
                selectedColor: palette.successSoft,
                side: BorderSide(color: vegOnly ? palette.success : palette.hairline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder(
            valueListenable: search,
            builder: (context, value, _) => TextField(
              controller: search,
              onChanged: onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search dishes',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          search.clear();
                          onQuery('');
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipBar extends SliverPersistentHeaderDelegate {
  const _ChipBar({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: overlapsContent || shrinkOffset > 0 ? 1 : 0,
    shadowColor: Colors.black26,
    child: child,
  );

  @override
  bool shouldRebuild(_ChipBar old) => old.child != child || old.height != height;
}

class _SectionChips extends StatelessWidget {
  const _SectionChips({
    required this.controller,
    required this.sections,
    required this.active,
    required this.keyFor,
    required this.onTap,
  });

  final ScrollController controller;
  final List<MenuSection> sections;
  final String active;
  final GlobalKey Function(String slug) keyFor;
  final void Function(String slug) onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListView.separated(
      controller: controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final s = sections[i];
        final selected = s.slug == active;
        return ChoiceChip(
          key: keyFor(s.slug),
          label: Text(s.name),
          selected: selected,
          onSelected: (_) => onTap(s.slug),
          labelStyle: context.text.labelLarge!.copyWith(
            color: selected ? palette.accentOnSoft : null,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          side: BorderSide(color: selected ? palette.accent.withValues(alpha: 0.5) : palette.hairline),
        );
      },
    );
  }
}
