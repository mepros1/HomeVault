package com.homevault.server.integrity;

import com.homevault.server.api.ApiException;
import com.homevault.server.config.HomeVaultProperties;
import com.homevault.server.config.HomeVaultProperties.AppCheckMode;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;

/**
 * Checks the {@code X-App-Check} header (a Play Integrity standard token) on
 * the endpoints that cost money. The token is bound to the request by its
 * {@code requestHash}: the device id on registration, the idempotency key on
 * analysis, so a captured token cannot be replayed for another request.
 *
 * <p>Modes: OFF ignores the header; LOG verifies and records the outcome but
 * never blocks; ENFORCE answers 403 {@code app_check_failed}.
 */
public class AppCheckVerifier {

  public static final String HEADER = "X-App-Check";

  /** Outcome of evaluating a decoded token; {@code reason} is null when it passes. */
  public record Verdict(boolean ok, String reason) {
    static Verdict pass() {
      return new Verdict(true, null);
    }

    static Verdict fail(String reason) {
      return new Verdict(false, reason);
    }
  }

  private static final Logger log = LoggerFactory.getLogger(AppCheckVerifier.class);

  private final HomeVaultProperties.AppCheck config;
  private final PlayIntegrityDecoder decoder;
  private final Clock clock;

  public AppCheckVerifier(HomeVaultProperties.AppCheck config, PlayIntegrityDecoder decoder, Clock clock) {
    this.config = config;
    this.decoder = decoder;
    this.clock = clock;
  }

  public AppCheckMode mode() {
    return config.mode();
  }

  /**
   * @param token the header value, may be null
   * @param expectedRequestHash what the app must have bound the token to
   * @param context endpoint name for logs
   */
  public void verify(String token, String expectedRequestHash, String context) {
    if (config.mode() == AppCheckMode.OFF) return;
    Verdict verdict = check(token, expectedRequestHash);
    if (verdict.ok()) {
      log.debug("app_check context={} ok", context);
      return;
    }
    if (config.mode() == AppCheckMode.LOG) {
      log.warn("app_check context={} would_reject reason={}", context, verdict.reason());
      return;
    }
    log.warn("app_check context={} rejected reason={}", context, verdict.reason());
    throw new ApiException(HttpStatus.FORBIDDEN, "app_check_failed", "app integrity check failed");
  }

  private Verdict check(String token, String expectedRequestHash) {
    if (token == null || token.isBlank()) return Verdict.fail("missing_token");
    if (decoder == null) return Verdict.fail("no_decoder");
    JsonNode payload;
    try {
      payload = decoder.decode(token);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return Verdict.fail("decode_interrupted");
    } catch (Exception e) {
      log.warn("app_check decode failed: {}", e.toString());
      return Verdict.fail("decode_failed");
    }
    return evaluate(payload, expectedRequestHash, config.packageName(), config.maxTokenAge(), clock.instant());
  }

  /** Pure verdict logic, shared with tests. */
  static Verdict evaluate(
      JsonNode payload, String expectedRequestHash, String packageName, Duration maxAge, Instant now) {
    JsonNode request = payload.path("requestDetails");
    if (!packageName.equals(request.path("requestPackageName").asString())) return Verdict.fail("package_mismatch");
    if (expectedRequestHash == null || !expectedRequestHash.equals(request.path("requestHash").asString())) {
      return Verdict.fail("request_hash_mismatch");
    }
    long ts = request.path("timestampMillis").asLong(0);
    if (ts <= 0) return Verdict.fail("missing_timestamp");
    Instant issued = Instant.ofEpochMilli(ts);
    if (issued.isBefore(now.minus(maxAge)) || issued.isAfter(now.plus(Duration.ofMinutes(1)))) {
      return Verdict.fail("stale_token");
    }
    String app = payload.path("appIntegrity").path("appRecognitionVerdict").asString();
    if (!"PLAY_RECOGNIZED".equals(app)) return Verdict.fail("app_" + Optional.ofNullable(app).orElse("unknown"));
    boolean deviceOk = false;
    for (JsonNode v : payload.path("deviceIntegrity").path("deviceRecognitionVerdict")) {
      if ("MEETS_DEVICE_INTEGRITY".equals(v.asString())) deviceOk = true;
    }
    if (!deviceOk) return Verdict.fail("device_integrity");
    return Verdict.pass();
  }
}
