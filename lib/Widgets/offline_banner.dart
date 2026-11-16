import 'package:flutter/material.dart';
import 'package:ords_ba/Data/network_status.dart';

/// Wraps the whole app (MaterialApp.builder). Shows a slim bar on top while
/// there is no internet. The child is never re-created when the bar appears.
class OfflineScope extends StatelessWidget {
  const OfflineScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: NetworkStatus.offline,
      builder: (context, offline, _) {
        final top = MediaQuery.paddingOf(context).top;
        return Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: offline
                  ? Material(
                      color: const Color(0xFF263238),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, top + 6, 16, 8),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_off_rounded,
                                color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                NetworkStatus.message,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: offline,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
