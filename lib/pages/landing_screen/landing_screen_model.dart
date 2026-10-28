import '/components/action_card/action_card_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'dart:math' as math;
import 'landing_screen_widget.dart' show LandingScreenWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class LandingScreenModel extends FlutterFlowModel<LandingScreenWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for ActionCard.
  late ActionCardModel actionCardModel1;
  // Model for ActionCard.
  late ActionCardModel actionCardModel2;

  @override
  void initState(BuildContext context) {
    actionCardModel1 = createModel(context, () => ActionCardModel());
    actionCardModel2 = createModel(context, () => ActionCardModel());
  }

  @override
  void dispose() {
    actionCardModel1.dispose();
    actionCardModel2.dispose();
  }
}
