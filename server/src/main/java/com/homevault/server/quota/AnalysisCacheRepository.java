package com.homevault.server.quota;

import com.homevault.server.analysis.AnalyzeRoomResponse;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.ObjectMapper;

/** 24-hour idempotency cache keyed by (user, X-Idempotency-Key). Only responses, never images. */
@Repository
public class AnalysisCacheRepository {

  private final JdbcClient jdbc;
  private final ObjectMapper mapper;

  public AnalysisCacheRepository(JdbcClient jdbc, ObjectMapper mapper) {
    this.jdbc = jdbc;
    this.mapper = mapper;
  }

  public Optional<AnalyzeRoomResponse> find(UUID userId, String key, Duration ttl) {
    return jdbc.sql(
            """
            select response::text
              from analysis_cache
             where user_id = :user_id
               and idempotency_key = :key
               and created_at > :not_before
            """)
        .param("user_id", userId)
        .param("key", key)
        .param("not_before", OffsetDateTime.now().minus(ttl))
        .query(String.class)
        .optional()
        .map(json -> mapper.readValue(json, AnalyzeRoomResponse.class));
  }

  public void put(UUID userId, String key, AnalyzeRoomResponse response) {
    jdbc.sql(
            """
            insert into analysis_cache (user_id, idempotency_key, response, created_at)
            values (:user_id, :key, cast(:response as jsonb), now())
            on conflict (user_id, idempotency_key) do update
              set response = excluded.response, created_at = excluded.created_at
            """)
        .param("user_id", userId)
        .param("key", key)
        .param("response", mapper.writeValueAsString(response))
        .update();
  }

  /** Housekeeping; call from a scheduled job or a cron once the deployment target is known. */
  public int purgeOlderThan(Duration ttl) {
    return jdbc.sql("delete from analysis_cache where created_at < :cutoff")
        .param("cutoff", OffsetDateTime.now().minus(ttl))
        .update();
  }
}
