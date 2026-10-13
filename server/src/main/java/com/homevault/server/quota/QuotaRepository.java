package com.homevault.server.quota;

import java.time.OffsetDateTime;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/** Wraps the {@code consume_room_quota} / {@code release_room_quota} SQL functions. */
@Repository
public class QuotaRepository {

  public record QuotaResult(boolean allowed, int used, int limit, OffsetDateTime resetsAt) {}

  private final JdbcClient jdbc;
  private final ObjectMapper mapper;

  public QuotaRepository(JdbcClient jdbc, ObjectMapper mapper) {
    this.jdbc = jdbc;
    this.mapper = mapper;
  }

  public QuotaResult consume(UUID userId, int freeLimit, int proLimit) {
    String json =
        jdbc.sql("select consume_room_quota(:user_id, :free_limit, :pro_limit)::text")
            .param("user_id", userId)
            .param("free_limit", freeLimit)
            .param("pro_limit", proLimit)
            .query(String.class)
            .single();
    JsonNode n = mapper.readTree(json);
    return new QuotaResult(
        n.path("allowed").asBoolean(false),
        n.path("used").asInt(0),
        n.path("limit").asInt(0),
        OffsetDateTime.parse(n.path("resets_at").asString()));
  }

  public void release(UUID userId) {
    jdbc.sql("select release_room_quota(:user_id)").param("user_id", userId).query().listOfRows();
  }
}
