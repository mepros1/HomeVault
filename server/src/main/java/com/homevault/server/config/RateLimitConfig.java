package com.homevault.server.config;

import com.homevault.server.api.RateLimitFilter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RateLimitConfig {

  @Bean
  RateLimitFilter rateLimitFilter(HomeVaultProperties props) {
    return new RateLimitFilter(props);
  }
}
