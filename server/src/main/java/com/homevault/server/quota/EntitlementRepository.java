package com.homevault.server.quota;

import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Pro flag per user, written by the RevenueCat webhook (or by hand). */
@Repository
public class EntitlementRepository {

  private final JdbcClient jdbc;

  public EntitlementRepository(JdbcClient jdbc) {
    this.jdbc = jdbc;
  }

  /** The RevenueCat app user id is the app's device id (see CLAUDE.md). */
  public Optional<UUID> userIdForDevice(String deviceId) {
    return jdbc.sql("select user_id from devices where device_id = :id")
        .param("id", deviceId)
        .query(UUID.class)
        .optional();
  }

  public void setPro(UUID userId, boolean pro) {
    jdbc.sql(
            """
            insert into entitlements (user_id, is_pro, updated_at)
            values (:user_id, :pro, now())
            on conflict (user_id) do update
              set is_pro = excluded.is_pro, updated_at = now()
            """)
        .param("user_id", userId)
        .param("pro", pro)
        .update();
  }
}
