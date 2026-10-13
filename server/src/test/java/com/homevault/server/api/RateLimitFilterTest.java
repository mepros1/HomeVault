package com.homevault.server.api;

import static org.assertj.core.api.Assertions.assertThat;

import com.homevault.server.config.HomeVaultProperties;
import jakarta.servlet.FilterChain;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class RateLimitFilterTest {

  private static HomeVaultProperties props(int devices, int analyze, boolean trustXff) {
    return new HomeVaultProperties(
        new HomeVaultProperties.Auth(HomeVaultProperties.AuthMode.DEVICE, "", "homevault", Duration.ofDays(1), ""),
        new HomeVaultProperties.Gemini("", "m", Duration.ofSeconds(1), true),
        new HomeVaultProperties.Quota(3, 300, 0),
        new HomeVaultProperties.RateLimit(devices, analyze, trustXff),
        new HomeVaultProperties.RevenueCat("", "pro"),
        new HomeVaultProperties.AppCheck(
            HomeVaultProperties.AppCheckMode.OFF, "com.homevault.app", "", Duration.ofMinutes(10)),
        new HomeVaultProperties.Backup(20, 8_388_608, 104_857_600L, Duration.ofMinutes(15), Duration.ofDays(365)),
        Duration.ofHours(24),
        8,
        409600);
  }

  private static MockHttpServletRequest post(String uri, String ip) {
    MockHttpServletRequest r = new MockHttpServletRequest("POST", uri);
    r.setRemoteAddr(ip);
    return r;
  }

  @Test
  void blocksTheThirdDeviceRegistrationFromOneIpWithinTheHour() throws Exception {
    Clock clock = Clock.fixed(Instant.parse("2026-09-27T10:00:00Z"), ZoneOffset.UTC);
    RateLimitFilter filter = new RateLimitFilter(props(2, 100, false), clock);
    AtomicInteger passed = new AtomicInteger();
    FilterChain chain = (req, res) -> passed.incrementAndGet();

    for (int i = 0; i < 2; i++) {
      MockHttpServletResponse res = new MockHttpServletResponse();
      filter.doFilter(post("/v1/devices", "1.2.3.4"), res, chain);
      assertThat(res.getStatus()).isEqualTo(200);
    }
    MockHttpServletResponse blocked = new MockHttpServletResponse();
    filter.doFilter(post("/v1/devices", "1.2.3.4"), blocked, chain);
    assertThat(blocked.getStatus()).isEqualTo(429);
    assertThat(blocked.getContentAsString()).contains("rate_limited");
    assertThat(passed.get()).isEqualTo(2);

    // Another IP and another endpoint have their own windows.
    MockHttpServletResponse other = new MockHttpServletResponse();
    filter.doFilter(post("/v1/devices", "5.6.7.8"), other, chain);
    assertThat(other.getStatus()).isEqualTo(200);
    MockHttpServletResponse analyze = new MockHttpServletResponse();
    filter.doFilter(post("/v1/analyze-room", "1.2.3.4"), analyze, chain);
    assertThat(analyze.getStatus()).isEqualTo(200);
  }

  @Test
  void ignoresUnlimitedEndpointsAndHonoursForwardedForOnlyWhenTrusted() throws Exception {
    Clock clock = Clock.fixed(Instant.parse("2026-09-27T10:00:00Z"), ZoneOffset.UTC);
    RateLimitFilter trusting = new RateLimitFilter(props(1, 1, true), clock);
    RateLimitFilter plain = new RateLimitFilter(props(1, 1, false), clock);

    MockHttpServletRequest r = post("/v1/devices", "10.0.0.1");
    r.addHeader("X-Forwarded-For", "203.0.113.9, 10.0.0.1");
    assertThat(trusting.clientIp(r)).isEqualTo("203.0.113.9");
    assertThat(plain.clientIp(r)).isEqualTo("10.0.0.1");

    AtomicInteger passed = new AtomicInteger();
    MockHttpServletResponse res = new MockHttpServletResponse();
    plain.doFilter(new MockHttpServletRequest("GET", "/actuator/health"), res, (q, s) -> passed.incrementAndGet());
    assertThat(passed.get()).isEqualTo(1);
  }
}
