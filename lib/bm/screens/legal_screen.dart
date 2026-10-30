import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';

/// Support contact shown in the legal pages, from build configuration:
/// --dart-define=BM_SUPPORT_EMAIL=support@example.com
const kBmSupportEmail = String.fromEnvironment('BM_SUPPORT_EMAIL');

String get _contact => kBmSupportEmail.isEmpty
    ? 'through the support link on the Buzz Masters App Store page'
    : 'at $kBmSupportEmail';

enum LegalPage { privacy, terms }

/// In-app Privacy Policy and Terms of Use. The privacy text describes what
/// this build actually stores and sends; keep it in step with the code and
/// with docs/release-readiness.md.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.page});

  final LegalPage page;

  @override
  Widget build(BuildContext context) {
    final privacy = page == LegalPage.privacy;
    final sections = privacy ? _privacy() : _terms();
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      showFloor: false,
      child: Column(
        children: [
          ArenaHeader(
            title: privacy ? 'PRIVACY POLICY' : 'TERMS OF USE',
            subtitle: 'BUZZ MASTERS',
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: sections.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => BmPanel(
                color: BmColors.panelEdge,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sections[i].$1,
                        style: BmText.display(15, color: BmColors.cyan)),
                    const SizedBox(height: 6),
                    Text(sections[i].$2,
                        style:
                            BmText.body(12.5, color: const Color(0xFFD5DAF5))),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          BmButton(
            label: 'DONE',
            height: 48,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _privacy() => [
        (
          'ON YOUR DEVICE',
          'Your racing name and colour, race statistics, achievements, best '
              'time-trial runs and sound, music and haptic settings are stored '
              'on this device. You can erase them at any time in Settings → '
              'Account.',
        ),
        (
          'ONLINE PLAY',
          'When online play is available, we store a player id, your racing '
              'name and colour, a friend code, the races you join, your '
              'answers and results, your friends and race invitations, so '
              'races can be judged fairly and rankings shown. Other racers '
              'see your racing name and colour.',
        ),
        (
          'ACCOUNTS',
          'You can play as a guest. If you sign in with Apple, Google or an '
              'email link, we receive your account id and, where provided, '
              'your email address. We use them only to sign you in and to '
              'keep your progress.',
        ),
        (
          'PURCHASES & VIP',
          'Purchases are handled by Apple or Google. We never see your '
              'payment details. Our purchase partner RevenueCat confirms '
              'purchases to our server, which records what you own.',
        ),
        (
          'ADVERTISING',
          'Optional rewarded adverts are provided by Google AdMob. We do not '
              'ask to track you across other apps, so adverts are not '
              'personalised using that tracking. Google verifies completed '
              'adverts directly with our server before coins are granted.',
        ),
        (
          'DELETING YOUR DATA',
          'Settings → Account → Delete lets you permanently delete your '
              'account and everything stored about it, or erase the data on '
              'this device. Active subscriptions are cancelled in your App '
              'Store or Google Play settings.',
        ),
        (
          'CONTACT',
          'Questions about your data? Contact us $_contact.',
        ),
      ];

  List<(String, String)> _terms() => [
        (
          'THE GAME',
          'Buzz Masters is a trivia racing game. Practice Race and Time Trial '
              'work offline; online races need an internet connection.',
        ),
        (
          'FAIR PLAY',
          'Answers and results in online races are decided by our server. '
              'Do not attempt to interfere with races, other players or the '
              'service. We may remove accounts that do.',
        ),
        (
          'NAMES',
          'Racing names must not be offensive or impersonate others.',
        ),
        (
          'PURCHASES',
          'VIP is an optional auto-renewing subscription and is never needed '
              'to race. It renews until cancelled in your store settings. '
              'Cosmetic items have no effect on race results. Coins have no '
              'cash value.',
        ),
        (
          'CONTACT',
          'For help, contact us $_contact.',
        ),
      ];
}
