import '/components/button/button_widget.dart';
import '/components/podium_spot/podium_spot_widget.dart';
import '/components/stat_row/stat_row_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'final_results_model.dart';
export 'final_results_model.dart';

class FinalResultsWidget extends StatefulWidget {
  const FinalResultsWidget({super.key});

  static String routeName = 'FinalResults';
  static String routePath = '/finalResults';

  @override
  State<FinalResultsWidget> createState() => _FinalResultsWidgetState();
}

class _FinalResultsWidgetState extends State<FinalResultsWidget> {
  late FinalResultsModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => FinalResultsModel());
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        body: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 220.0,
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Container(
                  child: Container(
                    alignment: AlignmentDirectional(0.0, 0.0),
                    child: Stack(
                      alignment: AlignmentDirectional(0.0, 0.0),
                      children: [
                        Opacity(
                          opacity: 0.6,
                          child: Lottie.network(
                            'https://dimg.dreamflow.cloud/v1/lottie/confetti+explosion',
                            width: 100.0,
                            height: 100.0,
                            fit: BoxFit.cover,
                            animate: true,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'MATCH OVER',
                              style: FlutterFlowTheme.of(context)
                                  .labelLarge
                                  .override(
                                    font: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .labelLarge
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context)
                                        .onBackground,
                                    letterSpacing: 0.0,
                                    fontWeight: FontWeight.w900,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelLarge
                                        .fontStyle,
                                    lineHeight: 1.2,
                                  ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 20.0,
                                    color:
                                        FlutterFlowTheme.of(context).secondary,
                                    offset: Offset(
                                      0.0,
                                      0.0,
                                    ),
                                    spreadRadius: 0.0,
                                  )
                                ],
                                shape: BoxShape.rectangle,
                              ),
                              child: Text(
                                'Winner!',
                                style: FlutterFlowTheme.of(context)
                                    .headlineLarge
                                    .override(
                                      font: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w900,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .headlineLarge
                                            .fontStyle,
                                      ),
                                      color: FlutterFlowTheme.of(context)
                                          .primaryText,
                                      fontSize: 48.0,
                                      letterSpacing: 0.0,
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .headlineLarge
                                          .fontStyle,
                                      lineHeight: 1.2,
                                    ),
                              ),
                            ),
                            Text(
                              'Room: #BZZ77',
                              style: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .override(
                                    font: GoogleFonts.urbanist(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryText,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .fontStyle,
                                    lineHeight: 1.5,
                                  ),
                            ),
                          ].divide(SizedBox(height: 8.0)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              height: 280.0,
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(24.0, 0.0, 24.0, 0.0),
                child: Container(
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        height: 120.0,
                        child: wrapWithModel(
                          model: _model.podiumSpotModel1,
                          updateCallback: () => safeSetState(() {}),
                          child: PodiumSpotWidget(
                            avatarInitials: 'AX',
                            height: 120.0,
                            name: 'Alex',
                            rank: '2',
                            score: '2,450 pts',
                            tint: FlutterFlowTheme.of(context).secondary,
                          ),
                        ),
                      ),
                      Container(
                        height: 180.0,
                        child: wrapWithModel(
                          model: _model.podiumSpotModel2,
                          updateCallback: () => safeSetState(() {}),
                          child: PodiumSpotWidget(
                            avatarInitials: 'JD',
                            height: 180.0,
                            name: 'Jordan',
                            rank: '1',
                            score: '3,100 pts',
                            tint: FlutterFlowTheme.of(context).primary,
                          ),
                        ),
                      ),
                      Container(
                        height: 90.0,
                        child: wrapWithModel(
                          model: _model.podiumSpotModel3,
                          updateCallback: () => safeSetState(() {}),
                          child: PodiumSpotWidget(
                            avatarInitials: 'RY',
                            height: 90.0,
                            name: 'Riley',
                            rank: '3',
                            score: '1,820 pts',
                            tint: FlutterFlowTheme.of(context).success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Container(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Your Performance',
                                style: FlutterFlowTheme.of(context)
                                    .titleLarge
                                    .override(
                                      font: GoogleFonts.urbanist(
                                        fontWeight: FontWeight.bold,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleLarge
                                            .fontStyle,
                                      ),
                                      color: FlutterFlowTheme.of(context)
                                          .primaryText,
                                      letterSpacing: 0.0,
                                      fontWeight: FontWeight.bold,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleLarge
                                          .fontStyle,
                                      lineHeight: 1.3,
                                    ),
                              ),
                              wrapWithModel(
                                model: _model.statRowModel1,
                                updateCallback: () => safeSetState(() {}),
                                child: StatRowWidget(
                                  accent: FlutterFlowTheme.of(context).success,
                                  icon: Icon(
                                    Icons.track_changes_rounded,
                                    color: FlutterFlowTheme.of(context).success,
                                    size: 20.0,
                                  ),
                                  label: 'Accuracy',
                                  value: '94%',
                                ),
                              ),
                              wrapWithModel(
                                model: _model.statRowModel2,
                                updateCallback: () => safeSetState(() {}),
                                child: StatRowWidget(
                                  accent: FlutterFlowTheme.of(context).primary,
                                  icon: Icon(
                                    Icons.speed_rounded,
                                    color: FlutterFlowTheme.of(context).success,
                                    size: 20.0,
                                  ),
                                  label: 'Fastest Response',
                                  value: '0.42s',
                                ),
                              ),
                              wrapWithModel(
                                model: _model.statRowModel3,
                                updateCallback: () => safeSetState(() {}),
                                child: StatRowWidget(
                                  accent: FlutterFlowTheme.of(context).warning,
                                  icon: Icon(
                                    Icons.workspace_premium_rounded,
                                    color: FlutterFlowTheme.of(context).success,
                                    size: 20.0,
                                  ),
                                  label: 'Longest Streak',
                                  value: '12 Correct',
                                ),
                              ),
                              wrapWithModel(
                                model: _model.statRowModel4,
                                updateCallback: () => safeSetState(() {}),
                                child: StatRowWidget(
                                  accent: FlutterFlowTheme.of(context).info,
                                  icon: Icon(
                                    Icons.timer_rounded,
                                    color: FlutterFlowTheme.of(context).success,
                                    size: 20.0,
                                  ),
                                  label: 'Total Match Time',
                                  value: '4m 12s',
                                ),
                              ),
                            ].divide(SizedBox(height: 16.0)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: FlutterFlowTheme.of(context).secondaryBackground,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32.0),
                  topRight: Radius.circular(32.0),
                ),
                shape: BoxShape.rectangle,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 1.0,
                    decoration: BoxDecoration(
                      color: FlutterFlowTheme.of(context).alternate,
                      shape: BoxShape.rectangle,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Container(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          InkWell(
                            splashColor: Colors.transparent,
                            focusColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            onTap: () async {
                              context.goNamed(GameLobbyWidget.routeName);
                            },
                            child: wrapWithModel(
                              model: _model.buttonModel1,
                              updateCallback: () => safeSetState(() {}),
                              child: ButtonWidget(
                                icon: Icon(
                                  Icons.replay_rounded,
                                  color:
                                      FlutterFlowTheme.of(context).primaryText,
                                  size: 24.0,
                                ),
                                iconPresent: true,
                                iconEndPresent: false,
                                content: 'Play Again',
                                variant: 'primary',
                                size: 'large',
                                fullWidth: true,
                                loading: false,
                                disabled: false,
                              ),
                            ),
                          ),
                          InkWell(
                            splashColor: Colors.transparent,
                            focusColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            onTap: () async {
                              context.goNamed(LandingScreenWidget.routeName);
                            },
                            child: wrapWithModel(
                              model: _model.buttonModel2,
                              updateCallback: () => safeSetState(() {}),
                              child: ButtonWidget(
                                iconPresent: false,
                                iconEndPresent: false,
                                content: 'Back to Menu',
                                variant: 'ghost',
                                size: 'medium',
                                fullWidth: true,
                                loading: false,
                                disabled: false,
                              ),
                            ),
                          ),
                        ].divide(SizedBox(height: 16.0)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
