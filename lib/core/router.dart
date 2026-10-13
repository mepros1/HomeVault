import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/items/item_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/report/report_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/capture/capture_screen.dart';
import '../features/review/review_screen.dart';
import '../features/rooms/room_screen.dart';

/// Route table. Feature screens are added here as they are built; keep paths
/// stable because they will be used for deep links later.
abstract final class Routes {
  static const String home = '/';
  static const String room = '/rooms/:roomId';
  static const String capture = '/rooms/:roomId/capture';
  static const String review = '/rooms/:roomId/review';
  static const String item = '/items/:itemId';
  static const String report = '/report';
  static const String paywall = '/paywall';
  static const String settings = '/settings';

  static String roomPath(String roomId) => '/rooms/$roomId';

  static String capturePath(String roomId) => '/rooms/$roomId/capture';

  static String reviewPath(String roomId) => '/rooms/$roomId/review';

  static String itemPath(String itemId) => '/items/$itemId';
}

final appRouter = GoRouter(
  initialLocation: Routes.home,
  routes: [
    GoRoute(
      path: Routes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: Routes.room,
      builder: (context, state) =>
          RoomScreen(roomId: state.pathParameters['roomId']!),
    ),
    GoRoute(
      path: Routes.capture,
      builder: (context, state) =>
          CaptureScreen(roomId: state.pathParameters['roomId']!),
    ),
    GoRoute(
      path: Routes.review,
      builder: (context, state) =>
          ReviewScreen(roomId: state.pathParameters['roomId']!),
    ),
    GoRoute(
      path: Routes.item,
      builder: (context, state) =>
          ItemScreen(itemId: state.pathParameters['itemId']!),
    ),
    GoRoute(
      path: Routes.report,
      builder: (context, state) => const ReportScreen(),
    ),
    GoRoute(
      path: Routes.paywall,
      builder: (context, state) => const PaywallScreen(),
    ),
    GoRoute(
      path: Routes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
