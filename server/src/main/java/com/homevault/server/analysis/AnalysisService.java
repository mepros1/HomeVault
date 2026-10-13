package com.homevault.server.analysis;

import com.homevault.server.api.ApiException;
import com.homevault.server.config.HomeVaultProperties;
import com.homevault.server.quota.AnalysisCacheRepository;
import com.homevault.server.quota.BudgetRepository;
import com.homevault.server.quota.QuotaRepository;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

/**
 * Worker flow (spec section 5.2): validate input → idempotency cache → consume quota → model →
 * validate output → cache → respond. Images live in memory for the request only.
 */
@Service
public class AnalysisService {

  private static final Logger log = LoggerFactory.getLogger(AnalysisService.class);

  public record Request(String roomType, String currency, List<byte[]> images, String idempotencyKey) {}

  private final HomeVaultProperties props;
  private final GeminiClient gemini;
  private final PromptRegistry prompts;
  private final QuotaRepository quotas;
  private final BudgetRepository budget;
  private final AnalysisCacheRepository cache;

  public AnalysisService(
      HomeVaultProperties props,
      GeminiClient gemini,
      PromptRegistry prompts,
      QuotaRepository quotas,
      BudgetRepository budget,
      AnalysisCacheRepository cache) {
    this.props = props;
    this.gemini = gemini;
    this.prompts = prompts;
    this.quotas = quotas;
    this.budget = budget;
    this.cache = cache;
  }

  public AnalyzeRoomResponse analyze(UUID userId, Request request) {
    String requestId = newRequestId();
    List<byte[]> images = request.images() == null ? List.of() : request.images();

    if (props.gemini().apiKey().isBlank() && !props.gemini().mock()) {
      throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "misconfigured", "GEMINI_API_KEY is not set");
    }
    if (images.isEmpty()) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "bad_request", "no images");
    }
    if (images.size() > props.maxImages()) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "bad_request", "max " + props.maxImages() + " images");
    }
    for (int i = 0; i < images.size(); i++) {
      if (images.get(i).length > props.maxImageBytes()) {
        throw new ApiException(
            HttpStatus.PAYLOAD_TOO_LARGE, "payload_too_large", "image " + i + " exceeds 400 KB");
      }
    }

    String roomType = blankToDefault(request.roomType(), "Room");
    String currency = blankToDefault(request.currency(), "USD").toUpperCase(Locale.ROOT);
    if (currency.length() > 3) currency = currency.substring(0, 3);

    String key =
        request.idempotencyKey() == null || request.idempotencyKey().isBlank()
            ? IdempotencyKeys.fromImages(images)
            : request.idempotencyKey();

    Optional<AnalyzeRoomResponse> cached = cache.find(userId, key, props.cacheTtl());
    if (cached.isPresent()) {
      log.info("request_id={} user={} cache_hit", requestId, userId);
      return cached.get().withRequestId(requestId, true);
    }

    int dailyBudget = props.quota().dailyBudget();
    if (dailyBudget > 0 && !budget.consume(dailyBudget)) {
      log.warn("request_id={} daily_budget_exhausted limit={}", requestId, dailyBudget);
      throw new ApiException(
          HttpStatus.SERVICE_UNAVAILABLE, "budget_exhausted", "Analysis is paused for today, please try again tomorrow");
    }

    var quota = quotas.consume(userId, props.quota().freePerMonth(), props.quota().proPerMonth());
    if (!quota.allowed()) {
      if (dailyBudget > 0) budget.release();
      throw new ApiException(
          HttpStatus.TOO_MANY_REQUESTS,
          "quota_exceeded",
          "Analysis quota exhausted",
          Map.of(
              "limit", quota.limit(),
              "used", quota.used(),
              "resets_at", quota.resetsAt().toInstant().toString()));
    }

    long started = System.currentTimeMillis();
    GeminiClient.Result result;
    try {
      result = gemini.analyze(roomType, currency, images);
    } catch (GeminiClient.GeminiException e) {
      quotas.release(userId);
      if (dailyBudget > 0) budget.release();
      log.warn("request_id={} user={} model_error status={} msg={}", requestId, userId, e.status(), e.getMessage());
      throw new ApiException(
          HttpStatus.valueOf(e.status()), e.status() == 504 ? "model_timeout" : "model_error", e.getMessage());
    } catch (RuntimeException e) {
      quotas.release(userId);
      if (dailyBudget > 0) budget.release();
      throw e;
    }

    ItemValidator.Result validated = ItemValidator.validate(result.parsed(), images.size(), currency);
    if (validated.items().isEmpty()) {
      quotas.release(userId);
      if (dailyBudget > 0) budget.release();
      log.info("request_id={} user={} no_items warnings={}", requestId, userId, validated.warnings());
      throw new ApiException(
          HttpStatus.UNPROCESSABLE_ENTITY, "no_items_recognized", "No items were recognised in these photos");
    }

    AnalyzeRoomResponse response =
        new AnalyzeRoomResponse(
            requestId,
            gemini.model(),
            prompts.version(),
            validated.items(),
            result.usage(),
            validated.warnings(),
            null);
    cache.put(userId, key, response);

    log.info(
        "request_id={} user={} ok images={} items={} ms={} in={} out={}",
        requestId,
        userId,
        images.size(),
        validated.items().size(),
        System.currentTimeMillis() - started,
        result.usage().inputTokens(),
        result.usage().outputTokens());
    return response;
  }

  private static String newRequestId() {
    return "req_" + UUID.randomUUID().toString().replace("-", "").substring(0, 20);
  }

  private static String blankToDefault(String value, String fallback) {
    return value == null || value.isBlank() ? fallback : value.trim();
  }
}
