package com.homevault.server.quota;

import com.homevault.server.config.HomeVaultProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Drops idempotency-cache rows past their TTL (spec section 5.1: 24 h). */
@Component
public class CacheHousekeeping {

  private static final Logger log = LoggerFactory.getLogger(CacheHousekeeping.class);

  private final AnalysisCacheRepository cache;
  private final HomeVaultProperties props;

  public CacheHousekeeping(AnalysisCacheRepository cache, HomeVaultProperties props) {
    this.cache = cache;
    this.props = props;
  }

  @Scheduled(fixedDelayString = "${homevault.cache-purge-interval:PT1H}", initialDelayString = "PT1M")
  public void purgeExpired() {
    int removed = cache.purgeOlderThan(props.cacheTtl());
    if (removed > 0) log.info("analysis_cache purge removed={}", removed);
  }
}
