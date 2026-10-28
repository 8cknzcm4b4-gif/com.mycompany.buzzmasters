import '/components/answer_button/answer_button_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'question_screen_widget.dart' show QuestionScreenWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:provider/provider.dart';

class QuestionScreenModel extends FlutterFlowModel<QuestionScreenWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for AnswerButton.
  late AnswerButtonModel answerButtonModel1;
  // Model for AnswerButton.
  late AnswerButtonModel answerButtonModel2;
  // Model for AnswerButton.
  late AnswerButtonModel answerButtonModel3;
  // Model for AnswerButton.
  late AnswerButtonModel answerButtonModel4;

  @override
  void initState(BuildContext context) {
    answerButtonModel1 = createModel(context, () => AnswerButtonModel());
    answerButtonModel2 = createModel(context, () => AnswerButtonModel());
    answerButtonModel3 = createModel(context, () => AnswerButtonModel());
    answerButtonModel4 = createModel(context, () => AnswerButtonModel());
  }

  @override
  void dispose() {
    answerButtonModel1.dispose();
    answerButtonModel2.dispose();
    answerButtonModel3.dispose();
    answerButtonModel4.dispose();
  }
}
