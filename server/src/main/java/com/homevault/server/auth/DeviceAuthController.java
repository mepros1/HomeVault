package com.homevault.server.auth;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.homevault.server.integrity.AppCheckVerifier;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

/**
 * Anonymous device registration (auth mode {@code device}).
 *
 * <p>{@code POST /v1/devices} with {@code {"device_id": "<uuid generated on first launch>"}}
 * returns a bearer token the app stores and sends on every later call. Re-registering the
 * same device id requires the original device secret before a fresh token is issued.
 * The optional {@code X-App-Check}
 * header carries a Play Integrity token bound to the device id; see {@link AppCheckVerifier}.
 */
@RestController
@ConditionalOnBean(DeviceTokenIssuer.class)
public class DeviceAuthController {

  public record RegisterRequest(
      @JsonProperty("device_id") @NotBlank @Size(max = 128) String deviceId,
      @JsonProperty("device_secret") @NotBlank @Size(min = 43, max = 128)
          @Pattern(regexp = "[A-Za-z0-9_-]+") String deviceSecret,
      @Size(max = 32) String platform) {}

  public record RegisterResponse(
      @JsonProperty("access_token") String accessToken,
      @JsonProperty("token_type") String tokenType,
      @JsonProperty("user_id") UUID userId) {}

  private final DeviceRepository devices;
  private final DeviceTokenIssuer issuer;
  private final AppCheckVerifier appCheck;

  public DeviceAuthController(DeviceRepository devices, DeviceTokenIssuer issuer, AppCheckVerifier appCheck) {
    this.devices = devices;
    this.issuer = issuer;
    this.appCheck = appCheck;
  }

  @PostMapping("/v1/devices")
  public RegisterResponse register(
      @RequestHeader(value = AppCheckVerifier.HEADER, required = false) String appCheckToken,
      @Valid @RequestBody RegisterRequest request) {
    appCheck.verify(appCheckToken, request.deviceId(), "devices");
    UUID userId = devices.registerOrTouch(request.deviceId(), request.platform(), request.deviceSecret());
    return new RegisterResponse(issuer.issue(userId, request.deviceId()), "Bearer", userId);
  }
}
