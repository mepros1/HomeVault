package com.homevault.server.config;

import java.nio.charset.StandardCharsets;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

/**
 * Picks how bearer tokens are verified:
 *
 * <ul>
 *   <li>{@code device}: HS256 tokens signed by this server with {@code homevault.auth.secret}
 *   <li>{@code supabase}: Supabase Auth tokens verified against the project JWKS (ES256/RS256)
 * </ul>
 */
@Configuration
public class JwtDecoderConfig {

  @Bean
  JwtDecoder jwtDecoder(HomeVaultProperties props) {
    var auth = props.auth();
    return switch (auth.mode()) {
      case DEVICE -> {
        NimbusJwtDecoder decoder =
            NimbusJwtDecoder.withSecretKey(hmacKey(auth.secret()))
                .macAlgorithm(MacAlgorithm.HS256)
                .build();
        decoder.setJwtValidator(JwtValidators.createDefaultWithIssuer(auth.issuer()));
        yield decoder;
      }
      case SUPABASE -> {
        if (auth.jwkSetUri().isBlank()) {
          throw new IllegalStateException(
              "homevault.auth.jwk-set-uri is required in supabase mode");
        }
        yield NimbusJwtDecoder.withJwkSetUri(auth.jwkSetUri())
            .jwsAlgorithms(
                algs -> {
                  algs.add(SignatureAlgorithm.ES256);
                  algs.add(SignatureAlgorithm.RS256);
                })
            .build();
      }
    };
  }

  public static SecretKey hmacKey(String secret) {
    byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
    if (bytes.length < 32) {
      throw new IllegalStateException(
          "homevault.auth.secret must be at least 32 bytes (set AUTH_SECRET)");
    }
    return new SecretKeySpec(bytes, "HmacSHA256");
  }
}
