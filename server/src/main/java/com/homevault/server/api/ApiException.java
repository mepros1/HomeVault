package com.homevault.server.api;

import java.util.Map;
import org.springframework.http.HttpStatus;

/** An error the client is expected to handle per the table in spec section 5.1. */
public class ApiException extends RuntimeException {

  private final HttpStatus status;
  private final String code;
  private final Map<String, Object> extra;

  public ApiException(HttpStatus status, String code, String message) {
    this(status, code, message, Map.of());
  }

  public ApiException(HttpStatus status, String code, String message, Map<String, Object> extra) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }

  public HttpStatus status() {
    return status;
  }

  public String code() {
    return code;
  }

  public Map<String, Object> extra() {
    return extra;
  }
}
