package com.homevault.server.analysis;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/**
 * Loads the versioned system prompt and the structured-output schema from resources.
 *
 * <p>The prompt file starts with a {@code version: <id>} line, then {@code ---}, then the
 * prompt text. The version is returned to the app and stored per item so recognition
 * quality can be compared between prompt revisions. Bump it on every wording change.
 */
@Component
public class PromptRegistry {

  private static final String PROMPT_PATH = "prompts/analyze-room.txt";
  private static final String SCHEMA_PATH = "prompts/analyze-room-response.schema.json";

  private final String version;
  private final String systemPrompt;
  private final JsonNode responseSchema;

  public PromptRegistry(ObjectMapper mapper) {
    String raw = read(PROMPT_PATH);
    int sep = raw.indexOf("\n---\n");
    if (!raw.startsWith("version:") || sep < 0) {
      throw new IllegalStateException(PROMPT_PATH + " must start with 'version: <id>' and '---'");
    }
    this.version = raw.substring("version:".length(), sep).trim();
    this.systemPrompt = raw.substring(sep + "\n---\n".length()).trim();
    this.responseSchema = mapper.readTree(read(SCHEMA_PATH));
  }

  public String version() {
    return version;
  }

  public String systemPrompt() {
    return systemPrompt;
  }

  public JsonNode responseSchema() {
    return responseSchema;
  }

  public String userPrompt(String roomType, String currency, int imageCount) {
    return "Room type: %s. Currency for estimates: %s. Number of photographs: %d (indices 0 to %d). Produce the deduplicated inventory."
        .formatted(roomType, currency, imageCount, imageCount - 1);
  }

  private static String read(String path) {
    try (InputStream in = new ClassPathResource(path).getInputStream()) {
      return new String(in.readAllBytes(), StandardCharsets.UTF_8).replace("\r\n", "\n");
    } catch (IOException e) {
      throw new IllegalStateException("cannot read " + path, e);
    }
  }
}
