package com.homevault.server.stats;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.homevault.server.config.SecurityConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ReviewStatsController.class)
@Import(SecurityConfig.class)
class ReviewStatsControllerTest {

  @Autowired MockMvc mvc;
  @MockitoBean JdbcClient jdbc;
  @MockitoBean JwtDecoder jwtDecoder;

  @Test
  void requiresAToken() throws Exception {
    mvc.perform(post("/v1/stats/review").contentType(MediaType.APPLICATION_JSON).content("{\"deltas\":[]}"))
        .andExpect(status().isUnauthorized());
  }

  @Test
  void aggregatesNonEmptyDeltasAndRejectsNegatives() throws Exception {
    JdbcClient.StatementSpec spec = mock(JdbcClient.StatementSpec.class, org.mockito.Mockito.RETURNS_SELF);
    when(jdbc.sql(anyString())).thenReturn(spec);
    when(spec.update()).thenReturn(1);

    mvc.perform(post("/v1/stats/review")
            .with(jwt())
            .contentType(MediaType.APPLICATION_JSON)
            .content("""
                {"deltas":[
                  {"prompt_version":"2026-09-22.2","accepted":5,"edited":1,"deleted":2},
                  {"prompt_version":"2026-09-21.1","accepted":0,"edited":0,"deleted":0}
                ]}
                """))
        .andExpect(status().isNoContent());
    verify(spec, times(1)).update();

    mvc.perform(post("/v1/stats/review")
            .with(jwt())
            .contentType(MediaType.APPLICATION_JSON)
            .content("{\"deltas\":[{\"prompt_version\":\"v\",\"accepted\":-1,\"edited\":0,\"deleted\":0}]}"))
        .andExpect(status().isBadRequest());
    verify(spec, times(1)).update(); // still one: the rejected batch wrote nothing
  }
}
