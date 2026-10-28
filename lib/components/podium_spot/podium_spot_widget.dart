import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'podium_spot_model.dart';
export 'podium_spot_model.dart';

class PodiumSpotWidget extends StatefulWidget {
  const PodiumSpotWidget({
    super.key,
    String? avatarInitials,
    double? height,
    String? name,
    String? rank,
    String? score,
    Color? tint,
  })  : this.avatarInitials = avatarInitials ?? 'AX',
        this.height = height ?? 120.0,
        this.name = name ?? 'Alex',
        this.rank = rank ?? '2',
        this.score = score ?? '2,450 pts',
        this.tint = tint ?? const Color(0x00000000);

  final String avatarInitials;
  final double height;
  final String name;
  final String rank;
  final String score;
  final Color tint;

  @override
  State<PodiumSpotWidget> createState() => _PodiumSpotWidgetState();
}

class _PodiumSpotWidgetState extends State<PodiumSpotWidget> {
  late PodiumSpotModel _model;

  @override
  void setState(VoidCallback callback) {
    super.setState(callback);
    _model.onUpdate();
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PodiumSpotModel());
  }

  @override
  void dispose() {
    _model.maybeDispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56.0,
              height: 56.0,
              decoration: BoxDecoration(
                color: valueOrDefault<Color>(
                  widget!.tint,
                  FlutterFlowTheme.of(context).secondary,
                ),
                shape: BoxShape.circle,
              ),
              alignment: AlignmentDirectional(0.0, 0.0),
              child: Text(
                valueOrDefault<String>(
                  widget!.avatarInitials,
                  'AX',
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                style: FlutterFlowTheme.of(context).labelMedium.override(
                      font: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontStyle:
                            FlutterFlowTheme.of(context).labelMedium.fontStyle,
                      ),
                      color: FlutterFlowTheme.of(context).onPrimary,
                      fontSize: 21.28,
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w600,
                      fontStyle:
                          FlutterFlowTheme.of(context).labelMedium.fontStyle,
                      lineHeight: 1.2,
                    ),
                overflow: TextOverflow.clip,
              ),
            ),
            Text(
              valueOrDefault<String>(
                widget!.name,
                'Alex',
              ),
              style: FlutterFlowTheme.of(context).titleMedium.override(
                    font: GoogleFonts.urbanist(
                      fontWeight: FontWeight.bold,
                      fontStyle:
                          FlutterFlowTheme.of(context).titleMedium.fontStyle,
                    ),
                    color: FlutterFlowTheme.of(context).primaryText,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.bold,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleMedium.fontStyle,
                    lineHeight: 1.3,
                  ),
            ),
          ].divide(SizedBox(height: 4.0)),
        ),
        Container(
          width: 100.0,
          height: valueOrDefault<double>(
            widget!.height,
            120.0,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16.0),
              topRight: Radius.circular(16.0),
            ),
            shape: BoxShape.rectangle,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 2.0,
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).secondary,
                  shape: BoxShape.rectangle,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Container(
                  child: Container(
                    alignment: AlignmentDirectional(0.0, -1.0),
                    child: Text(
                      valueOrDefault<String>(
                        widget!.rank,
                        '2',
                      ),
                      style:
                          FlutterFlowTheme.of(context).headlineLarge.override(
                                font: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .headlineLarge
                                      .fontStyle,
                                ),
                                color: valueOrDefault<Color>(
                                  widget!.tint,
                                  FlutterFlowTheme.of(context).secondary,
                                ),
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w900,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .headlineLarge
                                    .fontStyle,
                                lineHeight: 1.2,
                              ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          valueOrDefault<String>(
            widget!.score,
            '2,450 pts',
          ),
          style: FlutterFlowTheme.of(context).labelLarge.override(
                font: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontStyle: FlutterFlowTheme.of(context).labelLarge.fontStyle,
                ),
                color: valueOrDefault<Color>(
                  widget!.tint,
                  FlutterFlowTheme.of(context).secondary,
                ),
                letterSpacing: 0.0,
                fontWeight: FontWeight.bold,
                fontStyle: FlutterFlowTheme.of(context).labelLarge.fontStyle,
                lineHeight: 1.2,
              ),
        ),
      ].divide(SizedBox(height: 16.0)),
    );
  }
}
