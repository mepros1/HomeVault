package com.homevault.server.analysis;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;

/** Successful response body (spec section 5.1) plus {@code prompt_version}. */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record AnalyzeRoomResponse(
    @JsonProperty("request_id") String requestId,
    String model,
    @JsonProperty("prompt_version") String promptVersion,
    List<AnalyzedItem> items,
    TokenUsage usage,
    List<String> warnings,
    Boolean cached) {

  public record TokenUsage(
      @JsonProperty("input_tokens") long inputTokens,
      @JsonProperty("output_tokens") long outputTokens) {}

  public AnalyzeRoomResponse withRequestId(String newRequestId, boolean fromCache) {
    return new AnalyzeRoomResponse(
        newRequestId, model, promptVersion, items, usage, warnings, fromCache ? true : null);
  }
}
