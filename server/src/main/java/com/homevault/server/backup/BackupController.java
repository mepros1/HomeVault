package com.homevault.server.backup;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.homevault.server.api.ApiException;
import com.homevault.server.config.HomeVaultProperties;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * Cloud backup of PDF reports, keyed by the device's user id. Photos and the
 * inventory itself never come here. A transfer code moves the backups to a
 * new device (the RevenueCat TRANSFER webhook does the same for Pro users
 * who restore their purchase).
 */
@RestController
public class BackupController {

  public record BackupJson(
      UUID id,
      @JsonProperty("file_name") String fileName,
      @JsonProperty("size_bytes") int sizeBytes,
      String sha256,
      @JsonProperty("generated_at") OffsetDateTime generatedAt,
      @JsonProperty("item_count") int itemCount,
      @JsonProperty("total_low") BigDecimal totalLow,
      @JsonProperty("total_high") BigDecimal totalHigh,
      @JsonProperty("created_at") OffsetDateTime createdAt) {

    static BackupJson of(BackupRepository.Summary s) {
      return new BackupJson(s.id(), s.fileName(), s.sizeBytes(), s.sha256(), s.generatedAt(), s.itemCount(),
          s.totalLow(), s.totalHigh(), s.createdAt());
    }
  }

  public record ListJson(List<BackupJson> backups, @JsonProperty("max_count") int maxCount,
      @JsonProperty("max_total_bytes") long maxTotalBytes) {}

  public record TransferCodeJson(String code, @JsonProperty("expires_at") OffsetDateTime expiresAt) {}

  public record ClaimRequest(@NotBlank @Size(max = 16) String code) {}

  public record ClaimJson(int moved) {}

  private static final byte[] PDF_MAGIC = "%PDF".getBytes(StandardCharsets.US_ASCII);

  private final HomeVaultProperties.Backup config;
  private final BackupRepository backups;

  public BackupController(HomeVaultProperties props, BackupRepository backups) {
    this.config = props.backup();
    this.backups = backups;
  }

  @GetMapping("/v1/backups")
  public ListJson list(@AuthenticationPrincipal Jwt jwt) {
    List<BackupJson> items = backups.list(user(jwt)).stream().map(BackupJson::of).toList();
    return new ListJson(items, config.maxPerUser(), config.maxTotalBytes());
  }

  @PostMapping(value = "/v1/backups", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public BackupJson upload(
      @AuthenticationPrincipal Jwt jwt,
      @RequestParam("id") UUID id,
      @RequestParam("file_name") String fileName,
      @RequestParam("generated_at") OffsetDateTime generatedAt,
      @RequestParam(value = "item_count", defaultValue = "0") int itemCount,
      @RequestParam(value = "total_low", defaultValue = "0") BigDecimal totalLow,
      @RequestParam(value = "total_high", defaultValue = "0") BigDecimal totalHigh,
      @RequestParam("file") MultipartFile file) {
    UUID userId = user(jwt);
    byte[] content;
    try {
      content = file.getBytes();
    } catch (IOException e) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "bad_request", "unreadable upload");
    }
    if (content.length > config.maxFileBytes()) {
      throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "payload_too_large", "report exceeds the size limit");
    }
    if (content.length < PDF_MAGIC.length || !startsWith(content, PDF_MAGIC)) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "bad_request", "not a PDF");
    }
    if (fileName.isBlank() || fileName.length() > 200 || fileName.contains("/") || fileName.contains("\\")) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "bad_request", "bad file name");
    }
    backups.ownerOf(id).ifPresent(owner -> {
      if (!owner.equals(userId)) throw new ApiException(HttpStatus.CONFLICT, "conflict", "backup id in use");
    });
    boolean replacing = backups.ownerOf(id).isPresent();
    BackupRepository.Usage usage = backups.usage(userId);
    if (!replacing && usage.count() >= config.maxPerUser()) {
      throw new ApiException(HttpStatus.CONFLICT, "backup_limit", "backup limit reached, delete an older report",
          Map.of("max_count", config.maxPerUser()));
    }
    long oldSize = replacing ? backups.get(userId, id).map(b -> (long) b.summary().sizeBytes()).orElse(0L) : 0L;
    if (usage.bytes() - oldSize + content.length > config.maxTotalBytes()) {
      throw new ApiException(HttpStatus.CONFLICT, "backup_limit", "backup storage is full, delete an older report",
          Map.of("max_total_bytes", config.maxTotalBytes()));
    }
    var meta = new BackupRepository.Summary(id, fileName, content.length, sha256Hex(content), generatedAt, itemCount,
        totalLow, totalHigh, null);
    return BackupJson.of(backups.upsert(userId, meta, content));
  }

  @GetMapping("/v1/backups/{id}")
  public ResponseEntity<byte[]> download(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
    BackupRepository.Stored stored = backups.get(user(jwt), id)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "no such backup"));
    return ResponseEntity.ok()
        .contentType(MediaType.APPLICATION_PDF)
        .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + stored.summary().fileName() + "\"")
        .body(stored.content());
  }

  @DeleteMapping("/v1/backups/{id}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
    backups.delete(user(jwt), id);
  }

  @PostMapping("/v1/backups/transfer-code")
  public TransferCodeJson transferCode(@AuthenticationPrincipal Jwt jwt) {
    String code = backups.createTransferCode(user(jwt), config.transferCodeTtl());
    return new TransferCodeJson(code, OffsetDateTime.now().plus(config.transferCodeTtl()));
  }

  @PostMapping("/v1/backups/claim")
  public ClaimJson claim(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody ClaimRequest request) {
    String code = request.code().trim().toUpperCase().replace("-", "").replace(" ", "");
    int moved = backups.claim(code, user(jwt))
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "transfer_code_invalid",
            "the code is unknown, used or expired"));
    return new ClaimJson(moved);
  }

  private static UUID user(Jwt jwt) {
    return UUID.fromString(jwt.getSubject());
  }

  private static boolean startsWith(byte[] data, byte[] prefix) {
    for (int i = 0; i < prefix.length; i++) if (data[i] != prefix[i]) return false;
    return true;
  }

  static String sha256Hex(byte[] data) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }
}
