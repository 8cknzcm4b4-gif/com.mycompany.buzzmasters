import '/components/button/button_widget.dart';
import '/components/player_avatar/player_avatar_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'game_lobby_widget.dart' show GameLobbyWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class GameLobbyModel extends FlutterFlowModel<GameLobbyWidget> {
  ///  State fields for stateful widgets in this page.

  // Model for PlayerAvatar.
  late PlayerAvatarModel playerAvatarModel1;
  // Model for PlayerAvatar.
  late PlayerAvatarModel playerAvatarModel2;
  // Model for PlayerAvatar.
  late PlayerAvatarModel playerAvatarModel3;
  // Model for PlayerAvatar.
  late PlayerAvatarModel playerAvatarModel4;
  // Model for PlayerAvatar.
  late PlayerAvatarModel playerAvatarModel5;
  // Model for Button.
  late ButtonModel buttonModel1;
  // Model for Button.
  late ButtonModel buttonModel2;

  @override
  void initState(BuildContext context) {
    playerAvatarModel1 = createModel(context, () => PlayerAvatarModel());
    playerAvatarModel2 = createModel(context, () => PlayerAvatarModel());
    playerAvatarModel3 = createModel(context, () => PlayerAvatarModel());
    playerAvatarModel4 = createModel(context, () => PlayerAvatarModel());
    playerAvatarModel5 = createModel(context, () => PlayerAvatarModel());
    buttonModel1 = createModel(context, () => ButtonModel());
    buttonModel2 = createModel(context, () => ButtonModel());
  }

  @override
  void dispose() {
    playerAvatarModel1.dispose();
    playerAvatarModel2.dispose();
    playerAvatarModel3.dispose();
    playerAvatarModel4.dispose();
    playerAvatarModel5.dispose();
    buttonModel1.dispose();
    buttonModel2.dispose();
  }
}
