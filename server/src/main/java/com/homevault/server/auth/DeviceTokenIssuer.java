package com.homevault.server.auth;

import com.homevault.server.config.HomeVaultProperties;
import com.homevault.server.config.JwtDecoderConfig;
import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/** Signs long-lived HS256 tokens for anonymous devices (auth mode {@code device}). */
@Component
@ConditionalOnProperty(prefix = "homevault.auth", name = "mode", havingValue = "device", matchIfMissing = true)
public class DeviceTokenIssuer {

  private final MACSigner signer;
  private final HomeVaultProperties.Auth auth;

  public DeviceTokenIssuer(HomeVaultProperties props) {
    this.auth = props.auth();
    try {
      this.signer = new MACSigner(JwtDecoderConfig.hmacKey(auth.secret()));
    } catch (JOSEException e) {
      throw new IllegalStateException("cannot build HS256 signer", e);
    }
  }

  public String issue(UUID userId, String deviceId) {
    Instant now = Instant.now();
    JWTClaimsSet claims =
        new JWTClaimsSet.Builder()
            .subject(userId.toString())
            .issuer(auth.issuer())
            .issueTime(Date.from(now))
            .expirationTime(Date.from(now.plus(auth.tokenTtl())))
            .claim("device_id", deviceId)
            .build();
    SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
    try {
      jwt.sign(signer);
    } catch (JOSEException e) {
      throw new IllegalStateException("cannot sign device token", e);
    }
    return jwt.serialize();
  }
}
