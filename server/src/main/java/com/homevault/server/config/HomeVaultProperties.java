package com.homevault.server.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/** Typed view of the {@code homevault.*} block in application.yml. */
@ConfigurationProperties(prefix = "homevault")
public record HomeVaultProperties(
    Auth auth,
    Gemini gemini,
    Quota quota,
    RateLimit rateLimit,
    RevenueCat revenuecat,
    AppCheck appCheck,
    Backup backup,
    @DefaultValue("24h") Duration cacheTtl,
    @DefaultValue("8") int maxImages,
    @DefaultValue("409600") int maxImageBytes) {

  public enum AuthMode {
    DEVICE,
    SUPABASE
  }

  public record Auth(
      @DefaultValue("device") AuthMode mode,
      @DefaultValue("") String secret,
      @DefaultValue("homevault") String issuer,
      @DefaultValue("365d") Duration tokenTtl,
      @DefaultValue("") String jwkSetUri) {}

  public record Gemini(
      @DefaultValue("") String apiKey,
      @DefaultValue("gemini-3.1-flash-lite") String model,
      @DefaultValue("40s") Duration timeout,
      /** Development only: return canned items instead of calling the model. */
      @DefaultValue("false") boolean mock) {}

  public record Quota(
      @DefaultValue("3") int freePerMonth,
      @DefaultValue("300") int proPerMonth,
      /** Global analyses per UTC day across all users; 0 disables the fuse. */
      @DefaultValue("2000") int dailyBudget) {}

  public record RateLimit(
      @DefaultValue("20") int devicesPerHourPerIp,
      @DefaultValue("120") int analyzePerHourPerIp,
      /** Only behind a proxy that overwrites X-Forwarded-For. */
      @DefaultValue("false") boolean trustForwardedFor) {}

  public enum AppCheckMode {
    /** Header ignored, Google never called. */
    OFF,
    /** Verified and logged; requests always pass. Use while rolling out. */
    LOG,
    /** Missing or bad token -> 403 app_check_failed. */
    ENFORCE
  }

  /** Play Integrity verification of {@code X-App-Check} (spec section 6). */
  public record AppCheck(
      @DefaultValue("off") AppCheckMode mode,
      @DefaultValue("com.homevault.app") String packageName,
      /** Path to a Google service-account JSON key with the Play Integrity API scope. */
      @DefaultValue("") String serviceAccountFile,
      /** Tokens older than this are rejected (replay window). */
      @DefaultValue("10m") Duration maxTokenAge) {}

  /** Cloud backup of PDF reports (see BackupController). */
  public record Backup(
      @DefaultValue("20") int maxPerUser,
      @DefaultValue("8388608") int maxFileBytes,
      @DefaultValue("104857600") long maxTotalBytes,
      @DefaultValue("15m") Duration transferCodeTtl,
      /** Backups of devices not seen for this long are deleted. */
      @DefaultValue("365d") Duration retention) {}

  public record RevenueCat(
      /** Authorization header value configured in the RevenueCat dashboard; empty disables the webhook. */
      @DefaultValue("") String webhookSecret,
      @DefaultValue("pro") String entitlementId) {}
}
