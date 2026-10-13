package com.homevault.server.api;

import com.homevault.server.analysis.AnalysisService;
import com.homevault.server.analysis.AnalyzeRoomResponse;
import com.homevault.server.integrity.AppCheckVerifier;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/** {@code POST /v1/analyze-room} — the contract from spec section 5.1. */
@RestController
public class AnalyzeRoomController {

  private final AnalysisService analysis;
  private final AppCheckVerifier appCheck;

  public AnalyzeRoomController(AnalysisService analysis, AppCheckVerifier appCheck) {
    this.analysis = analysis;
    this.appCheck = appCheck;
  }

  @PostMapping(value = "/v1/analyze-room", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public AnalyzeRoomResponse analyze(
      @AuthenticationPrincipal Jwt jwt,
      @RequestParam(value = "room_type", required = false) String roomType,
      @RequestParam(value = "currency", required = false) String currency,
      @RequestParam(value = "images[]", required = false) List<MultipartFile> bracketImages,
      @RequestParam(value = "images", required = false) List<MultipartFile> plainImages,
      @RequestHeader(value = "X-Idempotency-Key", required = false) String idempotencyKey,
      @RequestHeader(value = AppCheckVerifier.HEADER, required = false) String appCheckToken) {

    // The token is bound to the idempotency key the app computed, so it
    // cannot be reused for a different set of photos.
    appCheck.verify(appCheckToken, idempotencyKey, "analyze");

    List<MultipartFile> files = new ArrayList<>();
    if (bracketImages != null) files.addAll(bracketImages);
    if (plainImages != null) files.addAll(plainImages);

    List<byte[]> images = new ArrayList<>(files.size());
    for (MultipartFile f : files) {
      try {
        images.add(f.getBytes());
      } catch (IOException e) {
        throw new ApiException(HttpStatus.BAD_REQUEST, "bad_request", "unreadable upload");
      }
    }

    UUID userId = UUID.fromString(jwt.getSubject());
    return analysis.analyze(
        userId,
        new AnalysisService.Request(roomType, currency, images, idempotencyKey));
  }
}
