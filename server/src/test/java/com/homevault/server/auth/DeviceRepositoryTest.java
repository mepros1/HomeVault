package com.homevault.server.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.homevault.server.api.ApiException;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.simple.JdbcClient;

class DeviceRepositoryTest {
  private final JdbcClient jdbc = mock(JdbcClient.class);
  private final JdbcClient.StatementSpec statement = mock(JdbcClient.StatementSpec.class);
  @SuppressWarnings("unchecked")
  private final JdbcClient.MappedQuerySpec<UUID> query = mock(JdbcClient.MappedQuerySpec.class);

  private DeviceRepository repository(Optional<UUID> matched) {
    when(jdbc.sql(anyString())).thenReturn(statement);
    when(statement.param(anyString(), any())).thenReturn(statement);
    when(statement.query(UUID.class)).thenReturn(query);
    when(query.optional()).thenReturn(matched);
    return new DeviceRepository(jdbc);
  }

  @Test
  void authenticatesOnlyTheMatchingDeviceAndStoresAHash() {
    UUID user = UUID.randomUUID();
    DeviceRepository repo = repository(Optional.of(user));
    assertEquals(user, repo.registerOrTouch("public-id", "android", "private-device-secret"));
    verify(statement).param("secret_hash", DeviceRepository.hashSecret("private-device-secret"));
  }

  @Test
  void rejectsAnExistingDeviceWhenItsSecretDoesNotMatch() {
    DeviceRepository repo = repository(Optional.empty());
    assertThrows(ApiException.class,
        () -> repo.registerOrTouch("public-id", "android", "wrong-private-secret"));
  }
}
