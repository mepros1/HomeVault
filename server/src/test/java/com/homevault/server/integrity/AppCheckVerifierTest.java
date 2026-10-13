package com.homevault.server.integrity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.homevault.server.api.ApiException;
import com.homevault.server.config.HomeVaultProperties;
import com.homevault.server.config.HomeVaultProperties.AppCheckMode;
import java.io.IOException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

class AppCheckVerifierTest {

  private static final Instant NOW = Instant.parse("2026-09-27T12:00:00Z");
  private static final Clock CLOCK = Clock.fixed(NOW, ZoneOffset.UTC);
  private final ObjectMapper mapper = new ObjectMapper();

  private static HomeVaultProperties.AppCheck config(AppCheckMode mode) {
    return new HomeVaultProperties.AppCheck(mode, "com.homevault.app", "", Duration.ofMinutes(10));
  }

  private JsonNode payload(String pkg, String hash, Instant issued, String app, String... device) {
    var root = mapper.createObjectNode();
    root.putObject("requestDetails")
        .put("requestPackageName", pkg)
        .put("requestHash", hash)
        .put("timestampMillis", issued.toEpochMilli());
    root.putObject("appIntegrity").put("appRecognitionVerdict", app).put("packageName", pkg);
    var verdicts = root.putObject("deviceIntegrity").putArray("deviceRecognitionVerdict");
    for (String d : device) verdicts.add(d);
    return root;
  }

  private JsonNode good() {
    return payload("com.homevault.app", "hash-1", NOW.minusSeconds(30), "PLAY_RECOGNIZED",
        "MEETS_DEVICE_INTEGRITY", "MEETS_BASIC_INTEGRITY");
  }

  @Test
  void evaluatesEachCheck() {
    Duration age = Duration.ofMinutes(10);
    assertThat(AppCheckVerifier.evaluate(good(), "hash-1", "com.homevault.app", age, NOW).ok()).isTrue();
    assertThat(AppCheckVerifier.evaluate(good(), "other", "com.homevault.app", age, NOW).reason())
        .isEqualTo("request_hash_mismatch");
    assertThat(AppCheckVerifier.evaluate(good(), "hash-1", "com.evil.app", age, NOW).reason())
        .isEqualTo("package_mismatch");
    assertThat(AppCheckVerifier.evaluate(
            payload("com.homevault.app", "hash-1", NOW.minus(Duration.ofMinutes(11)), "PLAY_RECOGNIZED",
                "MEETS_DEVICE_INTEGRITY"), "hash-1", "com.homevault.app", age, NOW).reason())
        .isEqualTo("stale_token");
    assertThat(AppCheckVerifier.evaluate(
            payload("com.homevault.app", "hash-1", NOW, "UNRECOGNIZED_VERSION", "MEETS_DEVICE_INTEGRITY"),
            "hash-1", "com.homevault.app", age, NOW).reason())
        .isEqualTo("app_UNRECOGNIZED_VERSION");
    assertThat(AppCheckVerifier.evaluate(
            payload("com.homevault.app", "hash-1", NOW, "PLAY_RECOGNIZED", "MEETS_BASIC_INTEGRITY"),
            "hash-1", "com.homevault.app", age, NOW).reason())
        .isEqualTo("device_integrity");
  }

  @Test
  void enforceRejectsMissingAndBadTokensAndPassesGoodOnes() {
    PlayIntegrityDecoder decoder = token -> {
      if (token.equals("bad")) throw new IOException("400 from google");
      return good();
    };
    AppCheckVerifier verifier = new AppCheckVerifier(config(AppCheckMode.ENFORCE), decoder, CLOCK);

    assertThatCode(() -> verifier.verify("ok", "hash-1", "t")).doesNotThrowAnyException();
    assertThatThrownBy(() -> verifier.verify(null, "hash-1", "t"))
        .isInstanceOf(ApiException.class)
        .satisfies(e -> {
          assertThat(((ApiException) e).status()).isEqualTo(HttpStatus.FORBIDDEN);
          assertThat(((ApiException) e).code()).isEqualTo("app_check_failed");
        });
    assertThatThrownBy(() -> verifier.verify("bad", "hash-1", "t")).isInstanceOf(ApiException.class);
    assertThatThrownBy(() -> verifier.verify("ok", "hash-2", "t")).isInstanceOf(ApiException.class);
  }

  @Test
  void logModeNeverBlocksAndOffModeNeverDecodes() {
    AtomicInteger decodes = new AtomicInteger();
    PlayIntegrityDecoder decoder = token -> {
      decodes.incrementAndGet();
      return good();
    };
    AppCheckVerifier logging = new AppCheckVerifier(config(AppCheckMode.LOG), decoder, CLOCK);
    assertThatCode(() -> logging.verify(null, "hash-1", "t")).doesNotThrowAnyException();
    assertThatCode(() -> logging.verify("ok", "wrong", "t")).doesNotThrowAnyException();
    assertThat(decodes.get()).isEqualTo(1);

    AppCheckVerifier off = new AppCheckVerifier(config(AppCheckMode.OFF), decoder, CLOCK);
    assertThatCode(() -> off.verify("ok", "hash-1", "t")).doesNotThrowAnyException();
    assertThat(decodes.get()).isEqualTo(1);
  }
}
