import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/attendance_cubit.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Bloc/complaints_cubit.dart';
import 'package:ords_ba/Bloc/dashboard_cubit.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Data/network_status.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Screens/history_screen.dart';
import 'package:ords_ba/Screens/home_screen.dart';
import 'package:ords_ba/Screens/profile_screen.dart';
import 'package:ords_ba/Widgets/bottom_bar.dart';
import 'package:ords_ba/Widgets/common.dart';

/// Shown only while logged in. Creates the [AttendanceCubit] for this BA.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>();
    final k = auth.state.user?.storageKey;
    return MultiBlocProvider(
      providers: [
        BlocProvider<AttendanceCubit>(
          // New cubit per login: attendance data is namespaced by BA.
          key: ValueKey('attendance_$k'),
          create: (ctx) => AttendanceCubit(
            repo: ctx.read<Repository>(),
            store: AttendanceStore(auth.state.user!.storageKey),
            shelfStore: ShelfStore(auth.state.user!.storageKey),
            pendingStore: PendingActionStore(auth.state.user!.storageKey),
            tokenProvider: () => auth.state.token,
            onUnauthorized: () => auth.add(const AuthLogoutRequested(
                reason: 'Session expired. Please login again.')),
          ),
        ),
        // Home chart: selected filter + data loaded from the server.
        BlocProvider<DashboardCubit>(
          key: ValueKey('dashboard_$k'),
          create: (ctx) => DashboardCubit(
            repo: ctx.read<Repository>(),
            tokenProvider: () => auth.state.token,
            onUnauthorized: () => auth.add(const AuthLogoutRequested(
                reason: 'Session expired. Please login again.')),
          ),
        ),
        // Complaints list: also feeds the open count on the home screen.
        BlocProvider<ComplaintsCubit>(
          key: ValueKey('complaints_$k'),
          lazy: false,
          create: (ctx) => ComplaintsCubit(
            service: ComplaintService(
              repo: ctx.read<Repository>(),
              tokenProvider: () => auth.state.token,
              onUnauthorized: () => auth.add(const AuthLogoutRequested(
                  reason: 'Session expired. Please login again.')),
            ),
          )..load(),
        ),
      ],
      child: const _ShellBody(),
    );
  }
}

class _ShellBody extends StatefulWidget {
  const _ShellBody();
  @override
  State<_ShellBody> createState() => _ShellBodyState();
}

class _ShellBodyState extends State<_ShellBody> with WidgetsBindingObserver {
  BottomTab _tab = BottomTab.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPendingActions();
    });
    NetworkStatus.offline.addListener(_onNetworkChanged);
  }

  /// Internet came back: send everything saved while offline.
  void _onNetworkChanged() {
    if (!NetworkStatus.offline.value && mounted) {
      _syncPendingActions();
      context.read<ComplaintsCubit>().refresh();
      context.read<DashboardCubit>().refreshCurrent();
    }
  }

  @override
  void dispose() {
    NetworkStatus.offline.removeListener(_onNetworkChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// App came back to foreground: catch a missed 12:00 AM auto-out and
  /// refresh the profile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AttendanceCubit>().sync();
      _syncPendingActions();
      context.read<ComplaintsCubit>().refresh();
      context.read<DashboardCubit>().refreshCurrent();
      context.read<AuthBloc>().add(const AuthProfileRefreshRequested());
    }
  }

  bool _syncing = false; // never run two syncs at once (would double-send)

  Future<void> _syncPendingActions() async {
    if (_syncing) return;
    final auth = context.read<AuthBloc>();
    final token = auth.state.token;
    final user = auth.state.user;
    if (token == null || user == null) return;
    _syncing = true;
    try {
      final count = await context.read<Repository>().syncPendingActions(
        token: token,
        store: PendingActionStore(user.storageKey),
      );
      if (count > 0 && mounted) {
        showToast(context, '$count offline item(s) synced successfully.', error: false);
        context.read<ComplaintsCubit>().refresh();
        context.read<DashboardCubit>().refreshCurrent();
      }
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        auth.add(AuthLogoutRequested(reason: e.message));
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <BottomTab, Widget>{
      BottomTab.home: HomeScreen(key: UniqueKey()),
      BottomTab.history: const HistoryScreen(),
      BottomTab.profile: const ProfileScreen(),
    };

    return PopScope(
      canPop: _tab == BottomTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = BottomTab.home);
      },
      child: BlocListener<AttendanceCubit, AttendanceState>(
        // messages raised outside a screen (e.g. midnight auto-out)
        listenWhen: (a, b) =>
            a.messageId != b.messageId && b.message != null && b.messageIsError == false &&
            b.message!.contains('automatically'),
        listener: (context, st) => showToast(context, st.message!, error: false),
        child: Scaffold(
          extendBody: true,
          body: pages[_tab]!,
          bottomNavigationBar: BottomBar(
            active: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
      ),
    );
  }
}
