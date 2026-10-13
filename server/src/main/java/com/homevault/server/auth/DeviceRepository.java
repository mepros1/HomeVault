package com.homevault.server.auth;

import com.homevault.server.api.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class DeviceRepository {

  private final JdbcClient jdbc;

  public DeviceRepository(JdbcClient jdbc) {
    this.jdbc = jdbc;
  }

  /** Atomic create-or-authenticate: an existing id is never enough to take over a device. */
  public UUID registerOrTouch(String deviceId, String platform, String deviceSecret) {
    return jdbc.sql(
            """
            insert into devices (device_id, platform, secret_hash)
            values (:device_id, :platform, :secret_hash)
            on conflict (device_id) do update
              set last_seen_at = now(),
                  platform = coalesce(excluded.platform, devices.platform)
            where devices.secret_hash = excluded.secret_hash
            returning user_id
            """)
        .param("device_id", deviceId)
        .param("platform", platform)
        .param("secret_hash", hashSecret(deviceSecret))
        .query(UUID.class)
        .optional()
        .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "unauthorized", "device credentials rejected"));
  }

  static String hashSecret(String secret) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
          .digest(secret.getBytes(StandardCharsets.UTF_8)));
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }
}
