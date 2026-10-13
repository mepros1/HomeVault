package com.homevault.server.analysis;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;

/**
 * X-Idempotency-Key fallback: SHA-256 over the sorted SHA-256 hex hashes of the images,
 * joined with {@code \n}. Must stay identical to {@code idempotencyKeyFor} in the app.
 */
public final class IdempotencyKeys {

  private IdempotencyKeys() {}

  public static String fromImages(List<byte[]> images) {
    List<String> hexes = images.stream().map(IdempotencyKeys::sha256Hex).sorted().toList();
    return sha256Hex(String.join("\n", hexes).getBytes(StandardCharsets.UTF_8));
  }

  public static String sha256Hex(byte[] bytes) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }
}
