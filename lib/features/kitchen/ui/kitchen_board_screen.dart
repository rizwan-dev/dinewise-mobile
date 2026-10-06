import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../data/board.dart';
import '../data/kitchen_repository.dart';
import 'ticket_card.dart';

/// The kitchen board: New, Cooking, Ready and Out, live. Columns side by side on a tablet in
/// landscape, tabs on a phone.
class KitchenBoardScreen extends ConsumerWidget {
  const KitchenBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(boardProvider);
    final live = ref.watch(kitchenLiveProvider);
    final staff = ref.watch(staffSessionProvider)?.staff;
    final sound = ref.watch(kitchenSoundProvider);
    final now = ref.watch(kitchenClockProvider).value ?? ref.read(clockProvider)();

    ref.listen(newOrderSignalProvider, (_, _) {
      HapticFeedback.heavyImpact();
      if (ref.read(kitchenSoundProvider)) SystemSound.play(SystemSoundType.alert);
      showMessage(context, 'New order on the board');
    });

    final wide = MediaQuery.sizeOf(context).width >= 900;

    final content = switch (board) {
      AsyncValue(:final value?) => wide ? _Columns(board: value, now: now) : _Tabs(board: value, now: now),
      AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(boardProvider)),
      _ => const _BoardSkeleton(),
    };

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kitchen', style: context.text.titleLarge),
                  if (staff != null)
                    Text('${staff.name} · ${staff.role.label}', style: context.text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            LiveIndicator(status: live),
          ],
        ),
        actions: [
          IconButton(
            tooltip: sound ? 'Mute new-order chime' : 'Turn on new-order chime',
            onPressed: () => ref.read(kitchenSoundProvider.notifier).toggle(),
            icon: Icon(sound ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
          ),
          IconButton(
            tooltip: 'Menu availability',
            onPressed: () => context.push(Routes.kitchenMenu),
            icon: const Icon(Icons.no_meals_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              if (value == 'out') {
                await ref.read(staffAuthProvider).signOut();
              } else if (value == 'customer') {
                context.go(Routes.home);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'customer', child: Text('Back to ordering')),
              PopupMenuItem(value: 'out', child: Text('Sign out of kitchen')),
            ],
          ),
        ],
      ),
      body: content,
    );
  }
}

class _Tabs extends ConsumerWidget {
  const _Tabs({required this.board, required this.now});

  final Board board;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasLater = board.later.isNotEmpty;
    return DefaultTabController(
      length: BoardColumn.values.length + (hasLater ? 1 : 0),
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final c in BoardColumn.values) Tab(text: '${c.label} · ${board.column(c).length}'),
              if (hasLater) Tab(text: 'Later · ${board.later.length}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final c in BoardColumn.values)
                  _TicketList(
                    tickets: board.column(c),
                    now: now,
                    reasons: board.rejectReasons,
                    empty: _emptyText(c),
                  ),
                if (hasLater)
                  _TicketList(
                    tickets: board.later,
                    now: now,
                    reasons: board.rejectReasons,
                    empty: 'Nothing scheduled.',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _emptyText(BoardColumn c) => switch (c) {
  BoardColumn.newOrders => 'No new orders. They appear here the moment they are placed.',
  BoardColumn.cooking => 'Nothing on the stove.',
  BoardColumn.ready => 'Nothing waiting to go out.',
  BoardColumn.out => 'No riders out.',
};

class _Columns extends StatelessWidget {
  const _Columns({required this.board, required this.now});

  final Board board;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        if (board.later.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              child: ExpansionTile(
                shape: const Border(),
                leading: const Icon(Icons.event_outlined),
                title: Text('Scheduled for later · ${board.later.length}', style: context.text.titleMedium),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  SizedBox(
                    height: 330,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: board.later.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => SizedBox(
                        width: 320,
                        child: SingleChildScrollView(
                          child: TicketCard(
                            ticket: board.later[i],
                            now: now,
                            rejectReasons: board.rejectReasons,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in BoardColumn.values)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      c.label,
                                      style: context.text.titleLarge,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: palette.card,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text('${board.column(c).length}', style: context.text.labelLarge),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _TicketList(
                              tickets: board.column(c),
                              now: now,
                              reasons: board.rejectReasons,
                              empty: _emptyText(c),
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TicketList extends ConsumerWidget {
  const _TicketList({
    required this.tickets,
    required this.now,
    required this.reasons,
    required this.empty,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 32),
  });

  final List<Ticket> tickets;
  final DateTime now;
  final List<String> reasons;
  final String empty;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => refreshOrSay(context, () async {
        final error = await ref.read(boardProvider.notifier).refreshQuietly();
        if (error != null) throw error;
        return null;
      }),
      child: tickets.isEmpty
          ? ListView(
              padding: padding,
              children: [
                const SizedBox(height: 40),
                Icon(Icons.check_circle_outline_rounded, size: 40, color: context.palette.subtle),
                const SizedBox(height: 12),
                Text(
                  empty,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium!.copyWith(color: context.palette.muted),
                ),
              ],
            )
          : ListView.separated(
              padding: padding,
              itemCount: tickets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => TicketCard(
                key: ValueKey(tickets[i].code),
                ticket: tickets[i],
                now: now,
                rejectReasons: reasons,
              ),
            ),
    );
  }
}

class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Skeleton(
      child: Column(
        children: [
          Bone(height: 40, radius: 12),
          SizedBox(height: 16),
          Bone(height: 220, radius: 20),
          SizedBox(height: 12),
          Bone(height: 220, radius: 20),
        ],
      ),
    ),
  );
}
