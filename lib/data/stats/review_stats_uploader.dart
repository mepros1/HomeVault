import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/analyze_room_client.dart' show AccessTokenProvider;
import '../db/database.dart';

/// Sends the review counters (spec §10) to `POST /v1/stats/review`.
///
/// Only deltas since the last successful upload travel, as integers per
/// prompt version: how many suggested items were accepted, edited or
/// deleted. No item content, no per-room data. Failures are silent: the
/// counters stay unsynced and the next call retries.
class ReviewStatsUploader {
  ReviewStatsUploader(
    this._db, {
    required Uri endpoint,
    required AccessTokenProvider accessToken,
    AccessTokenProvider? refreshAccessToken,
    http.Client? httpClient,
  })  : _endpoint = endpoint,
        _accessToken = accessToken,
        _refreshAccessToken = refreshAccessToken,
        _http = httpClient ?? http.Client();

  static const Duration timeout = Duration(seconds: 15);

  final AppDatabase _db;
  final Uri _endpoint;
  final AccessTokenProvider _accessToken;
  final AccessTokenProvider? _refreshAccessToken;
  final http.Client _http;

  Future<bool>? _inFlight;

  /// Uploads pending deltas. Returns true when there was nothing to send or
  /// the server accepted the batch. Concurrent calls share one request.
  Future<bool> upload() {
    final running = _inFlight;
    if (running != null) return running;
    final future = _upload().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<bool> _upload() async {
    final rows = await _db.reviewStatsDao.unsynced();
    if (rows.isEmpty) return true;
    // Undo after a sync can make a delta negative; the server only counts
    // forward, so such a row is reported as zero and re-based.
    final deltas = [
      for (final r in rows)
        {
          'prompt_version': r.promptVersion,
          'accepted': _clamp(r.accepted - r.syncedAccepted),
          'edited': _clamp(r.edited - r.syncedEdited),
          'deleted': _clamp(r.deleted - r.syncedDeleted),
        },
    ];

    String? token;
    try {
      token = await _accessToken();
    } catch (_) {
      return false;
    }
    if (token == null) return false;

    var refreshed = false;
    while (true) {
      final http.Response response;
      try {
        response = await _http
            .post(
              _endpoint,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'deltas': deltas}),
            )
            .timeout(timeout);
      } on Exception {
        return false;
      }
      if (response.statusCode == 204) {
        await _db.reviewStatsDao.markSynced(rows);
        return true;
      }
      final refresh = _refreshAccessToken;
      if (response.statusCode == 401 && !refreshed && refresh != null) {
        refreshed = true;
        try {
          token = await refresh();
        } catch (_) {
          return false;
        }
        if (token == null) return false;
        continue;
      }
      return false;
    }
  }

  static int _clamp(int v) => v < 0 ? 0 : v;

  void close() => _http.close();
}
