import '/components/button/button_widget.dart';
import '/components/podium_spot/podium_spot_widget.dart';
import '/components/stat_row/stat_row_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'final_results_widget.dart' show FinalResultsWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

class FinalResultsModel extends FlutterFlowModel<FinalResultsWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for PodiumSpot.
  late PodiumSpotModel podiumSpotModel1;
  // Model for PodiumSpot.
  late PodiumSpotModel podiumSpotModel2;
  // Model for PodiumSpot.
  late PodiumSpotModel podiumSpotModel3;
  // Model for StatRow.
  late StatRowModel statRowModel1;
  // Model for StatRow.
  late StatRowModel statRowModel2;
  // Model for StatRow.
  late StatRowModel statRowModel3;
  // Model for StatRow.
  late StatRowModel statRowModel4;
  // Model for Button.
  late ButtonModel buttonModel1;
  // Model for Button.
  late ButtonModel buttonModel2;

  @override
  void initState(BuildContext context) {
    podiumSpotModel1 = createModel(context, () => PodiumSpotModel());
    podiumSpotModel2 = createModel(context, () => PodiumSpotModel());
    podiumSpotModel3 = createModel(context, () => PodiumSpotModel());
    statRowModel1 = createModel(context, () => StatRowModel());
    statRowModel2 = createModel(context, () => StatRowModel());
    statRowModel3 = createModel(context, () => StatRowModel());
    statRowModel4 = createModel(context, () => StatRowModel());
    buttonModel1 = createModel(context, () => ButtonModel());
    buttonModel2 = createModel(context, () => ButtonModel());
  }

  @override
  void dispose() {
    podiumSpotModel1.dispose();
    podiumSpotModel2.dispose();
    podiumSpotModel3.dispose();
    statRowModel1.dispose();
    statRowModel2.dispose();
    statRowModel3.dispose();
    statRowModel4.dispose();
    buttonModel1.dispose();
    buttonModel2.dispose();
  }
}
