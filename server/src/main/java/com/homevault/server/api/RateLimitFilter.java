package com.homevault.server.api;

import com.homevault.server.config.HomeVaultProperties;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.core.annotation.Order;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Per-IP fixed-window limits on the two endpoints that cost money. A fuse,
 * not a fairness scheme: real abuse protection is Play Integrity. State is
 * in-memory, so with several server instances the effective limit is
* multiplied by the instance count; acceptable at v1 scale. Registered in
 * {@link com.homevault.server.config.RateLimitConfig}, not component-scanned,
 * so @WebMvcTest slices stay free of it.
 */
@Order(1)
public class RateLimitFilter extends OncePerRequestFilter {

  private record Window(long startEpochMinute, AtomicInteger count) {}

  private final HomeVaultProperties.RateLimit config;
  private final Clock clock;
  private final Map<String, Window> windows = new ConcurrentHashMap<>();
  private volatile Instant lastSweep;

  public RateLimitFilter(HomeVaultProperties props) {
    this(props, Clock.systemUTC());
  }

  RateLimitFilter(HomeVaultProperties props, Clock clock) {
    this.config = props.rateLimit();
    this.clock = clock;
    this.lastSweep = clock.instant();
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {
    int limit = limitFor(request);
    if (limit <= 0) {
      chain.doFilter(request, response);
      return;
    }
    String key = request.getRequestURI() + "|" + clientIp(request);
    if (!allow(key, limit)) {
      response.setStatus(429);
      response.setContentType("application/json");
      response.setHeader("Retry-After", "3600");
      response.getWriter().write("{\"error\":\"rate_limited\",\"message\":\"Too many requests from this network, try again later\"}");
      return;
    }
    chain.doFilter(request, response);
  }

  private int limitFor(HttpServletRequest request) {
    if (!"POST".equals(request.getMethod())) return 0;
    return switch (request.getRequestURI()) {
      case "/v1/devices" -> config.devicesPerHourPerIp();
      case "/v1/analyze-room" -> config.analyzePerHourPerIp();
      default -> 0;
    };
  }

  boolean allow(String key, int limit) {
    long hour = clock.instant().getEpochSecond() / 3600;
    Window w = windows.compute(key, (k, old) ->
        old == null || old.startEpochMinute() != hour ? new Window(hour, new AtomicInteger()) : old);
    boolean allowed = w.count().incrementAndGet() <= limit;
    sweepIfDue(hour);
    return allowed;
  }

  private void sweepIfDue(long currentHour) {
    Instant now = clock.instant();
    if (Duration.between(lastSweep, now).toMinutes() < 10) return;
    lastSweep = now;
    windows.entrySet().removeIf(e -> e.getValue().startEpochMinute() != currentHour);
  }

  /** First hop of X-Forwarded-For when the app sits behind a trusted proxy. */
  String clientIp(HttpServletRequest request) {
    if (config.trustForwardedFor()) {
      String xff = request.getHeader("X-Forwarded-For");
      if (xff != null && !xff.isBlank()) return xff.split(",")[0].trim();
    }
    return request.getRemoteAddr();
  }
}
