package com.homevault.server.stats;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * Recognition-quality counters (spec section 10). The app sends deltas since
 * its last upload; the server aggregates per prompt version. Counts only —
 * no item names, no photos, no per-user rows.
 */
@RestController
public class ReviewStatsController {

  public record Delta(
      @JsonProperty("prompt_version") @NotBlank @Size(max = 64) String promptVersion,
      @Min(0) @Max(100_000) int accepted,
      @Min(0) @Max(100_000) int edited,
      @Min(0) @Max(100_000) int deleted) {}

  public record Batch(@Valid @Size(max = 50) List<Delta> deltas) {}

  private final JdbcClient jdbc;

  public ReviewStatsController(JdbcClient jdbc) {
    this.jdbc = jdbc;
  }

  @PostMapping("/v1/stats/review")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void record(@Valid @RequestBody Batch batch) {
    if (batch.deltas() == null) return;
    for (Delta d : batch.deltas()) {
      if (d.accepted() == 0 && d.edited() == 0 && d.deleted() == 0) continue;
      jdbc.sql(
              """
              insert into review_stats (prompt_version, accepted, edited, deleted)
              values (:v, :a, :e, :d)
              on conflict (prompt_version) do update
                set accepted = review_stats.accepted + excluded.accepted,
                    edited = review_stats.edited + excluded.edited,
                    deleted = review_stats.deleted + excluded.deleted,
                    updated_at = now()
              """)
          .param("v", d.promptVersion())
          .param("a", d.accepted())
          .param("e", d.edited())
          .param("d", d.deleted())
          .update();
    }
  }
}
