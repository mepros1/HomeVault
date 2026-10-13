/// Client-side view of the server error contract (spec §5.1). Each variant's
/// doc comment states the behaviour the UI is expected to implement.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// 401 — the stored device token is no longer accepted; re-register.
final class UnauthorizedException extends ApiException {
  const UnauthorizedException() : super('Session is no longer valid');
}

/// 403 — show the "update the app" stub.
final class AppCheckFailedException extends ApiException {
  const AppCheckFailedException() : super('App integrity check failed');
}

/// 413 — recompress and retry.
final class PayloadTooLargeException extends ApiException {
  const PayloadTooLargeException() : super('Images exceed the size limit');
}

/// 422 — hint: "shoot closer and in good light".
final class NoItemsRecognizedException extends ApiException {
  const NoItemsRecognizedException() : super('No items were recognised');
}

/// 429 — show the paywall.
final class QuotaExceededException extends ApiException {
  const QuotaExceededException({required this.limit, required this.resetsAt})
      : super('Analysis quota exhausted');

  final int limit;
  final DateTime resetsAt;
}

/// 502 / 504 after all retries, or network rate limiting — keep the job queued.
final class UpstreamException extends ApiException {
  const UpstreamException(this.statusCode)
      : super('Analysis service failed ($statusCode)');

  final int statusCode;
}

/// Any other non-2xx status.
final class UnexpectedStatusException extends ApiException {
  const UnexpectedStatusException(this.statusCode, String body)
      : super('Unexpected status $statusCode: $body');

  final int statusCode;
}

/// 409 `backup_limit` — the cloud backup holds as many reports as allowed.
final class BackupLimitException extends ApiException {
  const BackupLimitException() : super('Cloud backup is full');
}

/// 404 `transfer_code_invalid` on `/v1/backups/claim`.
final class TransferCodeInvalidException extends ApiException {
  const TransferCodeInvalidException() : super('Transfer code is unknown, used or expired');
}

/// No connectivity or socket failure — job stays queued (spec §3.3).
final class NetworkException extends ApiException {
  const NetworkException(Object cause) : super('Network error: $cause');
}
