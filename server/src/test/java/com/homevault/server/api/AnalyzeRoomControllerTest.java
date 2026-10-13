package com.homevault.server.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.homevault.server.analysis.AnalysisService;
import com.homevault.server.analysis.AnalyzeRoomResponse;
import com.homevault.server.analysis.AnalyzedItem;
import com.homevault.server.config.SecurityConfig;
import com.homevault.server.integrity.AppCheckVerifier;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(AnalyzeRoomController.class)
@Import(SecurityConfig.class)
class AnalyzeRoomControllerTest {

  private static final UUID USER = UUID.randomUUID();

  @Autowired MockMvc mvc;
  @MockitoBean AnalysisService analysis;
  @MockitoBean AppCheckVerifier appCheck;
  @MockitoBean JwtDecoder jwtDecoder;

  private MockMultipartFile image(String name) {
    return new MockMultipartFile("images[]", name, "image/jpeg", new byte[] {1, 2, 3});
  }

  @Test
  void rejectsMissingToken() throws Exception {
    mvc.perform(multipart("/v1/analyze-room").file(image("a.jpg")).param("room_type", "Kitchen"))
        .andExpect(status().isUnauthorized());
  }

  @Test
  void returnsContractShapedBody() throws Exception {
    var item =
        new AnalyzedItem(
            "Flat-screen television", "Electronics", "Samsung", null, null, 1, "good", 400, 900,
            "USD", 0.86, 0, "Wall-mounted");
    when(analysis.analyze(eq(USER), any()))
        .thenReturn(
            new AnalyzeRoomResponse(
                "req_1", "gemini-test", "2026-09-21.1", List.of(item),
                new AnalyzeRoomResponse.TokenUsage(6480, 1520), List.of(), null));

    mvc.perform(
            multipart("/v1/analyze-room")
                .file(image("a.jpg"))
                .file(image("b.jpg"))
                .param("room_type", "Living Room")
                .header("X-Idempotency-Key", "abc")
                .with(jwt().jwt(j -> j.subject(USER.toString()))))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.request_id").value("req_1"))
        .andExpect(jsonPath("$.prompt_version").value("2026-09-21.1"))
        .andExpect(jsonPath("$.items[0].est_high").value(900))
        .andExpect(jsonPath("$.items[0].source_image_index").value(0))
        .andExpect(jsonPath("$.usage.input_tokens").value(6480))
        .andExpect(jsonPath("$.cached").doesNotExist());
  }

  @Test
  void mapsQuotaErrorTo429WithLimitAndResetsAt() throws Exception {
    when(analysis.analyze(eq(USER), any()))
        .thenThrow(
            new ApiException(
                HttpStatus.TOO_MANY_REQUESTS, "quota_exceeded", "Analysis quota exhausted",
                Map.of("limit", 3, "used", 3, "resets_at", OffsetDateTime.parse("2026-10-01T00:00:00Z").toInstant().toString())));

    mvc.perform(
            multipart("/v1/analyze-room")
                .file(image("a.jpg"))
                .with(jwt().jwt(j -> j.subject(USER.toString()))))
        .andExpect(status().isTooManyRequests())
        .andExpect(jsonPath("$.error").value("quota_exceeded"))
        .andExpect(jsonPath("$.limit").value(3))
        .andExpect(jsonPath("$.resets_at").value("2026-10-01T00:00:00Z"));
  }
}
