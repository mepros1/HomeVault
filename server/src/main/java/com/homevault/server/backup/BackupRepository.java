package com.homevault.server.backup;

import java.math.BigDecimal;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

/** PDF backups and device-transfer codes; see V3 migration. */
@Repository
public class BackupRepository {

  public record Summary(
      UUID id,
      String fileName,
      int sizeBytes,
      String sha256,
      OffsetDateTime generatedAt,
      int itemCount,
      BigDecimal totalLow,
      BigDecimal totalHigh,
      OffsetDateTime createdAt) {}

  public record Stored(Summary summary, byte[] content) {}

  public record Usage(int count, long bytes) {}

  /** No 0/O, 1/I: the code is read from one screen and typed on another. */
  private static final String CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  private static final int CODE_LENGTH = 8;

  private static final String SUMMARY_COLUMNS =
      "id, file_name, size_bytes, sha256, generated_at, item_count, total_low, total_high, created_at";

  private final JdbcClient jdbc;
  private final SecureRandom random = new SecureRandom();

  public BackupRepository(JdbcClient jdbc) {
    this.jdbc = jdbc;
  }

  public List<Summary> list(UUID userId) {
    return jdbc.sql("select " + SUMMARY_COLUMNS + " from report_backups where user_id = :u order by generated_at desc")
        .param("u", userId)
        .query(Summary.class)
        .list();
  }

  public Usage usage(UUID userId) {
    return jdbc.sql("select count(*) as count, coalesce(sum(size_bytes), 0) as bytes from report_backups where user_id = :u")
        .param("u", userId)
        .query((rs, i) -> new Usage(rs.getInt("count"), rs.getLong("bytes")))
        .single();
  }

  /** Owner of an existing backup id, if any. */
  public Optional<UUID> ownerOf(UUID id) {
    return jdbc.sql("select user_id from report_backups where id = :id").param("id", id).query(UUID.class).optional();
  }

  public Summary upsert(UUID userId, Summary meta, byte[] content) {
    jdbc.sql(
            """
            insert into report_backups
              (id, user_id, file_name, size_bytes, sha256, generated_at, item_count, total_low, total_high, content)
            values (:id, :u, :name, :size, :sha, :gen, :items, :low, :high, :content)
            on conflict (id) do update
              set file_name = excluded.file_name, size_bytes = excluded.size_bytes, sha256 = excluded.sha256,
                  generated_at = excluded.generated_at, item_count = excluded.item_count,
                  total_low = excluded.total_low, total_high = excluded.total_high, content = excluded.content
            where report_backups.user_id = :u
            """)
        .param("id", meta.id())
        .param("u", userId)
        .param("name", meta.fileName())
        .param("size", content.length)
        .param("sha", meta.sha256())
        .param("gen", meta.generatedAt())
        .param("items", meta.itemCount())
        .param("low", meta.totalLow())
        .param("high", meta.totalHigh())
        .param("content", content)
        .update();
    return get(userId, meta.id()).map(Stored::summary).orElseThrow();
  }

  public Optional<Stored> get(UUID userId, UUID id) {
    return jdbc.sql("select " + SUMMARY_COLUMNS + ", content from report_backups where user_id = :u and id = :id")
        .param("u", userId)
        .param("id", id)
        .query((rs, i) -> new Stored(
            new Summary(
                rs.getObject("id", UUID.class),
                rs.getString("file_name"),
                rs.getInt("size_bytes"),
                rs.getString("sha256"),
                rs.getObject("generated_at", OffsetDateTime.class),
                rs.getInt("item_count"),
                rs.getBigDecimal("total_low"),
                rs.getBigDecimal("total_high"),
                rs.getObject("created_at", OffsetDateTime.class)),
            rs.getBytes("content")))
        .optional();
  }

  public int delete(UUID userId, UUID id) {
    return jdbc.sql("delete from report_backups where user_id = :u and id = :id")
        .param("u", userId)
        .param("id", id)
        .update();
  }

  /** Re-keys every backup of {@code from} to {@code to}; returns how many moved. */
  public int moveAll(UUID from, UUID to) {
    if (from.equals(to)) return 0;
    return jdbc.sql("update report_backups set user_id = :to where user_id = :from")
        .param("to", to)
        .param("from", from)
        .update();
  }

  public String createTransferCode(UUID userId, Duration ttl) {
    for (int attempt = 0; attempt < 5; attempt++) {
      String code = randomCode();
      int inserted =
          jdbc.sql(
                  """
                  insert into backup_transfers (code, from_user_id, expires_at)
                  values (:code, :u, now() + :ttl * interval '1 second')
                  on conflict (code) do nothing
                  """)
              .param("code", code)
              .param("u", userId)
              .param("ttl", ttl.toSeconds())
              .update();
      if (inserted == 1) return code;
    }
    throw new IllegalStateException("could not allocate a transfer code");
  }

  /** Consumes the code and moves the backups; empty when the code is unknown, used or expired. */
  @Transactional
  public Optional<Integer> claim(String code, UUID toUserId) {
    Optional<UUID> from =
        jdbc.sql(
                """
                update backup_transfers set used_at = now()
                where code = :code and used_at is null and expires_at > now()
                returning from_user_id
                """)
            .param("code", code)
            .query(UUID.class)
            .optional();
    return from.map(f -> moveAll(f, toUserId));
  }

  /** Backups of devices not seen for {@code retention} and stale transfer codes. */
  public int purgeInactive(Duration retention) {
    jdbc.sql("delete from backup_transfers where expires_at < now() - interval '1 day'").update();
    return jdbc.sql(
            """
            delete from report_backups b
            where not exists (
              select 1 from devices d
              where d.user_id = b.user_id and d.last_seen_at > now() - :days * interval '1 day')
            """)
        .param("days", retention.toDays())
        .update();
  }

  private String randomCode() {
    StringBuilder sb = new StringBuilder(CODE_LENGTH);
    for (int i = 0; i < CODE_LENGTH; i++) sb.append(CODE_ALPHABET.charAt(random.nextInt(CODE_ALPHABET.length())));
    return sb.toString();
  }
}
