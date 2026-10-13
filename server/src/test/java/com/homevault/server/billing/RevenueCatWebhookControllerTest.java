package com.homevault.server.billing;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.homevault.server.config.SecurityConfig;
import com.homevault.server.quota.EntitlementRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(RevenueCatWebhookController.class)
@Import({SecurityConfig.class, RevenueCatWebhookControllerTest.Props.class})
@TestPropertySource(properties = "homevault.revenuecat.webhook-secret=s3cret")
class RevenueCatWebhookControllerTest {

  @EnableConfigurationProperties(com.homevault.server.config.HomeVaultProperties.class)
  static class Props {}

  private static final UUID USER = UUID.randomUUID();

  @Autowired MockMvc mvc;
  @MockitoBean EntitlementRepository entitlements;
  @MockitoBean com.homevault.server.backup.BackupRepository backups;
  @MockitoBean JwtDecoder jwtDecoder;

  private static String event(String type, String extra) {
    return """
        {"api_version":"1.0","event":{"type":"%s","app_user_id":"device-1",
         "aliases":["$RCAnonymousID:abc","device-1"],"entitlement_ids":["pro"],
         "product_id":"homevault_pro_lifetime"%s}}
        """.formatted(type, extra);
  }

  private org.springframework.test.web.servlet.ResultActions send(String body, String auth) throws Exception {
    var req = post("/v1/webhooks/revenuecat").contentType(MediaType.APPLICATION_JSON).content(body);
    if (auth != null) req = req.header("Authorization", auth);
    return mvc.perform(req);
  }

  @Test
  void rejectsMissingOrWrongSecretWithoutTouchingEntitlements() throws Exception {
    send(event("INITIAL_PURCHASE", ""), null).andExpect(status().isUnauthorized());
    send(event("INITIAL_PURCHASE", ""), "Bearer nope").andExpect(status().isUnauthorized());
    verify(entitlements, never()).setPro(any(), anyBoolean());
  }

  @Test
  void grantsProOnPurchaseAndRevokesOnExpiration() throws Exception {
    when(entitlements.userIdForDevice("device-1")).thenReturn(Optional.of(USER));

    send(event("NON_RENEWING_PURCHASE", ""), "Bearer s3cret").andExpect(status().isOk());
    verify(entitlements).setPro(USER, true);

    send(event("EXPIRATION", ""), "s3cret").andExpect(status().isOk());
    verify(entitlements).setPro(USER, false);
  }

  @Test
  void refundRevokesButPlainCancellationDoesNot() throws Exception {
    when(entitlements.userIdForDevice("device-1")).thenReturn(Optional.of(USER));

    send(event("CANCELLATION", ",\"expiration_at_ms\":4102444800000"), "s3cret").andExpect(status().isOk());
    verify(entitlements, never()).setPro(any(), anyBoolean());

    send(event("CANCELLATION", ",\"expiration_at_ms\":1600000000000"), "s3cret").andExpect(status().isOk());
    verify(entitlements).setPro(USER, false);
  }

  @Test
  void acknowledgesUnknownUsersOtherEntitlementsAndTestEvents() throws Exception {
    when(entitlements.userIdForDevice(any())).thenReturn(Optional.empty());
    send(event("INITIAL_PURCHASE", ""), "s3cret").andExpect(status().isOk());
    send("{\"event\":{\"type\":\"TEST\"}}", "s3cret").andExpect(status().isOk());

    when(entitlements.userIdForDevice("device-1")).thenReturn(Optional.of(USER));
    send(
            """
            {"event":{"type":"INITIAL_PURCHASE","app_user_id":"device-1","entitlement_ids":["other"]}}
            """,
            "s3cret")
        .andExpect(status().isOk());
    verify(entitlements, never()).setPro(eq(USER), anyBoolean());
  }
}
