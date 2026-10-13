package com.homevault.server.integrity;

import java.io.IOException;
import tools.jackson.databind.JsonNode;

/** Turns an opaque Play Integrity token into its verdict payload. */
public interface PlayIntegrityDecoder {

  /**
   * @return the {@code tokenPayloadExternal} object
   * @throws IOException when Google cannot be reached or rejects the token
   */
  JsonNode decode(String integrityToken) throws IOException, InterruptedException;
}
