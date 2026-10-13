package com.homevault.server.backup;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.homevault.server.config.HomeVaultProperties;
import com.homevault.server.config.SecurityConfig;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(BackupController.class)
@Import({SecurityConfig.class, BackupControllerTest.Props.class})
@TestPropertySource(properties = {"homevault.backup.max-per-user=2", "homevault.backup.max-total-bytes=1000"})
class BackupControllerTest {

  @EnableConfigurationProperties(HomeVaultProperties.class)
  static class Props {}

  private static final UUID USER = UUID.randomUUID();
  private static final UUID ID = UUID.randomUUID();
  private static final byte[] PDF = "%PDF-1.7 hello".getBytes(StandardCharsets.US_ASCII);

  @Autowired MockMvc mvc;
  @MockitoBean BackupRepository backups;
  @MockitoBean JwtDecoder jwtDecoder;

  private static BackupRepository.Summary summary(UUID id, int size) {
    return new BackupRepository.Summary(id, "HomeVault-flat-2026-09-28-abcd1234.pdf", size, "sha",
        OffsetDateTime.parse("2026-09-28T10:00:00Z"), 12, new BigDecimal("100.00"), new BigDecimal("400.00"),
        OffsetDateTime.parse("2026-09-28T10:01:00Z"));
  }

  private org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder upload(byte[] bytes) {
    return (org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder) multipart("/v1/backups")
        .file(new MockMultipartFile("file", "r.pdf", "application/pdf", bytes))
        .param("id", ID.toString())
        .param("file_name", "HomeVault-flat-2026-09-28-abcd1234.pdf")
        .param("generated_at", "2026-09-28T10:00:00Z")
        .param("item_count", "12")
        .param("total_low", "100")
        .param("total_high", "400")
        .with(jwt().jwt(j -> j.subject(USER.toString())));
  }

  @Test
  void requiresAToken() throws Exception {
    mvc.perform(get("/v1/backups")).andExpect(status().isUnauthorized());
  }

  @Test
  void uploadsAPdfAndReturnsItsSummary() throws Exception {
    when(backups.ownerOf(ID)).thenReturn(Optional.empty());
    when(backups.usage(USER)).thenReturn(new BackupRepository.Usage(0, 0));
    when(backups.upsert(eq(USER), any(), any())).thenReturn(summary(ID, PDF.length));

    mvc.perform(upload(PDF))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.id").value(ID.toString()))
        .andExpect(jsonPath("$.item_count").value(12))
        .andExpect(jsonPath("$.file_name").value("HomeVault-flat-2026-09-28-abcd1234.pdf"));
  }

  @Test
  void rejectsNonPdfAndForeignIdsAndFullStorage() throws Exception {
    when(backups.usage(USER)).thenReturn(new BackupRepository.Usage(0, 0));
    when(backups.ownerOf(ID)).thenReturn(Optional.empty());
    mvc.perform(upload("not a pdf".getBytes())).andExpect(status().isBadRequest());

    when(backups.ownerOf(ID)).thenReturn(Optional.of(UUID.randomUUID()));
    mvc.perform(upload(PDF)).andExpect(status().isConflict()).andExpect(jsonPath("$.error").value("conflict"));

    when(backups.ownerOf(ID)).thenReturn(Optional.empty());
    when(backups.usage(USER)).thenReturn(new BackupRepository.Usage(2, 100));
    mvc.perform(upload(PDF)).andExpect(status().isConflict()).andExpect(jsonPath("$.error").value("backup_limit"));

    when(backups.usage(USER)).thenReturn(new BackupRepository.Usage(1, 995));
    mvc.perform(upload(PDF)).andExpect(status().isConflict()).andExpect(jsonPath("$.error").value("backup_limit"));
    verify(backups, never()).upsert(any(), any(), any());
  }

  @Test
  void replacingAPdfCountsOnlyTheNewSizeDifference() throws Exception {
    when(backups.ownerOf(ID)).thenReturn(Optional.of(USER));
    when(backups.usage(USER)).thenReturn(new BackupRepository.Usage(2, 995));
    when(backups.get(USER, ID)).thenReturn(Optional.of(new BackupRepository.Stored(summary(ID, PDF.length), PDF)));
    when(backups.upsert(eq(USER), any(), any())).thenReturn(summary(ID, PDF.length));
    mvc.perform(upload(PDF)).andExpect(status().isOk());
    verify(backups).upsert(eq(USER), any(), any());
  }

  @Test
  void listsDownloadsAndDeletes() throws Exception {
    when(backups.list(USER)).thenReturn(List.of(summary(ID, PDF.length)));
    when(backups.get(USER, ID)).thenReturn(Optional.of(new BackupRepository.Stored(summary(ID, PDF.length), PDF)));
    var auth = jwt().jwt(j -> j.subject(USER.toString()));

    mvc.perform(get("/v1/backups").with(auth))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.backups[0].id").value(ID.toString()))
        .andExpect(jsonPath("$.max_count").value(2));

    mvc.perform(get("/v1/backups/" + ID).with(auth))
        .andExpect(status().isOk())
        .andExpect(content().contentType(MediaType.APPLICATION_PDF))
        .andExpect(header().string("Content-Disposition", org.hamcrest.Matchers.containsString("abcd1234.pdf")))
        .andExpect(content().bytes(PDF));

    mvc.perform(get("/v1/backups/" + UUID.randomUUID()).with(auth)).andExpect(status().isNotFound());

    mvc.perform(delete("/v1/backups/" + ID).with(auth)).andExpect(status().isNoContent());
    verify(backups).delete(USER, ID);
  }

  @Test
  void transferCodeAndClaim() throws Exception {
    var auth = jwt().jwt(j -> j.subject(USER.toString()));
    when(backups.createTransferCode(eq(USER), any())).thenReturn("ABCD2345");
    mvc.perform(post("/v1/backups/transfer-code").with(auth))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("ABCD2345"));

    when(backups.claim("ABCD2345", USER)).thenReturn(Optional.of(3));
    mvc.perform(post("/v1/backups/claim").with(auth).contentType(MediaType.APPLICATION_JSON)
            .content("{\"code\":\" abcd-2345 \"}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.moved").value(3));

    when(backups.claim("NOPE", USER)).thenReturn(Optional.empty());
    mvc.perform(post("/v1/backups/claim").with(auth).contentType(MediaType.APPLICATION_JSON)
            .content("{\"code\":\"NOPE\"}"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.error").value("transfer_code_invalid"));
  }
}
