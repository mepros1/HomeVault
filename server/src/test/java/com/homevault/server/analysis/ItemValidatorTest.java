package com.homevault.server.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import tools.jackson.databind.ObjectMapper;

class ItemValidatorTest {

  private final ObjectMapper mapper = new ObjectMapper();

  @Test
  void acceptsSpecSampleItem() {
    var parsed =
        mapper.readTree(
            """
            {"items":[{"name":"Flat-screen television","category":"Electronics","brand":"Samsung",
              "model":null,"serial":null,"qty":1,"condition":"good","est_low":400,"est_high":900,
              "confidence":0.86,"source_image_index":0,"note":"Wall-mounted, approx. 55 inch"}]}
            """);
    var result = ItemValidator.validate(parsed, 4, "USD");

    assertThat(result.warnings()).isEmpty();
    assertThat(result.items()).hasSize(1);
    var tv = result.items().getFirst();
    assertThat(tv.brand()).isEqualTo("Samsung");
    assertThat(tv.model()).isNull();
    assertThat(tv.estLow()).isEqualTo(400);
    assertThat(tv.currency()).isEqualTo("USD");
  }

  @Test
  void dropsInvalidRowsAndNormalisesLooseOnes() {
    var parsed =
        mapper.readTree(
            """
            {"items":[
              {"name":"","category":"Furniture","est_low":1,"est_high":2,"confidence":0.5,"source_image_index":0},
              {"name":"Inverted","category":"Furniture","est_low":50,"est_high":10,"confidence":0.5,"source_image_index":0},
              {"name":"Overconfident","category":"Furniture","est_low":1,"est_high":2,"confidence":1.5,"source_image_index":0},
              {"name":"Loose","category":"Spaceships","condition":"mint","qty":0,"est_low":10.456,"est_high":20,
               "confidence":0.7,"source_image_index":9,"brand":"  "}
            ]}
            """);
    var result = ItemValidator.validate(parsed, 2, "EUR");

    assertThat(result.items()).hasSize(1);
    assertThat(result.warnings()).hasSize(4);
    var loose = result.items().getFirst();
    assertThat(loose.category()).isEqualTo("Other");
    assertThat(loose.condition()).isNull();
    assertThat(loose.qty()).isEqualTo(1);
    assertThat(loose.estLow()).isEqualTo(10.46);
    assertThat(loose.sourceImageIndex()).isZero();
    assertThat(loose.brand()).isNull();
  }

  @Test
  void missingItemsArrayYieldsNothing() {
    var result = ItemValidator.validate(mapper.readTree("{}"), 1, "USD");
    assertThat(result.items()).isEmpty();
    assertThat(result.warnings()).containsExactly("model returned no items array");
  }
}
