import '/components/button/button_widget.dart';
import '/components/category_card/category_card_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'category_selection_widget.dart' show CategorySelectionWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class CategorySelectionModel extends FlutterFlowModel<CategorySelectionWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for CategoryCard.
  late CategoryCardModel categoryCardModel1;
  // Model for CategoryCard.
  late CategoryCardModel categoryCardModel2;
  // Model for CategoryCard.
  late CategoryCardModel categoryCardModel3;
  // Model for CategoryCard.
  late CategoryCardModel categoryCardModel4;
  // Model for CategoryCard.
  late CategoryCardModel categoryCardModel5;
  // Model for CategoryCard.
  late CategoryCardModel categoryCardModel6;
  // Model for Button.
  late ButtonModel buttonModel;

  @override
  void initState(BuildContext context) {
    categoryCardModel1 = createModel(context, () => CategoryCardModel());
    categoryCardModel2 = createModel(context, () => CategoryCardModel());
    categoryCardModel3 = createModel(context, () => CategoryCardModel());
    categoryCardModel4 = createModel(context, () => CategoryCardModel());
    categoryCardModel5 = createModel(context, () => CategoryCardModel());
    categoryCardModel6 = createModel(context, () => CategoryCardModel());
    buttonModel = createModel(context, () => ButtonModel());
  }

  @override
  void dispose() {
    categoryCardModel1.dispose();
    categoryCardModel2.dispose();
    categoryCardModel3.dispose();
    categoryCardModel4.dispose();
    categoryCardModel5.dispose();
    categoryCardModel6.dispose();
    buttonModel.dispose();
  }
}
