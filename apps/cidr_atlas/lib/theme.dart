// CIDR Atlas
// Light and dark themes and the semantic colour palette.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Semantic colours of the CIDR Atlas workspace, attached to [ThemeData] as a
/// theme extension so every widget and painter reads the active palette.
@immutable
class AtlasPalette extends ThemeExtension<AtlasPalette> {
  const AtlasPalette({
    required this.background,
    required this.surface,
    required this.sidebar,
    required this.sidebarCard,
    required this.detailsPanel,
    required this.tableHeader,
    required this.inputFill,
    required this.border,
    required this.rowDivider,
    required this.text,
    required this.textSecondary,
    required this.textFaint,
    required this.textSelected,
    required this.outlinedForeground,
    required this.accent,
    required this.accentStrong,
    required this.onAccentStrong,
    required this.brandTile,
    required this.emptyTile,
    required this.navSelected,
    required this.rowSelected,
    required this.candidateSelected,
    required this.success,
    required this.reserved,
    required this.warning,
    required this.danger,
    required this.plannerError,
    required this.conflictBadgeBackground,
    required this.conflictBadgeText,
    required this.barrier,
    required this.mapFree,
    required this.mapBlocked,
    required this.mapCandidate,
    required this.mapOutline,
    required this.mapFreeOpacity,
    required this.mapBlockedOpacity,
  });

  /// The original CIDR Atlas dark palette.
  static const dark = AtlasPalette(
    background: Color(0xff10151f),
    surface: Color(0xff171e2b),
    sidebar: Color(0xff131a26),
    sidebarCard: Color(0xff1b2535),
    detailsPanel: Color(0xff141c28),
    tableHeader: Color(0xff141b28),
    inputFill: Color(0xff111824),
    border: Color(0xff293244),
    rowDivider: Color(0xff232c3d),
    text: Color(0xffe4eaf5),
    textSecondary: Color(0xff98a6bc),
    textFaint: Color(0xff68778e),
    textSelected: Color(0xffffffff),
    outlinedForeground: Color(0xffd6e0f2),
    accent: Color(0xff8fafff),
    accentStrong: Color(0xffb2c7ff),
    onAccentStrong: Color(0xff12203b),
    brandTile: Color(0xff2b3f67),
    emptyTile: Color(0xff1d2b42),
    navSelected: Color(0xff24334e),
    rowSelected: Color(0xff23334e),
    candidateSelected: Color(0xff263958),
    success: Color(0xff77d8b4),
    reserved: Color(0xffdbc18b),
    warning: Color(0xffe6c583),
    danger: Color(0xffff8c8c),
    plannerError: Color(0xffffb4ab),
    conflictBadgeBackground: Color(0xff5d343a),
    conflictBadgeText: Color(0xffffa9a9),
    barrier: Color(0x9910151f),
    mapFree: Color(0xff77d8b4),
    mapBlocked: Color(0xffdbc18b),
    mapCandidate: Color(0xff8fafff),
    mapOutline: Color(0xff293244),
    mapFreeOpacity: 0.45,
    mapBlockedOpacity: 0.35,
  );

  /// The light palette; text colours meet WCAG AA on its surfaces.
  static const light = AtlasPalette(
    background: Color(0xfff3f5f9),
    surface: Color(0xffffffff),
    sidebar: Color(0xffebeef4),
    sidebarCard: Color(0xffffffff),
    detailsPanel: Color(0xfff8f9fc),
    tableHeader: Color(0xfff1f3f7),
    inputFill: Color(0xffffffff),
    border: Color(0xffd3d9e3),
    rowDivider: Color(0xffe5e9ef),
    text: Color(0xff1a2233),
    textSecondary: Color(0xff4f5c70),
    textFaint: Color(0xff5b677a),
    textSelected: Color(0xff111827),
    outlinedForeground: Color(0xff27324a),
    accent: Color(0xff2c53c4),
    accentStrong: Color(0xff2c53c4),
    onAccentStrong: Color(0xffffffff),
    brandTile: Color(0xffdce5fb),
    emptyTile: Color(0xffdce5fb),
    navSelected: Color(0xffdce5fb),
    rowSelected: Color(0xffe2e9fb),
    candidateSelected: Color(0xffe2e9fb),
    success: Color(0xff166b4b),
    reserved: Color(0xff7a5a0d),
    warning: Color(0xff7a5a0d),
    danger: Color(0xffb8323a),
    plannerError: Color(0xffb3261e),
    conflictBadgeBackground: Color(0xfffbe1e1),
    conflictBadgeText: Color(0xff9b2228),
    barrier: Color(0x661a2233),
    mapFree: Color(0xff1a7754),
    mapBlocked: Color(0xff85620f),
    mapCandidate: Color(0xff2c53c4),
    mapOutline: Color(0xff7d8899),
    // Stronger fills keep free and blocked space at 3:1 against the light
    // surface (WCAG 1.4.11 non-text contrast).
    mapFreeOpacity: 0.7,
    mapBlockedOpacity: 0.7,
  );

  /// The palette of the nearest [Theme], or [dark] outside a CIDR Atlas theme.
  static AtlasPalette of(BuildContext context) =>
      Theme.of(context).extension<AtlasPalette>() ?? dark;

  /// Window and scaffold background.
  final Color background;

  /// Cards, panels and dialogs.
  final Color surface;

  /// Workspace navigation sidebar.
  final Color sidebar;

  /// Card inside the sidebar.
  final Color sidebarCard;

  /// Prefix details side panel.
  final Color detailsPanel;

  /// Inventory table header band.
  final Color tableHeader;

  /// Text field fill.
  final Color inputFill;

  /// Panel, field and divider borders.
  final Color border;

  /// Separator between table rows.
  final Color rowDivider;

  /// Primary text.
  final Color text;

  /// Secondary text, labels and icons.
  final Color textSecondary;

  /// Least prominent text such as the version label.
  final Color textFaint;

  /// Text of the selected navigation item.
  final Color textSelected;

  /// Outlined button text and icons.
  final Color outlinedForeground;

  /// Accent for links, CIDRs, icons and the planner candidate.
  final Color accent;

  /// Filled button background and brand icon.
  final Color accentStrong;

  /// Text on [accentStrong].
  final Color onAccentStrong;

  /// Background of the sidebar brand mark.
  final Color brandTile;

  /// Background of the empty-inventory illustration.
  final Color emptyTile;

  /// Selected navigation item.
  final Color navSelected;

  /// Selected inventory row.
  final Color rowSelected;

  /// Selected planner candidate card.
  final Color candidateSelected;

  /// Active, free and healthy states as text or icon.
  final Color success;

  /// Reserved and blocked states as text or icon.
  final Color reserved;

  /// Informational message panels.
  final Color warning;

  /// Conflicts, errors and destructive actions.
  final Color danger;

  /// Planner input errors.
  final Color plannerError;

  /// Background of the sidebar conflict count.
  final Color conflictBadgeBackground;

  /// Text of the sidebar conflict count.
  final Color conflictBadgeText;

  /// Modal barrier behind the discovery progress panel.
  final Color barrier;

  /// Planner map fill for free space.
  final Color mapFree;

  /// Planner map fill and hatching for blocked space.
  final Color mapBlocked;

  /// Planner map outline of the selected candidate.
  final Color mapCandidate;

  /// Planner map frame.
  final Color mapOutline;

  /// Fill opacity of free space on the planner map.
  final double mapFreeOpacity;

  /// Fill opacity of blocked space on the planner map.
  final double mapBlockedOpacity;

  /// Every colour by name, for completeness and contrast checks.
  Map<String, Color> get colors => {
    'background': background,
    'surface': surface,
    'sidebar': sidebar,
    'sidebarCard': sidebarCard,
    'detailsPanel': detailsPanel,
    'tableHeader': tableHeader,
    'inputFill': inputFill,
    'border': border,
    'rowDivider': rowDivider,
    'text': text,
    'textSecondary': textSecondary,
    'textFaint': textFaint,
    'textSelected': textSelected,
    'outlinedForeground': outlinedForeground,
    'accent': accent,
    'accentStrong': accentStrong,
    'onAccentStrong': onAccentStrong,
    'brandTile': brandTile,
    'emptyTile': emptyTile,
    'navSelected': navSelected,
    'rowSelected': rowSelected,
    'candidateSelected': candidateSelected,
    'success': success,
    'reserved': reserved,
    'warning': warning,
    'danger': danger,
    'plannerError': plannerError,
    'conflictBadgeBackground': conflictBadgeBackground,
    'conflictBadgeText': conflictBadgeText,
    'barrier': barrier,
    'mapFree': mapFree,
    'mapBlocked': mapBlocked,
    'mapCandidate': mapCandidate,
    'mapOutline': mapOutline,
  };

  @override
  AtlasPalette copyWith({
    Color? background,
    Color? surface,
    Color? sidebar,
    Color? sidebarCard,
    Color? detailsPanel,
    Color? tableHeader,
    Color? inputFill,
    Color? border,
    Color? rowDivider,
    Color? text,
    Color? textSecondary,
    Color? textFaint,
    Color? textSelected,
    Color? outlinedForeground,
    Color? accent,
    Color? accentStrong,
    Color? onAccentStrong,
    Color? brandTile,
    Color? emptyTile,
    Color? navSelected,
    Color? rowSelected,
    Color? candidateSelected,
    Color? success,
    Color? reserved,
    Color? warning,
    Color? danger,
    Color? plannerError,
    Color? conflictBadgeBackground,
    Color? conflictBadgeText,
    Color? barrier,
    Color? mapFree,
    Color? mapBlocked,
    Color? mapCandidate,
    Color? mapOutline,
    double? mapFreeOpacity,
    double? mapBlockedOpacity,
  }) => AtlasPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    sidebar: sidebar ?? this.sidebar,
    sidebarCard: sidebarCard ?? this.sidebarCard,
    detailsPanel: detailsPanel ?? this.detailsPanel,
    tableHeader: tableHeader ?? this.tableHeader,
    inputFill: inputFill ?? this.inputFill,
    border: border ?? this.border,
    rowDivider: rowDivider ?? this.rowDivider,
    text: text ?? this.text,
    textSecondary: textSecondary ?? this.textSecondary,
    textFaint: textFaint ?? this.textFaint,
    textSelected: textSelected ?? this.textSelected,
    outlinedForeground: outlinedForeground ?? this.outlinedForeground,
    accent: accent ?? this.accent,
    accentStrong: accentStrong ?? this.accentStrong,
    onAccentStrong: onAccentStrong ?? this.onAccentStrong,
    brandTile: brandTile ?? this.brandTile,
    emptyTile: emptyTile ?? this.emptyTile,
    navSelected: navSelected ?? this.navSelected,
    rowSelected: rowSelected ?? this.rowSelected,
    candidateSelected: candidateSelected ?? this.candidateSelected,
    success: success ?? this.success,
    reserved: reserved ?? this.reserved,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    plannerError: plannerError ?? this.plannerError,
    conflictBadgeBackground:
        conflictBadgeBackground ?? this.conflictBadgeBackground,
    conflictBadgeText: conflictBadgeText ?? this.conflictBadgeText,
    barrier: barrier ?? this.barrier,
    mapFree: mapFree ?? this.mapFree,
    mapBlocked: mapBlocked ?? this.mapBlocked,
    mapCandidate: mapCandidate ?? this.mapCandidate,
    mapOutline: mapOutline ?? this.mapOutline,
    mapFreeOpacity: mapFreeOpacity ?? this.mapFreeOpacity,
    mapBlockedOpacity: mapBlockedOpacity ?? this.mapBlockedOpacity,
  );

  @override
  AtlasPalette lerp(covariant AtlasPalette? other, double t) {
    if (other == null) return this;
    return AtlasPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarCard: Color.lerp(sidebarCard, other.sidebarCard, t)!,
      detailsPanel: Color.lerp(detailsPanel, other.detailsPanel, t)!,
      tableHeader: Color.lerp(tableHeader, other.tableHeader, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      border: Color.lerp(border, other.border, t)!,
      rowDivider: Color.lerp(rowDivider, other.rowDivider, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      textSelected: Color.lerp(textSelected, other.textSelected, t)!,
      outlinedForeground: Color.lerp(
        outlinedForeground,
        other.outlinedForeground,
        t,
      )!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentStrong: Color.lerp(accentStrong, other.accentStrong, t)!,
      onAccentStrong: Color.lerp(onAccentStrong, other.onAccentStrong, t)!,
      brandTile: Color.lerp(brandTile, other.brandTile, t)!,
      emptyTile: Color.lerp(emptyTile, other.emptyTile, t)!,
      navSelected: Color.lerp(navSelected, other.navSelected, t)!,
      rowSelected: Color.lerp(rowSelected, other.rowSelected, t)!,
      candidateSelected: Color.lerp(
        candidateSelected,
        other.candidateSelected,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      reserved: Color.lerp(reserved, other.reserved, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      plannerError: Color.lerp(plannerError, other.plannerError, t)!,
      conflictBadgeBackground: Color.lerp(
        conflictBadgeBackground,
        other.conflictBadgeBackground,
        t,
      )!,
      conflictBadgeText: Color.lerp(
        conflictBadgeText,
        other.conflictBadgeText,
        t,
      )!,
      barrier: Color.lerp(barrier, other.barrier, t)!,
      mapFree: Color.lerp(mapFree, other.mapFree, t)!,
      mapBlocked: Color.lerp(mapBlocked, other.mapBlocked, t)!,
      mapCandidate: Color.lerp(mapCandidate, other.mapCandidate, t)!,
      mapOutline: Color.lerp(mapOutline, other.mapOutline, t)!,
      mapFreeOpacity: lerpDouble(mapFreeOpacity, other.mapFreeOpacity, t)!,
      mapBlockedOpacity: lerpDouble(
        mapBlockedOpacity,
        other.mapBlockedOpacity,
        t,
      )!,
    );
  }
}

/// Shorthand for [AtlasPalette.of].
extension AtlasPaletteContext on BuildContext {
  AtlasPalette get palette => AtlasPalette.of(this);
}

/// Builds the CIDR Atlas theme for [brightness]: the dark theme reproduces
/// the original look, the light theme applies the same layout to
/// [AtlasPalette.light].
ThemeData atlasTheme(Brightness brightness) {
  final p = brightness == Brightness.dark
      ? AtlasPalette.dark
      : AtlasPalette.light;
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: p.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
      surface: p.surface,
    ),
    fontFamily: 'Arial',
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontSize: 14, color: p.text),
      bodySmall: TextStyle(color: p.textSecondary),
    ),
    dividerColor: p.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.inputFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: p.border),
      ),
      labelStyle: TextStyle(color: p.textSecondary, fontSize: 13),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accentStrong,
        foregroundColor: p.onAccentStrong,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.outlinedForeground,
        side: BorderSide(color: p.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
    extensions: [p],
  );
}
