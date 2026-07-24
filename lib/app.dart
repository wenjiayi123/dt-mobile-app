import 'package:flutter/material.dart';

import 'package:dt_mobile_app/features/auth/presentation/auth_page.dart';
import 'package:dt_mobile_app/features/notifications/presentation/notification_page.dart';
import 'package:dt_mobile_app/features/settings/presentation/settings_page.dart';
import 'package:dt_mobile_app/shared/ui/port_twin_backdrop.dart';

const String routeHome = '/';
const String routeAuth = '/auth';
const String routeSettings = '/settings';
const String routeNotifications = '/notifications';

class DtMobileApp extends StatelessWidget {
  const DtMobileApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    final theme = _buildTheme();

    return MaterialApp(
      title: 'PortAI DT Mobile',
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);

        return MediaQuery(
          data: mediaQuery.copyWith(
            boldText: mediaQuery.boldText,
            textScaler: mediaQuery.textScaler,
          ),
          child: TooltipTheme(
            data: theme.tooltipTheme,
            child: Stack(
              children: [
                const Positioned.fill(child: PortTwinBackdrop()),
                Positioned.fill(child: child ?? const SizedBox.shrink()),
              ],
            ),
          ),
        );
      },
      initialRoute: routeHome,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case routeHome:
            return MaterialPageRoute<void>(
              builder: (_) => home,
              settings: settings,
            );
          case routeAuth:
            return MaterialPageRoute<void>(
              builder: (_) => const AuthPage(),
              settings: settings,
            );
          case routeSettings:
            return MaterialPageRoute<void>(
              builder: (_) => const SettingsPage(),
              settings: settings,
            );
          case routeNotifications:
            return MaterialPageRoute<void>(
              builder: (_) => const NotificationPage(),
              settings: settings,
            );
          default:
            return MaterialPageRoute<void>(
              builder: (_) => _UnknownRoutePage(routeName: settings.name),
              settings: settings,
            );
        }
      },
    );
  }

  ThemeData _buildTheme() {
    final scheme =
        const ColorScheme.dark(
          primary: Color(0xFF4DE4FF),
          onPrimary: Color(0xFF002431),
          secondary: Color(0xFF76F7C5),
          onSecondary: Color(0xFF00382B),
          error: Color(0xFFFF7889),
          onError: Color(0xFF41000A),
          surface: Color(0xFF0A1830),
          onSurface: Color(0xFFEAF4FF),
        ).copyWith(
          primaryContainer: const Color(0xFF123E66),
          onPrimaryContainer: const Color(0xFFD7F5FF),
          secondaryContainer: const Color(0xFF0B4944),
          onSecondaryContainer: const Color(0xFFB9FFE4),
          tertiary: const Color(0xFFB8A7FF),
          onTertiary: const Color(0xFF21144F),
          tertiaryContainer: const Color(0xFF332765),
          onTertiaryContainer: const Color(0xFFE8DEFF),
          errorContainer: const Color(0xFF632133),
          onErrorContainer: const Color(0xFFFFD9DE),
          surfaceContainerLowest: const Color(0xFF020711),
          surfaceContainerLow: const Color(0xFF071225),
          surfaceContainer: const Color(0xFF0A1830),
          surfaceContainerHigh: const Color(0xFF10213D),
          surfaceContainerHighest: const Color(0xFF172B49),
          onSurfaceVariant: const Color(0xFFA9BDD8),
          outline: const Color(0xFF57739B),
          outlineVariant: const Color(0xFF263F61),
          inverseSurface: const Color(0xFFDCE9FA),
          onInverseSurface: const Color(0xFF102038),
          inversePrimary: const Color(0xFF006681),
          shadow: Colors.black,
          scrim: Colors.black,
        );
    final base = ThemeData(
      colorScheme: scheme,
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'PortAISansSC',
    );

    const minimumTouchTarget = Size(64, 48);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    final roundedMd = BorderRadius.circular(16);
    final roundedLg = BorderRadius.circular(20);

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xF2071226),
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0xFF4DE4FF).withValues(alpha: 0.12),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
          letterSpacing: 0.2,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: const Color(0xF2071226),
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF123E66),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return base.textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            color: selected ? const Color(0xFFB8EFFF) : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? const Color(0xFF4DE4FF) : scheme.onSurfaceVariant,
          );
        }),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        showDuration: const Duration(seconds: 2),
        preferBelow: false,
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xF2172B49),
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: roundedMd,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.32)),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        clipBehavior: Clip.antiAlias,
        color: const Color(0xE60A1830),
        elevation: 2,
        shadowColor: const Color(0xFF22D3EE).withValues(alpha: 0.15),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: roundedLg,
          side: BorderSide(
            color: const Color(0xFF4DE4FF).withValues(alpha: 0.19),
          ),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: const Color(0xFA0A1830),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: roundedLg,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.26)),
        ),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: base.listTileTheme.copyWith(
        minLeadingWidth: 24,
        minVerticalPadding: 10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: roundedMd),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minimumTouchTarget,
          padding: buttonPadding,
          elevation: 0,
          backgroundColor: const Color(0xFF1769E0),
          foregroundColor: Colors.white,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: roundedMd),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minimumTouchTarget,
          padding: buttonPadding,
          foregroundColor: const Color(0xFFB8EFFF),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.46)),
          shape: RoundedRectangleBorder(borderRadius: roundedMd),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(56, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: roundedMd),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(44, 44)),
          padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.all(10)),
          foregroundColor: WidgetStatePropertyAll<Color>(
            scheme.onSurfaceVariant,
          ),
          overlayColor: WidgetStatePropertyAll<Color>(
            scheme.primary.withValues(alpha: 0.11),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: roundedMd),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.secondaryContainer,
        checkmarkColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: base.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        alignLabelWithHint: true,
        filled: true,
        fillColor: const Color(0xCC071225),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: roundedMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: roundedMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: roundedMd,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: const Color(0xFA071225),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: const Color(0xFA071225),
        modalBarrierColor: Colors.black.withValues(alpha: 0.68),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: Color(0x554DE4FF)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFA10213D),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: roundedMd,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.20)),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: scheme.primary,
        collapsedIconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        collapsedTextColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: roundedMd),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFF4DE4FF),
        linearTrackColor: Color(0xFF172B49),
        circularTrackColor: Color(0xFF172B49),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF123E66),
        foregroundColor: Color(0xFFB8EFFF),
        elevation: 4,
        focusElevation: 5,
        hoverElevation: 5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: 0.32)
              : scheme.surfaceContainerHighest;
        }),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          scheme.primary.withValues(alpha: 0.34),
        ),
        trackColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        radius: const Radius.circular(99),
      ),
    );
  }
}

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage({required this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('页面未找到')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    minHeight: constraints.maxHeight > 0
                        ? constraints.maxHeight - 32
                        : 0,
                  ),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text('当前路由不存在', style: textTheme.titleLarge),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            routeName == null || routeName!.isEmpty
                                ? '未提供路由名称。'
                                : '无法打开：$routeName',
                          ),
                          const SizedBox(height: 16),
                          Tooltip(
                            message: '返回首页并清空错误路由',
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  routeHome,
                                  (route) => false,
                                );
                              },
                              icon: const Icon(Icons.home_outlined),
                              label: const Text('返回首页'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
