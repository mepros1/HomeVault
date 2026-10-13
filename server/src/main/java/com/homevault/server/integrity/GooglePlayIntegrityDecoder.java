package com.homevault.server.integrity;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/**
 * {@code POST https://playintegrity.googleapis.com/v1/{package}:decodeIntegrityToken}
 * authenticated with a service account that has the Play Integrity API scope.
 */
public class GooglePlayIntegrityDecoder implements PlayIntegrityDecoder {

  public static final String SCOPE = "https://www.googleapis.com/auth/playintegrity";

  private final URI endpoint;
  private final GoogleServiceAccount account;
  private final ObjectMapper mapper;
  private final HttpClient http;

  public GooglePlayIntegrityDecoder(String packageName, GoogleServiceAccount account, ObjectMapper mapper) {
    this(URI.create("https://playintegrity.googleapis.com/v1/" + packageName + ":decodeIntegrityToken"),
        account, mapper);
  }

  GooglePlayIntegrityDecoder(URI endpoint, GoogleServiceAccount account, ObjectMapper mapper) {
    this.endpoint = endpoint;
    this.account = account;
    this.mapper = mapper;
    this.http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
  }

  @Override
  public JsonNode decode(String integrityToken) throws IOException, InterruptedException {
    String body = mapper.writeValueAsString(mapper.createObjectNode().put("integrity_token", integrityToken));
    HttpRequest request =
        HttpRequest.newBuilder(endpoint)
            .timeout(Duration.ofSeconds(15))
            .header("Authorization", "Bearer " + account.accessToken())
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .build();
    HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
    if (response.statusCode() != 200) {
      throw new IOException("decodeIntegrityToken returned " + response.statusCode() + ": " + response.body());
    }
    JsonNode payload = mapper.readTree(response.body()).path("tokenPayloadExternal");
    if (payload.isMissingNode() || payload.isNull()) {
      throw new IOException("decodeIntegrityToken response lacks tokenPayloadExternal");
    }
    return payload;
  }
}
