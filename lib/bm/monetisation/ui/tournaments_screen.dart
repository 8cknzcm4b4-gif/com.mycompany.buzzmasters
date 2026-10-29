/// Sponsored tournaments: list, detail with sponsor disclosure and standings.
///
/// Free entry only. No cash prizes, no wagers, no requirement to subscribe or
/// buy coins — enforced in the rules and again in the database function.
library;

import 'package:flutter/material.dart';

import '../../design/bm_theme.dart';
import '../../widgets/bm_button.dart';
import '../../widgets/bm_panel.dart';
import '../../widgets/studio_background.dart';
import '../bootstrap.dart';
import '../models.dart';
import '../rules.dart';

class SponsoredTournamentsScreen extends StatelessWidget {
  const SponsoredTournamentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final list = controller.tournaments;
        return StudioScaffold(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'TOURNAMENTS',
                      textAlign: TextAlign.center,
                      style: BmText.display(18, color: BmColors.gold),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Free entry. Sponsored events are labelled.',
                textAlign: TextAlign.center,
                style: BmText.body(12),
              ),
              const SizedBox(height: 12),
              BmStatusBanner(controller: controller),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                          controller.backend.isConfigured
                              ? 'No tournaments running right now.'
                              : 'Tournaments need the backend — not connected.',
                          textAlign: TextAlign.center,
                          style: BmText.body(13, color: BmColors.muted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final tournament = list[index];
                          return BmPanel(
                            color: BmColors.gold,
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        color: BmColors.gold
                                            .withValues(alpha: 0.2),
                                        border: Border.all(
                                            color: BmColors.gold),
                                      ),
                                      child: Text(
                                        tournament.sponsoredLabel.toUpperCase(),
                                        style: BmText.label(8,
                                            color: BmColors.gold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        tournament.sponsor.businessName,
                                        style: BmText.body(11,
                                            color: BmColors.muted),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(tournament.name,
                                    style: BmText.title(15)),
                                const SizedBox(height: 4),
                                Text(
                                  'Free entry · ${tournament.participantIds.length} entered',
                                  style:
                                      BmText.body(11, color: BmColors.muted),
                                ),
                                const SizedBox(height: 10),
                                BmButton(
                                  label: 'VIEW',
                                  height: 40,
                                  fontSize: 12,
                                  style: BmButtonStyle.gold,
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => TournamentDetailsScreen(
                                          tournament: tournament),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TournamentDetailsScreen extends StatelessWidget {
  const TournamentDetailsScreen({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final joined =
            tournament.participantIds.contains(controller.account.id);
        final block = tournamentEntryBlock(
          tournament: tournament,
          alreadyJoined: joined,
          now: DateTime.now(),
        );

        return StudioScaffold(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'TOURNAMENT',
                      textAlign: TextAlign.center,
                      style: BmText.display(18, color: BmColors.gold),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              BmStatusBanner(controller: controller),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sponsor disclosure is always visible.
                      BmPanel(
                        color: BmColors.gold,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.business_rounded,
                              color: BmColors.gold,
                              size: 30,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('SPONSORED BY',
                                      style: BmText.label(9,
                                          color: BmColors.gold)),
                                  Text(
                                    tournament.sponsor.businessName,
                                    style: BmText.title(14),
                                  ),
                                  if (tournament.sponsor.website.isNotEmpty)
                                    Text(
                                      tournament.sponsor.website,
                                      style: BmText.body(10,
                                          color: BmColors.cyan),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(tournament.name,
                          style: BmText.display(20, color: Colors.white)),
                      const SizedBox(height: 6),
                      Text(
                        '${tournament.startsAt.toLocal().toString().split(' ').first}'
                        '  →  '
                        '${tournament.endsAt.toLocal().toString().split(' ').first}',
                        style: BmText.body(12, color: BmColors.muted),
                      ),
                      const SizedBox(height: 14),
                      Text('ENTRY RULES', style: BmText.label(11)),
                      const SizedBox(height: 6),
                      BmPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tournament.entryRule,
                                style: BmText.body(12)),
                            const SizedBox(height: 8),
                            Text(
                              'Free entry. No cash prizes, deposits or wagers. '
                              'Subscribing or buying coins is never required.',
                              style: BmText.body(11, color: BmColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('VIRTUAL PRIZES', style: BmText.label(11)),
                      const SizedBox(height: 6),
                      if (tournament.prizes.isEmpty)
                        Text('Cosmetics only.',
                            style: BmText.body(12, color: BmColors.muted))
                      else
                        for (final prize in tournament.prizes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.emoji_events_rounded,
                                    size: 16, color: BmColors.gold),
                                const SizedBox(width: 8),
                                Text(prize, style: BmText.body(12)),
                              ],
                            ),
                          ),
                      const SizedBox(height: 14),
                      Text('RANKINGS', style: BmText.label(11)),
                      const SizedBox(height: 6),
                      FutureBuilder<List<TournamentScore>>(
                        future: controller.standings(tournament.id),
                        builder: (context, snapshot) {
                          final scores =
                              rankTournament(snapshot.data ?? const []);
                          if (scores.isEmpty) {
                            return Text(
                              'Standings appear once the first round is scored.',
                              style: BmText.body(11,
                                  color: BmColors.muted),
                            );
                          }
                          return Column(
                            children: [
                              for (var i = 0; i < scores.length; i++)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 28,
                                        child: Text('#${i + 1}',
                                            style: BmText.label(11,
                                                color: BmColors.gold)),
                                      ),
                                      Expanded(
                                        child: Text(
                                          scores[i].playerId,
                                          style: BmText.body(12),
                                        ),
                                      ),
                                      Text('${scores[i].correct} ✓',
                                          style: BmText.body(12,
                                              color: BmColors.green)),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BmButton(
                label: joined ? 'ENTERED' : 'ENTER FREE',
                style: joined ? BmButtonStyle.outline : BmButtonStyle.gold,
                onPressed: joined
                    ? null
                    : () async {
                        final error = await controller
                            .joinTournament(tournament);
                        if (error != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error)),
                          );
                        }
                      },
              ),
              if (block != null && !joined) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    block,
                    style: BmText.body(10, color: BmColors.muted),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
