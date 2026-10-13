package com.homevault.server.integrity;

import com.homevault.server.config.HomeVaultProperties;
import com.homevault.server.config.HomeVaultProperties.AppCheckMode;
import java.nio.file.Path;
import java.time.Clock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tools.jackson.databind.ObjectMapper;

/**
 * Builds the verifier from configuration. Refuses to start in ENFORCE mode
 * without a service account: silently rejecting every request would be
 * worse than failing fast.
 */
@Configuration
public class AppCheckConfig {

  private static final Logger log = LoggerFactory.getLogger(AppCheckConfig.class);

  @Bean
  AppCheckVerifier appCheckVerifier(HomeVaultProperties props, ObjectMapper mapper) throws Exception {
    HomeVaultProperties.AppCheck config = props.appCheck();
    if (config.mode() == AppCheckMode.OFF) {
      log.info("app_check mode=off");
      return new AppCheckVerifier(config, null, Clock.systemUTC());
    }
    if (config.serviceAccountFile().isBlank()) {
      if (config.mode() == AppCheckMode.ENFORCE) {
        throw new IllegalStateException("APP_CHECK_MODE=enforce needs PLAY_INTEGRITY_SERVICE_ACCOUNT_FILE");
      }
      log.warn("app_check mode=log without a service account: every request is logged as would_reject");
      return new AppCheckVerifier(config, null, Clock.systemUTC());
    }
    GoogleServiceAccount account =
        GoogleServiceAccount.fromFile(Path.of(config.serviceAccountFile()), GooglePlayIntegrityDecoder.SCOPE, mapper);
    log.info("app_check mode={} package={} service_account={}", config.mode(), config.packageName(),
        account.clientEmail());
    return new AppCheckVerifier(
        config, new GooglePlayIntegrityDecoder(config.packageName(), account, mapper), Clock.systemUTC());
  }
}
