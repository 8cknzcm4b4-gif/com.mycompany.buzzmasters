import '/components/button/button_widget.dart';
import '/components/rank_row/rank_row_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'leaderboard_widget.dart' show LeaderboardWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class LeaderboardModel extends FlutterFlowModel<LeaderboardWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for RankRow.
  late RankRowModel rankRowModel1;
  // Model for RankRow.
  late RankRowModel rankRowModel2;
  // Model for RankRow.
  late RankRowModel rankRowModel3;
  // Model for RankRow.
  late RankRowModel rankRowModel4;
  // Model for Button.
  late ButtonModel buttonModel;

  @override
  void initState(BuildContext context) {
    rankRowModel1 = createModel(context, () => RankRowModel());
    rankRowModel2 = createModel(context, () => RankRowModel());
    rankRowModel3 = createModel(context, () => RankRowModel());
    rankRowModel4 = createModel(context, () => RankRowModel());
    buttonModel = createModel(context, () => ButtonModel());
  }

  @override
  void dispose() {
    rankRowModel1.dispose();
    rankRowModel2.dispose();
    rankRowModel3.dispose();
    rankRowModel4.dispose();
    buttonModel.dispose();
  }
}
