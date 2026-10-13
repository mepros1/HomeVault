package com.homevault.server.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;

class IdempotencyKeysTest {

  private static byte[] b(String s) {
    return s.getBytes(StandardCharsets.UTF_8);
  }

  @Test
  void orderIndependent() {
    assertThat(IdempotencyKeys.fromImages(List.of(b("a"), b("b"), b("c"))))
        .isEqualTo(IdempotencyKeys.fromImages(List.of(b("c"), b("a"), b("b"))))
        .hasSize(64);
  }

  @Test
  void matchesTheAppsConstruction() {
    // Same construction as idempotencyKeyFor() in the Flutter app: sha256 over sorted
    // lowercase hex hashes joined by "\n". Two single-byte images with known hashes.
    String h1 = IdempotencyKeys.sha256Hex(b("x"));
    String h2 = IdempotencyKeys.sha256Hex(b("y"));
    String expected =
        IdempotencyKeys.sha256Hex(
            String.join("\n", h1.compareTo(h2) < 0 ? List.of(h1, h2) : List.of(h2, h1))
                .getBytes(StandardCharsets.UTF_8));
    assertThat(IdempotencyKeys.fromImages(List.of(b("y"), b("x")))).isEqualTo(expected);
  }
}
