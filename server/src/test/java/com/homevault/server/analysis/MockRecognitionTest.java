package com.homevault.server.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import tools.jackson.databind.ObjectMapper;

class MockRecognitionTest {

  private final ObjectMapper mapper = new ObjectMapper();

  @Test
  void mockItemsPassTheContractValidator() {
    for (String room : new String[] {"Kitchen", "Living Room", "Master Bedroom", "Garage", "Loft"}) {
      var result = ItemValidator.validate(MockRecognition.itemsFor(room, 3, mapper), 3, "USD");
      assertThat(result.warnings()).as(room).isEmpty();
      assertThat(result.items()).as(room).hasSizeGreaterThanOrEqualTo(5);
      assertThat(result.items()).allSatisfy(i -> {
        assertThat(i.sourceImageIndex()).isBetween(0, 2);
        assertThat(i.estHigh()).isGreaterThanOrEqualTo(i.estLow());
        assertThat(ItemValidator.CATEGORIES).contains(i.category());
      });
    }
  }

  @Test
  void kitchenHasALowConfidenceItemForTheConfirmFlow() {
    var result = ItemValidator.validate(MockRecognition.itemsFor("Kitchen", 4, mapper), 4, "USD");
    assertThat(result.items()).anyMatch(i -> i.confidence() < 0.6);
    assertThat(result.items()).anyMatch(i -> i.qty() > 1);
  }
}
