package com.homevault.server.integrity;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/**
 * Minimal OAuth 2.0 service-account client (JWT bearer grant, RFC 7523):
 * enough to call one Google API without pulling in the Google auth library.
 * Access tokens are cached until shortly before they expire.
 */
public class GoogleServiceAccount {

  private static final String GRANT = "urn:ietf:params:oauth:grant-type:jwt-bearer";
  private static final Base64.Encoder B64 = Base64.getUrlEncoder().withoutPadding();

  private final String clientEmail;
  private final PrivateKey privateKey;
  private final URI tokenUri;
  private final String scope;
  private final HttpClient http;
  private final ObjectMapper mapper;
  private final Clock clock;

  private volatile String cachedToken;
  private volatile Instant cachedUntil = Instant.EPOCH;

  public static GoogleServiceAccount fromFile(Path keyFile, String scope, ObjectMapper mapper)
      throws IOException, GeneralSecurityException {
    return fromJson(Files.readString(keyFile), scope, mapper, Clock.systemUTC());
  }

  public static GoogleServiceAccount fromJson(String json, String scope, ObjectMapper mapper, Clock clock)
      throws GeneralSecurityException {
    JsonNode key = mapper.readTree(json);
    String email = key.path("client_email").asString();
    String pem = key.path("private_key").asString();
    String tokenUri = key.path("token_uri").asString("https://oauth2.googleapis.com/token");
    if (email.isBlank() || pem.isBlank()) {
      throw new IllegalArgumentException("service account JSON lacks client_email or private_key");
    }
    return new GoogleServiceAccount(email, parsePkcs8(pem), URI.create(tokenUri), scope, mapper, clock);
  }

  GoogleServiceAccount(
      String clientEmail, PrivateKey privateKey, URI tokenUri, String scope, ObjectMapper mapper, Clock clock) {
    this.clientEmail = clientEmail;
    this.privateKey = privateKey;
    this.tokenUri = tokenUri;
    this.scope = scope;
    this.mapper = mapper;
    this.clock = clock;
    this.http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
  }

  public String clientEmail() {
    return clientEmail;
  }

  /** A bearer access token for {@code scope}, fetched or reused. */
  public String accessToken() throws IOException, InterruptedException {
    Instant now = clock.instant();
    String token = cachedToken;
    if (token != null && now.isBefore(cachedUntil)) return token;
    synchronized (this) {
      if (cachedToken != null && clock.instant().isBefore(cachedUntil)) return cachedToken;
      String body =
          "grant_type=" + URLEncoder.encode(GRANT, StandardCharsets.UTF_8)
              + "&assertion=" + assertion(clock.instant());
      HttpRequest request =
          HttpRequest.newBuilder(tokenUri)
              .timeout(Duration.ofSeconds(15))
              .header("Content-Type", "application/x-www-form-urlencoded")
              .POST(HttpRequest.BodyPublishers.ofString(body))
              .build();
      HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
      if (response.statusCode() != 200) {
        throw new IOException("token endpoint returned " + response.statusCode() + ": " + response.body());
      }
      JsonNode json = mapper.readTree(response.body());
      String access = json.path("access_token").asString();
      long expiresIn = json.path("expires_in").asLong(3600);
      if (access.isBlank()) throw new IOException("token endpoint returned no access_token");
      cachedToken = access;
      cachedUntil = clock.instant().plusSeconds(Math.max(expiresIn - 60, 30));
      return access;
    }
  }

  /** The signed JWT assertion for the token request (package-private for tests). */
  String assertion(Instant now) {
    String header = B64.encodeToString("{\"alg\":\"RS256\",\"typ\":\"JWT\"}".getBytes(StandardCharsets.UTF_8));
    String claims =
        mapper.writeValueAsString(
            mapper.createObjectNode()
                .put("iss", clientEmail)
                .put("scope", scope)
                .put("aud", tokenUri.toString())
                .put("iat", now.getEpochSecond())
                .put("exp", now.plusSeconds(3600).getEpochSecond()));
    String signingInput = header + "." + B64.encodeToString(claims.getBytes(StandardCharsets.UTF_8));
    try {
      Signature sig = Signature.getInstance("SHA256withRSA");
      sig.initSign(privateKey);
      sig.update(signingInput.getBytes(StandardCharsets.US_ASCII));
      return signingInput + "." + B64.encodeToString(sig.sign());
    } catch (GeneralSecurityException e) {
      throw new IllegalStateException("cannot sign service-account assertion", e);
    }
  }

  static PrivateKey parsePkcs8(String pem) throws GeneralSecurityException {
    String base64 =
        pem.replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replaceAll("\\s", "");
    byte[] der = Base64.getDecoder().decode(base64);
    return KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(der));
  }
}
