import '/components/player_bubble/player_bubble_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'buzzer_round_widget.dart' show BuzzerRoundWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class BuzzerRoundModel extends FlutterFlowModel<BuzzerRoundWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for PlayerBubble.
  late PlayerBubbleModel playerBubbleModel1;
  // Model for PlayerBubble.
  late PlayerBubbleModel playerBubbleModel2;
  // Model for PlayerBubble.
  late PlayerBubbleModel playerBubbleModel3;
  // Model for PlayerBubble.
  late PlayerBubbleModel playerBubbleModel4;
  // Model for PlayerBubble.
  late PlayerBubbleModel playerBubbleModel5;

  @override
  void initState(BuildContext context) {
    playerBubbleModel1 = createModel(context, () => PlayerBubbleModel());
    playerBubbleModel2 = createModel(context, () => PlayerBubbleModel());
    playerBubbleModel3 = createModel(context, () => PlayerBubbleModel());
    playerBubbleModel4 = createModel(context, () => PlayerBubbleModel());
    playerBubbleModel5 = createModel(context, () => PlayerBubbleModel());
  }

  @override
  void dispose() {
    playerBubbleModel1.dispose();
    playerBubbleModel2.dispose();
    playerBubbleModel3.dispose();
    playerBubbleModel4.dispose();
    playerBubbleModel5.dispose();
  }
}
