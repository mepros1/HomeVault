package com.homevault.server.integrity;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

class GoogleServiceAccountTest {

  @Test
  void parsesTheKeyFileAndSignsAVerifiableAssertion() throws Exception {
    KeyPairGenerator gen = KeyPairGenerator.getInstance("RSA");
    gen.initialize(2048);
    KeyPair pair = gen.generateKeyPair();
    String pem =
        "-----BEGIN PRIVATE KEY-----\n"
            + Base64.getMimeEncoder(64, "\n".getBytes()).encodeToString(pair.getPrivate().getEncoded())
            + "\n-----END PRIVATE KEY-----\n";
    ObjectMapper mapper = new ObjectMapper();
    String json =
        mapper.writeValueAsString(
            mapper.createObjectNode()
                .put("type", "service_account")
                .put("client_email", "svc@project.iam.gserviceaccount.com")
                .put("private_key", pem)
                .put("token_uri", "https://oauth2.googleapis.com/token"));
    Instant now = Instant.parse("2026-09-27T12:00:00Z");

    GoogleServiceAccount account =
        GoogleServiceAccount.fromJson(json, GooglePlayIntegrityDecoder.SCOPE, mapper, Clock.fixed(now, ZoneOffset.UTC));
    String assertion = account.assertion(now);

    String[] parts = assertion.split("\\.");
    assertThat(parts).hasSize(3);
    Base64.Decoder b64 = Base64.getUrlDecoder();
    JsonNode header = mapper.readTree(b64.decode(parts[0]));
    JsonNode claims = mapper.readTree(b64.decode(parts[1]));
    assertThat(header.path("alg").asString()).isEqualTo("RS256");
    assertThat(claims.path("iss").asString()).isEqualTo("svc@project.iam.gserviceaccount.com");
    assertThat(claims.path("scope").asString()).isEqualTo(GooglePlayIntegrityDecoder.SCOPE);
    assertThat(claims.path("aud").asString()).isEqualTo("https://oauth2.googleapis.com/token");
    assertThat(claims.path("exp").asLong() - claims.path("iat").asLong()).isEqualTo(3600);

    Signature verifier = Signature.getInstance("SHA256withRSA");
    verifier.initVerify(pair.getPublic());
    verifier.update((parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII));
    assertThat(verifier.verify(b64.decode(parts[2]))).isTrue();
  }
}
