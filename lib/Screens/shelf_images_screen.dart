import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Data/network_status.dart';
import 'package:ords_ba/Data/shelf_cache.dart';
import 'package:ords_ba/Model/shelf_models.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';

/// Displays all shelf pictures belonging to the signed-in BA.
/// The list endpoint returns metadata; each image is loaded separately by ID.
class ShelfImagesScreen extends StatefulWidget {
  const ShelfImagesScreen({super.key});

  @override
  State<ShelfImagesScreen> createState() => _ShelfImagesScreenState();
}

class _ShelfImagesScreenState extends State<ShelfImagesScreen> {
  final List<ShelfPicture> _items = [];
  List<Uint8List> _pendingPhotos = const [];
  bool _loading = true;
  bool _fromPhone = false; // showing the copy saved on this phone
  String? _error;

  ShelfCache get _cache =>
      ShelfCache(context.read<AuthBloc>().state.user?.storageKey ?? 'user');

  Repository get _repo => context.read<Repository>();
  String get _token => context.read<AuthBloc>().state.token ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _unauthorized(Object error) {
    if (error is ApiException && error.isUnauthorized) {
      context.read<AuthBloc>().add(const AuthLogoutRequested(
        reason: 'Session expired. Please login again.',
      ));
    }
  }

  Future<void> _load({bool spinner = true}) async {
    if (!mounted) return;
    if (spinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    _loadPending();
    try {
      final pictures = await _repo.fetchShelfPictures(token: _token);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(pictures);
        _error = null;
        _fromPhone = false;
        _loading = false;
      });
      // Keep a copy on the phone so everything also opens offline.
      final cache = _cache;
      await cache.saveList(pictures);
      cache.prefetch(pictures, _repo.shelfImageUrl, _repo.imageHeaders(_token));
    } catch (error) {
      if (!mounted) return;
      _unauthorized(error);
      final offline = error is ApiException && error.isOffline;
      final saved = _cache.readList();
      if (saved.isNotEmpty && (offline || _items.isEmpty)) {
        setState(() {
          _items
            ..clear()
            ..addAll(saved);
          _error = null;
          _fromPhone = true;
          _loading = false;
        });
        if (offline) showToast(context, NetworkStatus.message);
        return;
      }
      setState(() {
        _error = error is ApiException ? error.message : error.toString();
        _loading = false;
      });
      if (_items.isNotEmpty) showToast(context, _error!);
    }
  }

  /// Pictures taken offline that are still waiting to be uploaded.
  void _loadPending() {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    final photos = <Uint8List>[];
    for (final item in PendingActionStore(user.storageKey).all().reversed) {
      if (item['type'] != 'shelf') continue;
      try {
        final p = Map<String, dynamic>.from(item['payload'] as Map);
        photos.add(base64Decode(p['image_base64'].toString()));
      } catch (_) {}
    }
    if (mounted) setState(() => _pendingPhotos = photos);
  }

  void _open(ShelfPicture picture) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FullImageScreen(
        cache: _cache,
        picture: picture,
        url: _repo.shelfImageUrl(picture.id),
        headers: _repo.imageHeaders(_token),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Images'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.red,
        onRefresh: () => _load(spinner: false),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 120),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.red),
            ),
          ),
        ],
      );
    }

    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 60),
        children: [
          EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load shelf images',
            subtitle: _error,
          ),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    if (_items.isEmpty && _pendingPhotos.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 60),
        children: const [
          EmptyState(
            icon: Icons.photo_library_outlined,
            title: 'No shelf pictures yet',
            subtitle: 'Shelf pictures you upload will appear here.',
          ),
        ],
      );
    }

    final rows = <Object>[];
    DateTime? previousDay;
    for (final picture in _items) {
      final date = picture.capturedAt ?? picture.createdAt;
      if (date != null &&
          (previousDay == null || !_sameDay(previousDay, date))) {
        rows.add(date);
      }
      if (date != null) previousDay = date;
      rows.add(picture);
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      itemCount: rows.length + _pendingPhotos.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Text(
              '${_items.length} picture${_items.length == 1 ? '' : 's'}'
              '${_fromPhone ? '  -  saved on this phone (offline)' : ''}',
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        if (index <= _pendingPhotos.length) {
          return _PendingCard(bytes: _pendingPhotos[index - 1]);
        }

        final row = rows[index - _pendingPhotos.length - 1];
        if (row is DateTime) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 0, 8),
            child: Text(
              _dayLabel(row),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.redDeep,
              ),
            ),
          );
        }

        final picture = row as ShelfPicture;
        return _PictureCard(
          picture: picture,
          cache: _cache,
          url: _repo.shelfImageUrl(picture.id),
          headers: _repo.imageHeaders(_token),
          onTap: () => _open(picture),
        );
      },
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dayLabel(DateTime date) {
  final now = DateTime.now();
  if (_sameDay(date, now)) return 'Today';
  if (_sameDay(date, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return DateFormat('EEEE, dd MMM yyyy').format(date);
}

String _dateTimeText(DateTime? date) => date == null
    ? 'Date not available'
    : DateFormat('dd MMM yyyy  -  hh:mm a').format(date);

/// A picture saved offline that has not been uploaded yet.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: cardDecoration(radius: 20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.memory(bytes,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) =>
                      Container(color: AppColors.redTint)),
            ),
            const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      size: 18, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Saved offline - waiting to upload',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                          fontSize: 14),
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

class _PictureCard extends StatelessWidget {
  const _PictureCard({
    required this.cache,
    required this.picture,
    required this.url,
    required this.headers,
    required this.onTap,
  });

  final ShelfCache cache;
  final ShelfPicture picture;
  final String url;
  final Map<String, String> headers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = picture.capturedAt ?? picture.createdAt;
    final location = [picture.locationName, picture.areaName, picture.city]
        .where((part) => part.trim().isNotEmpty)
        .toSet()
        .join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: cardDecoration(radius: 20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: _ShelfNetworkImage(
                  key: ValueKey('shelf-${picture.id}'),
                  cache: cache,
                  pictureId: picture.id,
                  url: url,
                  headers: headers,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 17, color: AppColors.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _dateTimeText(date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        Text(
                          '#${picture.id}',
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.storefront_rounded,
                              size: 16, color: AppColors.textDim),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              location,
                              style: const TextStyle(
                                color: AppColors.textDim,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (picture.remarks.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        picture.remarks,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a shelf picture from the phone's saved copy when there is one,
/// otherwise downloads it (with the Bearer token) and saves it for offline use.
class _ShelfNetworkImage extends StatefulWidget {
  const _ShelfNetworkImage({
    super.key,
    required this.cache,
    required this.pictureId,
    required this.url,
    required this.headers,
    required this.fit,
  });

  final ShelfCache cache;
  final int pictureId;
  final String url;
  final Map<String, String> headers;
  final BoxFit fit;

  @override
  State<_ShelfNetworkImage> createState() => _ShelfNetworkImageState();
}

class _ShelfNetworkImageState extends State<_ShelfNetworkImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() => _bytes =
      widget.cache.load(widget.pictureId, widget.url, widget.headers);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasData) {
          return Image.memory(
            snap.data!,
            fit: widget.fit,
            width: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _problem(
                'Picture could not be loaded', Icons.broken_image_outlined),
          );
        }
        if (snap.hasError) {
          return InkWell(
            onTap: () => setState(_start),
            child: _problem(
                'Offline - this picture is not saved on the phone yet.\nTap to retry.',
                Icons.cloud_off_rounded),
          );
        }
        return Container(
          color: AppColors.redTint,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
              strokeWidth: 2.4, color: AppColors.red),
        );
      },
    );
  }

  Widget _problem(String text, IconData icon) => Container(
        color: AppColors.redTint,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.red, size: 36),
            const SizedBox(height: 6),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ],
        ),
      );
}

class _FullImageScreen extends StatelessWidget {
  const _FullImageScreen({
    required this.cache,
    required this.picture,
    required this.url,
    required this.headers,
  });

  final ShelfCache cache;
  final ShelfPicture picture;
  final String url;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final date = picture.capturedAt ?? picture.createdAt;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_dateTimeText(date), style: const TextStyle(fontSize: 15)),
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: _ShelfNetworkImage(
            cache: cache,
            pictureId: picture.id,
            url: url,
            headers: headers,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
