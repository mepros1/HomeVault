import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:json_annotation/json_annotation.dart';

import '../api/api_errors.dart';
import '../integrity/app_check.dart';

part 'device_auth_client.g.dart';

/// Body of a successful `POST /v1/devices`.
@JsonSerializable()
class RegisterDeviceResponse {
  const RegisterDeviceResponse({
    required this.accessToken,
    required this.userId,
    this.tokenType = 'Bearer',
  });

  factory RegisterDeviceResponse.fromJson(Map<String, dynamic> json) =>
      _$RegisterDeviceResponseFromJson(json);

  @JsonKey(name: 'access_token')
  final String accessToken;

  @JsonKey(name: 'token_type')
  final String tokenType;

  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, dynamic> toJson() => _$RegisterDeviceResponseToJson(this);
}

/// Anonymous device registration against the HomeVault server.
///
/// Re-registration authenticates with the original device secret before
/// issuing a fresh token. A device id alone is not an authentication credential.
class DeviceAuthClient {
  DeviceAuthClient({
    required Uri endpoint,
    http.Client? httpClient,
    AppCheck appCheck = const NoopAppCheck(),
  })  : _endpoint = endpoint,
        _http = httpClient ?? http.Client(),
        _appCheck = appCheck;

  final Uri _endpoint;
  final http.Client _http;
  final AppCheck _appCheck;

  Future<RegisterDeviceResponse> register({
    required String deviceId,
    required String deviceSecret,
    required String platform,
  }) async {
    // The integrity token is bound to the device id (spec §6).
    final integrity = await _appCheck.token(deviceId);
    final http.Response response;
    try {
      response = await _http
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/json',
              'X-App-Check': ?integrity,
            },
            body: jsonEncode({'device_id': deviceId, 'device_secret': deviceSecret, 'platform': platform}),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException catch (e) {
      throw NetworkException(e);
    } on SocketException catch (e) {
      throw NetworkException(e);
    } on http.ClientException catch (e) {
      throw NetworkException(e);
    }

    if (response.statusCode == 200) {
      return RegisterDeviceResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw UnexpectedStatusException(response.statusCode, response.body);
  }

  void close() => _http.close();
}
