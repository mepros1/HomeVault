import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../integrity/app_check.dart';
import '../media/image_prep.dart';
import 'analyze_room_models.dart';
import 'api_errors.dart';

typedef AccessTokenProvider = FutureOr<String?> Function();

/// HTTP client for `POST /v1/analyze-room` (spec §5.1).
///
/// Responsibilities: build the multipart body, attach auth and idempotency
/// headers, map status codes to [ApiException], retry 502/504 with
/// exponential backoff, and re-issue the token once on 401. It does not know
/// about the database or the queue.
class AnalyzeRoomClient {
  AnalyzeRoomClient({
    required this._endpoint,
    required this._accessToken,
    this._refreshAccessToken,
    http.Client? httpClient,
    Random? random,
    AppCheck appCheck = const NoopAppCheck(),
  })  : _http = httpClient ?? http.Client(),
        _random = random ?? Random(),
        _appCheck = appCheck;

  final Uri _endpoint;
  final AccessTokenProvider _accessToken;
  final AccessTokenProvider? _refreshAccessToken;
  final http.Client _http;
  final Random _random;
  final AppCheck _appCheck;

  Future<AnalyzeRoomResponse> analyzeRoom({
    required String roomType,
    required List<PreparedImage> images,
    required String idempotencyKey,
    String currency = Defaults.currency,
  }) async {
    assert(images.isNotEmpty && images.length <= Limits.maxCapturesPerRoom);

    var token = await _accessToken();
    if (token == null) throw const UnauthorizedException();

    var attempt = 0;
    var refreshed = false;
    while (true) {
      attempt++;
      // Fresh token per attempt, bound to the idempotency key (spec §6).
      final integrity = await _appCheck.token(idempotencyKey);
      final http.StreamedResponse streamed;
      try {
        streamed = await _http
            .send(_buildRequest(token!, roomType, currency, images, idempotencyKey, integrity))
            .timeout(Limits.analyzeTimeout);
      } on TimeoutException {
        if (attempt >= Limits.maxAnalyzeAttempts) throw const UpstreamException(504);
        await _backoff(attempt);
        continue;
      } on SocketException catch (e) {
        throw NetworkException(e);
      } on http.ClientException catch (e) {
        throw NetworkException(e);
      }

      final response = await http.Response.fromStream(streamed);
      switch (response.statusCode) {
        case 200:
          return AnalyzeRoomResponse.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
        case 401:
          final refresh = _refreshAccessToken;
          if (refreshed || refresh == null) throw const UnauthorizedException();
          refreshed = true;
          token = await refresh();
          if (token == null) throw const UnauthorizedException();
          attempt--; // a token re-issue is not a failed attempt
        case 403:
          throw const AppCheckFailedException();
        case 413:
          throw const PayloadTooLargeException();
        case 422:
          throw const NoItemsRecognizedException();
        case 429:
          final error = jsonDecode(response.body) as Map<String, dynamic>;
          if (error['error'] == 'rate_limited') throw const UpstreamException(429);
          final body = QuotaExceededBody.fromJson(
            error,
          );
          throw QuotaExceededException(
            limit: body.limit,
            resetsAt: body.resetsAt,
          );
        case 502 || 504:
          if (attempt >= Limits.maxAnalyzeAttempts) {
            throw UpstreamException(response.statusCode);
          }
          await _backoff(attempt);
        default:
          throw UnexpectedStatusException(response.statusCode, response.body);
      }
    }
  }

  http.MultipartRequest _buildRequest(
    String token,
    String roomType,
    String currency,
    List<PreparedImage> images,
    String idempotencyKey,
    String? integrityToken,
  ) {
    final request = http.MultipartRequest('POST', _endpoint)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['X-Idempotency-Key'] = idempotencyKey
      ..fields['room_type'] = roomType
      ..fields['currency'] = currency;
    if (integrityToken != null) request.headers['X-App-Check'] = integrityToken;
    for (var i = 0; i < images.length; i++) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'images[]',
          images[i].bytes,
          filename: 'img_$i.jpg',
        ),
      );
    }
    return request;
  }

  /// 2s, 4s, 8s … plus up to 500 ms of jitter.
  Future<void> _backoff(int attempt) {
    final base = Limits.analyzeBaseBackoff * pow(2, attempt - 1).toInt();
    final jitter = Duration(milliseconds: _random.nextInt(500));
    return Future<void>.delayed(base + jitter);
  }

  void close() => _http.close();
}
