import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:json_annotation/json_annotation.dart';

import '../api/analyze_room_client.dart' show AccessTokenProvider;
import '../api/api_errors.dart';

part 'report_backup_client.g.dart';

/// One PDF report as the server holds it.
@JsonSerializable(createToJson: false)
class CloudBackup {
  const CloudBackup({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.generatedAt,
    required this.itemCount,
    required this.totalLow,
    required this.totalHigh,
  });

  factory CloudBackup.fromJson(Map<String, dynamic> json) => _$CloudBackupFromJson(json);

  final String id;
  @JsonKey(name: 'file_name')
  final String fileName;
  @JsonKey(name: 'size_bytes')
  final int sizeBytes;
  @JsonKey(name: 'generated_at')
  final DateTime generatedAt;
  @JsonKey(name: 'item_count')
  final int itemCount;
  @JsonKey(name: 'total_low')
  final double totalLow;
  @JsonKey(name: 'total_high')
  final double totalHigh;
}

class TransferCode {
  const TransferCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

/// HTTP client for `/v1/backups` (cloud backup of PDF reports).
class ReportBackupClient {
  ReportBackupClient({
    required Uri baseEndpoint,
    required AccessTokenProvider accessToken,
    AccessTokenProvider? refreshAccessToken,
    http.Client? httpClient,
  })  : _base = baseEndpoint,
        _accessToken = accessToken,
        _refreshAccessToken = refreshAccessToken,
        _http = httpClient ?? http.Client();

  static const Duration timeout = Duration(seconds: 60);

  final Uri _base;
  final AccessTokenProvider _accessToken;
  final AccessTokenProvider? _refreshAccessToken;
  final http.Client _http;

  Future<CloudBackup> upload({
    required String id,
    required String fileName,
    required DateTime generatedAt,
    required int itemCount,
    required double totalLow,
    required double totalHigh,
    required Uint8List pdf,
  }) async {
    final response = await _send((token) {
      final request = http.MultipartRequest('POST', _base)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['id'] = id
        ..fields['file_name'] = fileName
        ..fields['generated_at'] = generatedAt.toUtc().toIso8601String()
        ..fields['item_count'] = '$itemCount'
        ..fields['total_low'] = totalLow.toStringAsFixed(2)
        ..fields['total_high'] = totalHigh.toStringAsFixed(2)
        ..files.add(http.MultipartFile.fromBytes('file', pdf, filename: fileName));
      return request;
    });
    return CloudBackup.fromJson(_json(response));
  }

  Future<List<CloudBackup>> list() async {
    final response = await _send((token) => http.Request('GET', _base)..headers['Authorization'] = 'Bearer $token');
    final backups = _json(response)['backups'] as List<dynamic>;
    return [for (final b in backups) CloudBackup.fromJson(b as Map<String, dynamic>)];
  }

  Future<Uint8List> download(String id) async {
    final response = await _send(
        (token) => http.Request('GET', _base.replace(path: '${_base.path}/$id'))..headers['Authorization'] = 'Bearer $token');
    return response.bodyBytes;
  }

  Future<void> delete(String id) async {
    await _send((token) =>
        http.Request('DELETE', _base.replace(path: '${_base.path}/$id'))..headers['Authorization'] = 'Bearer $token');
  }

  Future<TransferCode> transferCode() async {
    final response = await _send((token) =>
        http.Request('POST', _base.replace(path: '${_base.path}/transfer-code'))
          ..headers['Authorization'] = 'Bearer $token');
    final json = _json(response);
    return TransferCode(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  /// Moves the old device's backups to this one; returns how many.
  Future<int> claim(String code) async {
    final response = await _send((token) => http.Request('POST', _base.replace(path: '${_base.path}/claim'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'code': code}));
    return _json(response)['moved'] as int;
  }

  /// Sends the request, re-issuing the token once on 401, and maps errors.
  Future<http.Response> _send(http.BaseRequest Function(String token) build) async {
    var token = await _accessToken();
    if (token == null) throw const UnauthorizedException();
    var refreshed = false;
    while (true) {
      final http.Response response;
      try {
        response = await http.Response.fromStream(await _http.send(build(token!)).timeout(timeout));
      } on SocketException catch (e) {
        throw NetworkException(e);
      } on http.ClientException catch (e) {
        throw NetworkException(e);
      }
      switch (response.statusCode) {
        case >= 200 && < 300:
          return response;
        case 401:
          final refresh = _refreshAccessToken;
          if (refreshed || refresh == null) throw const UnauthorizedException();
          refreshed = true;
          token = await refresh();
          if (token == null) throw const UnauthorizedException();
        case 404 when _errorCode(response) == 'transfer_code_invalid':
          throw const TransferCodeInvalidException();
        case 409 when _errorCode(response) == 'backup_limit':
          throw const BackupLimitException();
        case 413:
          throw const PayloadTooLargeException();
        default:
          throw UnexpectedStatusException(response.statusCode, response.body);
      }
    }
  }

  static String? _errorCode(http.Response response) {
    try {
      return (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  void close() => _http.close();
}
