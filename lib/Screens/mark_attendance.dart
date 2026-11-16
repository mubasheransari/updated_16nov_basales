
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import 'package:ords_ba/Bloc/attendance_cubit.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/photo_capture.dart';
import 'package:ords_ba/Widgets/shelf_dialog.dart';

class MarkAttendanceScreen extends StatefulWidget {
  const MarkAttendanceScreen({super.key});

  @override
  State<MarkAttendanceScreen> createState() =>
      _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState
    extends State<MarkAttendanceScreen> {
  static const LatLng _fallback = LatLng(24.8607, 67.0011);

  GoogleMapController? _map;
  StreamSubscription<Position>? _sub;

  MartLocation? _mart;
  bool _martLoading = true;
  String? _martError;

  Position? _pos;
  String? _gpsError;
  bool _gpsDeniedForever = false;
  bool _gpsLoading = true;

  String _address = 'Finding your location...';
  bool _didFit = false;

  // ------------------------------ USER ------------------------------

  AppUser? get _currentUser {
    return context.read<AuthBloc>().state.user;
  }

  int? get _assignedLocationId {
    return _currentUser?.locationId;
  }

  bool get _attendanceAnywhere {
    return _currentUser?.attendanceAnywhere ?? false;
  }

  // ------------------------------ INIT ------------------------------

  @override
  void initState() {
    super.initState();

    _loadMart();
    _startGps();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _printPermissionDebug();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  void _printPermissionDebug() {
    final user = _currentUser;

    debugPrint('');
    debugPrint('========== BA ATTENDANCE USER ==========');
    debugPrint('User ID: ${user?.id}');
    debugPrint('Name: ${user?.fullName}');
    debugPrint('Email: ${user?.email}');
    debugPrint('Assigned Location: ${user?.locationId}');
    debugPrint(
      'ATTENDANCE ANYWHERE: ${user?.attendanceAnywhere}',
    );
    debugPrint('Mart: ${_mart?.name}');
    debugPrint('Mart ID: ${_mart?.id}');
    debugPrint('========================================');
    debugPrint('');
  }

  // ------------------------------ MART ------------------------------

  Future<void> _loadMart() async {
    if (!mounted) return;

    setState(() {
      _martLoading = true;
      _martError = null;
    });

    final user = _currentUser;
    final repo = context.read<Repository>();
    final cache = CacheStore();

    if (user?.locationId == null ||
        user!.locationId! <= 0) {
      if (!mounted) return;

      setState(() {
        _martLoading = false;
        _martError =
            'No mart location is assigned to your account.';
      });

      return;
    }

    List<MartLocation> locations = [];

    try {
      locations = await repo.fetchLocations();
      await cache.saveLocations(locations);

      debugPrint(
        'Fetched ${locations.length} mart locations.',
      );
    } catch (e) {
      debugPrint('Failed to fetch locations: $e');

      try {
        locations = cache.readLocations();
        debugPrint(
          'Loaded ${locations.length} mart locations from cache.',
        );
      } catch (cacheError) {
        debugPrint(
          'Failed to read cached locations: $cacheError',
        );

        locations = [];
      }
    }

    if (!mounted) return;

    MartLocation? found;

    for (final location in locations) {
      if (location.id == user.locationId) {
        found = location;
        break;
      }
    }

    setState(() {
      _mart = found;
      _martLoading = false;

      _martError = found == null
          ? locations.isEmpty
              ? 'Unable to load mart locations. Please retry.'
              : 'Your assigned mart location was not found.'
          : null;
    });

    debugPrint('========== MART DEBUG ==========');
    debugPrint('Assigned Location ID: ${user.locationId}');
    debugPrint('Loaded Mart ID: ${found?.id}');
    debugPrint('Loaded Mart Name: ${found?.name}');
    debugPrint('Has Coordinates: ${found?.hasCoordinates}');
    debugPrint('Latitude: ${found?.latitude}');
    debugPrint('Longitude: ${found?.longitude}');
    debugPrint('Radius: ${found?.radiusMeters}');
    debugPrint('Attendance Anywhere: ${user.attendanceAnywhere}');
    debugPrint('Mart Error: $_martError');
    debugPrint('================================');

    _fitCamera();
  }

  // ------------------------------- GPS -------------------------------

  Future<void> _startGps() async {
    if (!mounted) return;

    setState(() {
      _gpsLoading = true;
      _gpsError = null;
      _gpsDeniedForever = false;
    });

    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!mounted) return;

      if (!serviceEnabled) {
        setState(() {
          _gpsLoading = false;
          _gpsError =
              'GPS is turned off. Please turn on location.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (!mounted) return;

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!mounted) return;

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsLoading = false;
          _gpsDeniedForever =
              permission == LocationPermission.deniedForever;

          _gpsError =
              'Location permission is required to mark attendance.';
        });

        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      _onPosition(position, geocode: true);

      await _sub?.cancel();

      if (!mounted) return;

      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (position) {
          _onPosition(position);
        },
        onError: (Object error) {
          debugPrint('GPS stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('GPS error: $e');

      if (!mounted) return;

      setState(() {
        _gpsLoading = false;
        _gpsError = 'Could not get your location. Try again.';
      });
    }
  }

  void _onPosition(
    Position position, {
    bool geocode = false,
  }) {
    if (!mounted) return;

    setState(() {
      _pos = position;
      _gpsLoading = false;
      _gpsError = null;
    });

    debugPrint('========== GPS DEBUG ==========');
    debugPrint('Latitude: ${position.latitude}');
    debugPrint('Longitude: ${position.longitude}');
    debugPrint('Accuracy: ${position.accuracy}');
    debugPrint('Mocked: ${position.isMocked}');
    debugPrint('================================');

    if (geocode) {
      _reverseGeocode(position);
    }

    _fitCamera();
  }

  Future<void> _reverseGeocode(Position position) async {
    try {
      final marks = await geo.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      if (marks.isEmpty) {
        setState(() {
          _address =
              '${position.latitude.toStringAsFixed(5)}, '
              '${position.longitude.toStringAsFixed(5)}';
        });

        return;
      }

      final mark = marks.first;

      final parts = [
        mark.thoroughfare,
        mark.subLocality,
        mark.locality,
      ]
          .where(
            (value) =>
                value != null && value.trim().isNotEmpty,
          )
          .map((value) => value!.trim())
          .toList();

      setState(() {
        _address = parts.isEmpty
            ? '${position.latitude.toStringAsFixed(5)}, '
                '${position.longitude.toStringAsFixed(5)}'
            : parts.join(', ');
      });
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');

      if (!mounted) return;

      setState(() {
        _address =
            '${position.latitude.toStringAsFixed(5)}, '
            '${position.longitude.toStringAsFixed(5)}';
      });
    }
  }

  // ----------------------------- DISTANCE -----------------------------

  double? get _distance {
    final mart = _mart;
    final position = _pos;

    if (mart == null ||
        !mart.hasCoordinates ||
        position == null) {
      return null;
    }

    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      mart.latitude!,
      mart.longitude!,
    );
  }

  bool? get _inside {
    final distance = _distance;
    final mart = _mart;

    if (distance == null || mart == null) {
      return null;
    }

    return distance <= mart.radiusMeters;
  }

  // ------------------------------ MAP ------------------------------

  Future<void> _fitCamera({
    bool force = false,
  }) async {
    final controller = _map;

    if (controller == null) return;
    if (_didFit && !force) return;

    final mart = _mart;
    final position = _pos;

    try {
      if (mart != null &&
          mart.hasCoordinates &&
          position != null) {
        final martPoint = LatLng(
          mart.latitude!,
          mart.longitude!,
        );

        final userPoint = LatLng(
          position.latitude,
          position.longitude,
        );

        if ((_distance ?? 0) < 40) {
          await controller.animateCamera(
            CameraUpdate.newLatLngZoom(martPoint, 18),
          );
        } else {
          final southwest = LatLng(
            martPoint.latitude < userPoint.latitude
                ? martPoint.latitude
                : userPoint.latitude,
            martPoint.longitude < userPoint.longitude
                ? martPoint.longitude
                : userPoint.longitude,
          );

          final northeast = LatLng(
            martPoint.latitude > userPoint.latitude
                ? martPoint.latitude
                : userPoint.latitude,
            martPoint.longitude > userPoint.longitude
                ? martPoint.longitude
                : userPoint.longitude,
          );

          await controller.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: southwest,
                northeast: northeast,
              ),
              90,
            ),
          );
        }

        _didFit = true;
      } else if (mart != null && mart.hasCoordinates) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(mart.latitude!, mart.longitude!),
            17,
          ),
        );
      } else if (position != null) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            17,
          ),
        );
      }
    } catch (e) {
      debugPrint('Map camera update error: $e');
    }
  }

  Future<void> _recenter() async {
    final position = _pos;

    if (position == null) {
      await _startGps();
      return;
    }

    await _reverseGeocode(position);

    await _map?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        17,
      ),
    );
  }

  // ----------------------------- ATTENDANCE -----------------------------

  Future<void> _onTap(
    AttendanceState attendance,
  ) async {
    final position = _pos;

    if (position == null) {
      showToast(
        context,
        'Waiting for your GPS location...',
      );
      return;
    }

    if (position.isMocked) {
      showToast(
        context,
        'Fake / mock location detected. Turn it off to continue.',
        error: true,
      );
      return;
    }

    final user = _currentUser;
    final locationId = user?.locationId;

    if (user == null) {
      showToast(
        context,
        'User session not found. Please log in again.',
        error: true,
      );
      return;
    }

    if (locationId == null || locationId <= 0) {
      showToast(
        context,
        'No assigned mart location found. Please contact your administrator.',
        error: true,
      );
      return;
    }

    final mart = _mart;

    // A loaded mart must always match the assigned location.
    if (mart != null && mart.id != locationId) {
      showToast(
        context,
        'The loaded mart does not match your assigned location.',
        error: true,
      );
      return;
    }

    // Read the current permission from the authenticated user.
    final attendanceAnywhere = user.attendanceAnywhere;

    debugPrint('');
    debugPrint('========== ATTENDANCE CHECK ==========');
    debugPrint('User ID: ${user.id}');
    debugPrint('User Name: ${user.fullName}');
    debugPrint('User Email: ${user.email}');
    debugPrint('Role: ${user.role}');
    debugPrint('Assigned Location ID: $locationId');
    debugPrint('Mart ID: ${mart?.id}');
    debugPrint('Attendance Anywhere: $attendanceAnywhere');
    debugPrint('Current Latitude: ${position.latitude}');
    debugPrint('Current Longitude: ${position.longitude}');
    debugPrint('Mart Latitude: ${mart?.latitude}');
    debugPrint('Mart Longitude: ${mart?.longitude}');
    debugPrint('Distance: $_distance');
    debugPrint('Inside Radius: $_inside');
    debugPrint('======================================');

    // ----------------------------------------------------------
    // LOCATION PERMISSION
    // ----------------------------------------------------------

    if (attendanceAnywhere) {
      // ATTENDANCE_ANYWHERE = Y
      // Skip the 100m restriction completely.
      debugPrint(
        'ANYWHERE PERMISSION ENABLED: '
        'Skipping Flutter distance validation.',
      );
    } else {
      // ATTENDANCE_ANYWHERE = N
      // Assigned mart and coordinates are mandatory.
      if (mart == null) {
        showToast(
          context,
          'Mart information is unavailable. Please retry.',
          error: true,
        );
        return;
      }

      if (!mart.hasCoordinates) {
        showToast(
          context,
          'Mart coordinates are unavailable. '
          'Please contact your administrator.',
          error: true,
        );
        return;
      }

      final distance = _distance;

      if (distance == null) {
        showToast(
          context,
          'Unable to calculate your distance from the assigned mart.',
          error: true,
        );
        return;
      }

      if (distance > mart.radiusMeters) {
        showToast(
          context,
          'You are ${distance.toStringAsFixed(0)} metres away. '
          'You must be within '
          '${mart.radiusMeters.toStringAsFixed(0)} metres '
          'of ${mart.name}.',
          error: true,
        );
        return;
      }

      debugPrint(
        'RADIUS VALIDATION PASSED: '
        '${distance.toStringAsFixed(1)} metres.',
      );
    }

    if (!mounted) return;

    final cubit = context.read<AttendanceCubit>();

    // ----------------------------------------------------------
    // ATTENDANCE OUT
    // ----------------------------------------------------------

    if (attendance.isCheckedIn) {
      final selfie = await capturePhoto(
        context,
        selfie: true,
        title: 'Attendance OUT selfie',
        message: 'Take a clear selfie to mark attendance OUT.',
      );

      if (selfie == null || !mounted) return;

      debugPrint('Submitting ATTENDANCE OUT...');
      debugPrint('Location ID: $locationId');
      debugPrint('Attendance Anywhere: $attendanceAnywhere');

      await cubit.checkOut(
        lat: position.latitude,
        lng: position.longitude,
        locationId: locationId,
        selfie: selfie,
      );
    }

    // ----------------------------------------------------------
    // ATTENDANCE IN
    // ----------------------------------------------------------

    else {
      final selfie = await capturePhoto(
        context,
        selfie: true,
        title: 'Attendance IN selfie',
        message: 'Take a clear selfie to mark attendance IN.',
      );

      if (selfie == null || !mounted) return;

      debugPrint('Submitting ATTENDANCE IN...');
      debugPrint('Location ID: $locationId');
      debugPrint('Attendance Anywhere: $attendanceAnywhere');

      await cubit.checkIn(
        lat: position.latitude,
        lng: position.longitude,
        locationName: mart?.name ?? user.locationName,
        locationId: locationId,
        selfie: selfie,
      );
    }
  }

  // -------------------------------- BUILD --------------------------------

  @override
  Widget build(BuildContext context) {
    final mart = _mart;
    final position = _pos;

    final markers = <Marker>{
      if (mart != null && mart.hasCoordinates)
        Marker(
          markerId: const MarkerId('mart'),
          position: LatLng(
            mart.latitude!,
            mart.longitude!,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: mart.name,
            snippet: 'Assigned mart location',
          ),
        ),
    };

    final circles = <Circle>{
      if (mart != null && mart.hasCoordinates)
        Circle(
          circleId: const CircleId('radius'),
          center: LatLng(
            mart.latitude!,
            mart.longitude!,
          ),
          radius: mart.radiusMeters,
          fillColor: AppColors.red.withValues(alpha: 0.16),
          strokeColor: AppColors.red,
          strokeWidth: 2,
        ),
    };

    final start = mart != null && mart.hasCoordinates
        ? LatLng(
            mart.latitude!,
            mart.longitude!,
          )
        : position != null
            ? LatLng(
                position.latitude,
                position.longitude,
              )
            : _fallback;

    return BlocListener<AttendanceCubit, AttendanceState>(
      listenWhen: (previous, current) =>
          previous.messageId != current.messageId,
      listener: (context, state) {
        if (state.message != null) {
          showToast(
            context,
            state.message!,
            error: state.messageIsError,
          );
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: start,
                zoom: 16,
              ),
              onMapCreated: (controller) {
                _map = controller;

                Future.delayed(
                  const Duration(milliseconds: 400),
                  () {
                    if (mounted) {
                      _fitCamera();
                    }
                  },
                );
              },
              markers: markers,
              circles: circles,
              myLocationEnabled: position != null,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              padding: const EdgeInsets.only(bottom: 330),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _RoundBtn(
                      icon: Icons.arrow_back_rounded,
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                    ),

                    const Spacer(),

                    BlocBuilder<AttendanceCubit, AttendanceState>(
                      buildWhen: (previous, current) =>
                          previous.isCheckedIn != current.isCheckedIn,
                      builder: (context, attendance) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (attendance.isCheckedIn) ...[
                              _RoundBtn(
                                icon: Icons.photo_camera_rounded,
                                onTap: () {
                                  showShelfDialog(context);
                                },
                              ),
                              const SizedBox(width: 10),
                            ],

                            _RoundBtn(
                              icon: Icons.my_location_rounded,
                              onTap: _recenter,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: SafeArea(
                top: false,
                child: BlocBuilder<AttendanceCubit, AttendanceState>(
                  builder: (context, attendance) {
                    return _panel(attendance);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------- PANEL --------------------------------

  Widget _panel(AttendanceState attendance) {
    final mart = _mart;
    final inside = _inside;
    final distance = _distance;

    final user = _currentUser;
    final attendanceAnywhere =
        user?.attendanceAnywhere ?? false;

    Widget status;

    if (_martLoading || _gpsLoading) {
      status = const Pill(
        'Checking...',
        icon: Icons.hourglass_top_rounded,
      );
    } else if (_gpsError != null) {
      status = const Pill(
        'GPS unavailable',
        icon: Icons.error_outline_rounded,
      );
    } else if (attendanceAnywhere) {
      // Check this BEFORE inside == null.
      status = const Pill(
        'Anywhere enabled',
        icon: Icons.check_circle_rounded,
        color: AppColors.success,
      );
    } else if (_martError != null) {
      status = const Pill(
        'Mart unavailable',
        icon: Icons.error_outline_rounded,
        color: AppColors.warning,
      );
    } else if (inside == null) {
      status = const Pill(
        'Not verified',
        icon: Icons.help_outline_rounded,
        color: AppColors.warning,
      );
    } else if (inside) {
      status = Pill(
        'At mart - ${distance!.toStringAsFixed(0)} m',
        icon: Icons.check_circle_rounded,
        color: AppColors.success,
      );
    } else {
      status = Pill(
        distance! >= 1000
            ? '${(distance / 1000).toStringAsFixed(1)} km away'
            : '${distance.toStringAsFixed(0)} m away',
        icon: Icons.location_off_rounded,
      );
    }

    String label;
    IconData icon;

    Gradient gradient = AppGradients.horizontal;

    VoidCallback? onTap = () => _onTap(attendance);

    if (attendance.isCheckedIn) {
      label = 'ATTENDANCE OUT';
      icon = Icons.logout_rounded;
      gradient = AppGradients.primary;
    } else if (attendance.today != null &&
        !(kAllowReCheckIn && attendance.isCompletedToday)) {
      label = 'ATTENDANCE COMPLETED';
      icon = Icons.verified_rounded;
      onTap = null;
    } else {
      label = 'ATTENDANCE IN';
      icon = Icons.login_rounded;
    }

    // GPS is always required.
    if (_gpsError != null || _pos == null) {
      if (!attendance.isCheckedIn &&
          attendance.today == null) {
        onTap = null;
      }
    }

    // A missing mart blocks ordinary BAs but does not block
    // users whose ATTENDANCE_ANYWHERE permission is enabled.
    if (!attendanceAnywhere && _martError != null) {
      if (!attendance.isCheckedIn &&
          attendance.today == null) {
        onTap = null;
      }
    }

    // A normal BA cannot proceed while mart information is loading.
    if (!attendanceAnywhere && _martLoading) {
      if (!attendance.isCheckedIn &&
          attendance.today == null) {
        onTap = null;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.redDeep.withValues(alpha: 0.22),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppGradients.soft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your mart',
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                      ),
                    ),

                    Text(
                      mart?.name ??
                          user?.locationName ??
                          (_martLoading ? 'Loading...' : '--'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),

              status,
            ],
          ),

          const SizedBox(height: 14),

          if (_gpsError != null)
            _InfoBox(
              icon: Icons.gps_off_rounded,
              text: _gpsError!,
              action: _gpsDeniedForever ? 'Settings' : 'Retry',
              onAction: () {
                if (_gpsDeniedForever) {
                  Geolocator.openAppSettings();
                } else {
                  _startGps();
                }
              },
            )
          else if (_martError != null && !attendanceAnywhere)
            _InfoBox(
              icon: Icons.place_outlined,
              text: _martError!,
              action: 'Retry',
              onAction: _loadMart,
            )
          else ...[
            _InfoBox(
              icon: Icons.my_location_rounded,
              text: _address,
            ),

            if (mart != null && !mart.hasCoordinates &&
                !attendanceAnywhere) ...[
              const SizedBox(height: 8),
              const _InfoBox(
                icon: Icons.info_outline_rounded,
                text: 'Mart coordinates are not available. '
                    'Please contact your administrator.',
              ),
            ],

            if (attendanceAnywhere) ...[
              const SizedBox(height: 8),
              const _InfoBox(
                icon: Icons.check_circle_outline_rounded,
                text: 'Your account is allowed to mark attendance '
                    'from any location.',
              ),
            ],
          ],

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _TimeTile(
                  label: 'IN',
                  value: fmtTime(attendance.today?.inAt),
                  icon: Icons.login_rounded,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: _TimeTile(
                  label: 'OUT',
                  value: attendance.today?.outAt == null
                      ? '--:--'
                      : '${fmtTime(attendance.today!.outAt)}'
                          '${attendance.today!.autoOut ? ' (auto)' : ''}',
                  icon: Icons.logout_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          GradientButton(
            text: label,
            icon: icon,
            gradient: gradient,
            loading: attendance.busy,
            onPressed: attendance.busy ? null : onTap,
          ),

          const SizedBox(height: 10),

          const Center(
            child: _LiveClock(),
          ),
        ],
      ),
    );
  }
}

// ------------------------------ ROUND BUTTON ------------------------------

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: AppColors.redDeep.withValues(alpha: 0.3),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            color: AppColors.red,
          ),
        ),
      ),
    );
  }
}

// -------------------------------- INFO BOX --------------------------------

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.redTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.red,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 13.5,
              ),
            ),
          ),

          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

// -------------------------------- TIME TILE --------------------------------

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: AppColors.red,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------- LIVE CLOCK --------------------------------

class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late final Timer _timer;

  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          setState(() {
            _now = DateTime.now();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      DateFormat('EEEE, dd MMM yyyy - hh:mm:ss a').format(_now),
      style: const TextStyle(
        color: AppColors.textDim,
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
      ),
    );
  }
}
