package com.homevault.server.billing;

import com.homevault.server.api.ApiException;
import com.homevault.server.backup.BackupRepository;
import com.homevault.server.config.HomeVaultProperties;
import com.homevault.server.quota.EntitlementRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * RevenueCat webhook -> {@code entitlements}. The dashboard sends every event
 * with a fixed Authorization header value; that value is the shared secret.
 * The app configures RevenueCat with its device id as the app user id, which
 * is how {@code app_user_id} maps to {@code devices.user_id}.
 *
 * <p>Any 2xx stops RevenueCat's retries, so unknown users and irrelevant
 * event types are acknowledged and logged rather than rejected.
 */
@RestController
public class RevenueCatWebhookController {

  private static final Logger log = LoggerFactory.getLogger(RevenueCatWebhookController.class);

  private static final Set<String> GRANT_TYPES =
      Set.of(
          "INITIAL_PURCHASE",
          "NON_RENEWING_PURCHASE",
          "RENEWAL",
          "UNCANCELLATION",
          "PRODUCT_CHANGE",
          "SUBSCRIPTION_EXTENDED",
          "TEMPORARY_ENTITLEMENT_GRANT");

  private final HomeVaultProperties.RevenueCat config;
  private final EntitlementRepository entitlements;
  private final BackupRepository backups;

  public RevenueCatWebhookController(
      HomeVaultProperties props, EntitlementRepository entitlements, BackupRepository backups) {
    this.config = props.revenuecat();
    this.entitlements = entitlements;
    this.backups = backups;
  }

  @PostMapping("/v1/webhooks/revenuecat")
  @ResponseStatus(HttpStatus.OK)
  public void receive(
      @RequestHeader(value = "Authorization", required = false) String authorization,
      @RequestBody Map<String, Object> body) {
    if (config.webhookSecret().isBlank()) {
      throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "webhook_disabled", "webhook secret not configured");
    }
    if (!secretMatches(authorization)) {
      throw new ApiException(HttpStatus.UNAUTHORIZED, "unauthorized", "bad webhook secret");
    }
    Object eventObj = body.get("event");
    if (!(eventObj instanceof Map<?, ?> event)) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "bad_request", "missing event");
    }
    String type = string(event.get("type"));
    if (type == null || type.equals("TEST")) return;

    switch (type) {
      case "EXPIRATION" -> apply(event, false, type);
      case "CANCELLATION" -> {
        // A refund carries an expiration in the past; a plain cancellation
        // keeps access until EXPIRATION arrives.
        Long expiresAt = number(event.get("expiration_at_ms"));
        if (expiresAt != null && expiresAt <= System.currentTimeMillis()) apply(event, false, type);
      }
      case "TRANSFER" -> {
        // Pro moves with the purchase, and so do the report backups.
        List<UUID> from = new ArrayList<>();
        List<UUID> to = new ArrayList<>();
        for (String id : strings(event.get("transferred_from"))) {
          if (setPro(id, false, type)) entitlements.userIdForDevice(id).ifPresent(from::add);
        }
        for (String id : strings(event.get("transferred_to"))) {
          if (setPro(id, true, type)) entitlements.userIdForDevice(id).ifPresent(to::add);
        }
        if (from.size() == 1 && to.size() == 1) {
          int moved = backups.moveAll(from.get(0), to.get(0));
          if (moved > 0) log.info("revenuecat transfer moved backups={}", moved);
        }
      }
      default -> {
        if (GRANT_TYPES.contains(type)) {
          List<String> granted = strings(event.get("entitlement_ids"));
          if (granted.contains(config.entitlementId())) apply(event, true, type);
        } else {
          log.info("revenuecat event={} ignored", type);
        }
      }
    }
  }

  private void apply(Map<?, ?> event, boolean pro, String type) {
    List<String> ids = new ArrayList<>();
    String primary = string(event.get("app_user_id"));
    if (primary != null) ids.add(primary);
    ids.addAll(strings(event.get("aliases")));
    for (String id : ids) {
      if (setPro(id, pro, type)) return;
    }
    log.warn("revenuecat event={} no known device among {} ids", type, ids.size());
  }

  private boolean setPro(String appUserId, boolean pro, String type) {
    Optional<UUID> user = entitlements.userIdForDevice(appUserId);
    if (user.isEmpty()) return false;
    entitlements.setPro(user.get(), pro);
    log.info("revenuecat event={} user_id={} is_pro={}", type, user.get(), pro);
    return true;
  }

  private boolean secretMatches(String authorization) {
    if (authorization == null) return false;
    String presented = authorization.startsWith("Bearer ") ? authorization.substring(7) : authorization;
    return MessageDigest.isEqual(
        presented.getBytes(StandardCharsets.UTF_8), config.webhookSecret().getBytes(StandardCharsets.UTF_8));
  }

  private static String string(Object o) {
    return o instanceof String s && !s.isBlank() ? s : null;
  }

  private static Long number(Object o) {
    return o instanceof Number n ? n.longValue() : null;
  }

  private static List<String> strings(Object o) {
    List<String> out = new ArrayList<>();
    if (o instanceof List<?> list) {
      for (Object item : list) if (item instanceof String s) out.add(s);
    }
    return out;
  }
}
