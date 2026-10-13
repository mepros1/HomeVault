package com.homevault.server.api;

import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

/** Renders every error as {@code {"error": code, "message": text, ...}}. */
@RestControllerAdvice
public class ApiExceptionHandler {

  private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

  @ExceptionHandler(ApiException.class)
  ResponseEntity<Map<String, Object>> api(ApiException e) {
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("error", e.code());
    body.put("message", e.getMessage());
    body.putAll(e.extra());
    return ResponseEntity.status(e.status()).body(body);
  }

  @ExceptionHandler(MaxUploadSizeExceededException.class)
  ResponseEntity<Map<String, Object>> tooLarge(MaxUploadSizeExceededException e) {
    return api(
        new ApiException(
            HttpStatus.PAYLOAD_TOO_LARGE, "payload_too_large", "upload exceeds the size limit"));
  }

  @ExceptionHandler(MethodArgumentNotValidException.class)
  ResponseEntity<Map<String, Object>> invalid(MethodArgumentNotValidException e) {
    return api(new ApiException(HttpStatus.BAD_REQUEST, "bad_request", "invalid request body"));
  }

  @ExceptionHandler(Exception.class)
  ResponseEntity<Map<String, Object>> unexpected(Exception e) {
    log.error("unhandled error", e);
    return api(
        new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "internal", "unexpected failure"));
  }
}
