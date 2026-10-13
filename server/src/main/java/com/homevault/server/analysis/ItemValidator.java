package com.homevault.server.analysis;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import tools.jackson.databind.JsonNode;

/**
 * Second line of defence after the model's structured output: drops rows that violate the
 * contract instead of failing the request, and records a warning for each dropped row.
 */
public final class ItemValidator {

  public static final Set<String> CATEGORIES =
      Set.of(
          "Electronics",
          "Furniture",
          "Appliances",
          "Kitchenware",
          "Clothing & Accessories",
          "Jewelry & Watches",
          "Art & Collectibles",
          "Tools & Equipment",
          "Sports & Outdoor",
          "Musical Instruments",
          "Books & Media",
          "Toys & Games",
          "Home Decor",
          "Bedding & Linens",
          "Office & Stationery",
          "Other");

  public static final Set<String> CONDITIONS = Set.of("new", "excellent", "good", "fair", "poor");

  public record Result(List<AnalyzedItem> items, List<String> warnings) {}

  private ItemValidator() {}

  public static Result validate(JsonNode parsed, int imageCount, String currency) {
    List<AnalyzedItem> items = new ArrayList<>();
    List<String> warnings = new ArrayList<>();

    JsonNode list = parsed == null ? null : parsed.get("items");
    if (list == null || !list.isArray()) {
      warnings.add("model returned no items array");
      return new Result(items, warnings);
    }

    int i = -1;
    for (JsonNode e : list) {
      i++;
      String name = str(e.get("name"));
      if (name == null) {
        warnings.add("item " + i + ": missing name");
        continue;
      }

      String category = str(e.get("category"));
      if (category == null || !CATEGORIES.contains(category)) category = "Other";

      Double estLow = num(e.get("est_low"));
      Double estHigh = num(e.get("est_high"));
      if (estLow == null || estHigh == null || estLow < 0 || estHigh < estLow) {
        warnings.add("item " + i + " (" + name + "): invalid estimate range");
        continue;
      }

      Double confidence = num(e.get("confidence"));
      if (confidence == null || confidence < 0 || confidence > 1) {
        warnings.add("item " + i + " (" + name + "): invalid confidence");
        continue;
      }

      Double rawIndex = num(e.get("source_image_index"));
      int sourceIndex = rawIndex == null ? 0 : (int) Math.floor(rawIndex);
      if (sourceIndex < 0 || sourceIndex >= imageCount) {
        warnings.add("item " + i + " (" + name + "): source_image_index out of range, reset to 0");
        sourceIndex = 0;
      }

      String condition = str(e.get("condition"));
      if (condition != null && !CONDITIONS.contains(condition)) condition = null;

      Double rawQty = num(e.get("qty"));
      int qty = rawQty == null ? 1 : Math.max(1, (int) Math.floor(rawQty));

      items.add(
          new AnalyzedItem(
              name,
              category,
              str(e.get("brand")),
              str(e.get("model")),
              str(e.get("serial")),
              qty,
              condition,
              round2(estLow),
              round2(estHigh),
              currency,
              round2(confidence),
              sourceIndex,
              str(e.get("note"))));
    }
    return new Result(items, warnings);
  }

  private static String str(JsonNode n) {
    if (n == null || !n.isTextual()) return null;
    String t = n.asString().trim();
    return t.isEmpty() ? null : t;
  }

  private static Double num(JsonNode n) {
    if (n == null || !n.isNumber()) return null;
    double d = n.asDouble();
    return Double.isFinite(d) ? d : null;
  }

  private static double round2(double v) {
    return Math.round(v * 100.0) / 100.0;
  }
}
