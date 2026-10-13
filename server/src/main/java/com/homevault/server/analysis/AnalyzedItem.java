package com.homevault.server.analysis;

import com.fasterxml.jackson.annotation.JsonProperty;

/** One recognised item on the wire (spec section 5.1). Field names are the contract. */
public record AnalyzedItem(
    String name,
    String category,
    String brand,
    String model,
    String serial,
    int qty,
    String condition,
    @JsonProperty("est_low") double estLow,
    @JsonProperty("est_high") double estHigh,
    String currency,
    double confidence,
    @JsonProperty("source_image_index") int sourceImageIndex,
    String note) {}
