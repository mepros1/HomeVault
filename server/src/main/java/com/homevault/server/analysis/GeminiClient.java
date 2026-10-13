package com.homevault.server.analysis;

import com.homevault.server.config.HomeVaultProperties;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.time.Duration;
import java.util.Base64;
import java.util.List;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.node.ArrayNode;
import tools.jackson.databind.node.ObjectNode;

/**
 * One {@code generateContent} call with structured output. All room photos go in a single
 * request so the model can deduplicate across frames (spec section 3.3).
 *
 * <p>The API key must belong to a project with billing enabled: on the free tier Google may
 * use the content to improve its products, which is unacceptable for photos of people's
 * homes (spec section 6).
 */
@Component
public class GeminiClient {

  public record Result(JsonNode parsed, AnalyzeRoomResponse.TokenUsage usage) {}

  /** 502 for failures and bad output, 504 for timeouts (spec section 5.1). */
  public static class GeminiException extends RuntimeException {
    private final int status;

    public GeminiException(String message, int status) {
      super(message);
      this.status = status;
    }

    public int status() {
      return status;
    }
  }

  private static final String ENDPOINT =
      "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent";

  private final HomeVaultProperties.Gemini config;
  private final PromptRegistry prompts;
  private final ObjectMapper mapper;
  private final HttpClient http;

  public GeminiClient(HomeVaultProperties props, PromptRegistry prompts, ObjectMapper mapper) {
    this.config = props.gemini();
    this.prompts = prompts;
    this.mapper = mapper;
    this.http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
  }

  public String model() {
    return config.mock() ? "mock" : config.model();
  }

  public Result analyze(String roomType, String currency, List<byte[]> images) {
    if (config.mock()) {
      return new Result(
          MockRecognition.itemsFor(roomType, images.size(), mapper),
          new AnalyzeRoomResponse.TokenUsage(0, 0));
    }
    ObjectNode body = buildBody(roomType, currency, images);
    HttpRequest request =
        HttpRequest.newBuilder(URI.create(ENDPOINT.formatted(config.model())))
            .timeout(config.timeout())
            .header("Content-Type", "application/json")
            .header("x-goog-api-key", config.apiKey())
            .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(body)))
            .build();

    HttpResponse<String> response;
    try {
      response = http.send(request, HttpResponse.BodyHandlers.ofString());
    } catch (HttpTimeoutException e) {
      throw new GeminiException("model timeout", 504);
    } catch (IOException e) {
      throw new GeminiException("model unreachable: " + e.getMessage(), 502);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new GeminiException("interrupted", 502);
    }

    if (response.statusCode() / 100 != 2) {
      String snippet = response.body() == null ? "" : response.body();
      throw new GeminiException(
          "model HTTP " + response.statusCode() + ": " + snippet.substring(0, Math.min(300, snippet.length())),
          502);
    }

    JsonNode json = mapper.readTree(response.body());
    JsonNode textNode = json.path("candidates").path(0).path("content").path("parts").path(0).path("text");
    if (!textNode.isTextual()) {
      String reason = json.path("candidates").path(0).path("finishReason").asString();
      if (reason.isEmpty()) reason = json.path("promptFeedback").path("blockReason").asString();
      throw new GeminiException("model returned no text (" + (reason.isEmpty() ? "unknown" : reason) + ")", 502);
    }

    JsonNode parsed;
    try {
      parsed = mapper.readTree(textNode.asString());
    } catch (RuntimeException e) {
      throw new GeminiException("model returned invalid JSON", 502);
    }

    JsonNode usage = json.path("usageMetadata");
    return new Result(
        parsed,
        new AnalyzeRoomResponse.TokenUsage(
            usage.path("promptTokenCount").asLong(0), usage.path("candidatesTokenCount").asLong(0)));
  }

  private ObjectNode buildBody(String roomType, String currency, List<byte[]> images) {
    ObjectNode body = mapper.createObjectNode();

    body.putObject("systemInstruction").putArray("parts").addObject().put("text", prompts.systemPrompt());

    ArrayNode parts = body.putArray("contents").addObject().put("role", "user").putArray("parts");
    parts.addObject().put("text", prompts.userPrompt(roomType, currency, images.size()));
    for (byte[] image : images) {
      parts
          .addObject()
          .putObject("inlineData")
          .put("mimeType", "image/jpeg")
          .put("data", Base64.getEncoder().encodeToString(image));
    }

    ObjectNode generation = body.putObject("generationConfig");
    // Inventory extraction wants stability between runs, not creativity.
    generation.put("temperature", 0.0);
    generation.put("responseMimeType", "application/json");
    generation.set("responseSchema", prompts.responseSchema());

    // Room photos are benign; avoid spurious blocks on e.g. kitchen knives.
    body.putArray("safetySettings")
        .addObject()
        .put("category", "HARM_CATEGORY_DANGEROUS_CONTENT")
        .put("threshold", "BLOCK_ONLY_HIGH");
    return body;
  }
}
