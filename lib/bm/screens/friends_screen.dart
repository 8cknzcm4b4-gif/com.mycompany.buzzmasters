import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../online/join_game_screen.dart';
import '../online/online_race_service.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';

/// Friends and race invitations. Friend lists and invites are server data,
/// so without the Buzz Masters server this explains that and points to the
/// code-based join flow, which works the moment a server is connected.
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key, this.showBack = true});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final online = OnlineRace.service.isConfigured;
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          ArenaHeader(
            title: 'FRIENDS',
            subtitle: 'INVITES & PRIVATE RACES',
            showBack: showBack,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: BmGradients.violet,
                      boxShadow: bmGlow(BmColors.violet, blur: 30),
                    ),
                    child: const Icon(Icons.people_alt_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(online ? 'NO FRIENDS YET' : 'FRIENDS NEED ONLINE PLAY',
                      textAlign: TextAlign.center, style: BmText.display(21)),
                  const SizedBox(height: 8),
                  Text(
                    online
                        ? 'Share a race code with friends to race together.'
                        : 'Friend lists, invitations and private races are '
                            'stored on the Buzz Masters server, which this '
                            'build is not connected to yet. Nothing is shown '
                            'rather than placeholder friends.',
                    textAlign: TextAlign.center,
                    style: BmText.body(13, color: BmColors.muted),
                  ),
                  const SizedBox(height: 22),
                  BmPanel(
                    color: BmColors.cyan,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.vpn_key_rounded,
                                color: BmColors.cyan),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('HAVE A RACE CODE?',
                                  style: BmText.label(11, color: Colors.white)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        BmButton(
                          label: 'JOIN WITH CODE',
                          icon: Icons.login_rounded,
                          style: BmButtonStyle.cyan,
                          height: 48,
                          fontSize: 13,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => const JoinGameScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
