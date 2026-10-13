package com.homevault.server.analysis;

import java.util.List;
import java.util.Locale;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.node.ArrayNode;
import tools.jackson.databind.node.ObjectNode;

/**
 * Canned recognition results for development without a Gemini key
 * ({@code GEMINI_MOCK=true}). Produces the same JSON shape the model returns so
 * that validation, quota, caching and the app's review / report flows run
 * unchanged. Items vary by room type and are spread across the uploaded images.
 */
final class MockRecognition {

  private MockRecognition() {}

  /** name, category, brand, condition, low, high, confidence, note. */
  private record Seed(
      String name, String category, String brand, String condition,
      double low, double high, double confidence, String note) {}

  private static final List<Seed> KITCHEN = List.of(
      new Seed("Refrigerator", "Appliances", "Samsung", "good", 900, 1800, 0.92, "Stainless steel, French door"),
      new Seed("Electric range", "Appliances", null, "good", 500, 1200, 0.88, "Four burners, built-in oven"),
      new Seed("Microwave oven", "Appliances", "Panasonic", "good", 80, 200, 0.85, "Countertop model"),
      new Seed("Dining table", "Furniture", null, "good", 300, 900, 0.83, "Wooden, seats four"),
      new Seed("Dining chair", "Furniture", null, "good", 60, 150, 0.8, "Set of four matching chairs"),
      new Seed("Stand mixer", "Kitchenware", "KitchenAid", "excellent", 300, 500, 0.74, "Red, on the counter"),
      new Seed("Coffee maker", "Appliances", null, "fair", 40, 120, 0.55, "Partly hidden behind the mixer"),
      new Seed("Knife set with block", "Kitchenware", null, "good", 60, 200, 0.5, "Wooden block, count unclear"));

  private static final List<Seed> LIVING = List.of(
      new Seed("Flat-screen television", "Electronics", null, "good", 400, 900, 0.9, "Approx. 55 inch on a low cabinet"),
      new Seed("TV cabinet", "Furniture", null, "good", 150, 400, 0.86, "Light wood, three doors"),
      new Seed("Bookshelf ladder unit", "Furniture", null, "good", 120, 350, 0.82, "Five shelves"),
      new Seed("Books", "Books & Media", null, "good", 100, 400, 0.7, "Roughly 60 volumes"),
      new Seed("Area rug", "Home Decor", null, "fair", 100, 350, 0.78, "Patterned, approx. 2 x 3 m"),
      new Seed("Sofa", "Furniture", null, "good", 500, 1500, 0.65, "Only the armrest is visible"),
      new Seed("Wall art print", "Art & Collectibles", null, "good", 50, 200, 0.45, "Framed, subject unclear"));

  private static final List<Seed> BEDROOM = List.of(
      new Seed("Bed with mattress", "Furniture", null, "good", 600, 1600, 0.9, "Queen size"),
      new Seed("Wardrobe", "Furniture", null, "good", 300, 900, 0.85, "Freestanding, two doors"),
      new Seed("Bedside table", "Furniture", null, "good", 50, 150, 0.8, "Pair"),
      new Seed("Table lamp", "Home Decor", null, "good", 30, 90, 0.75, "Fabric shade"),
      new Seed("Watch", "Jewelry & Watches", "Seiko", "excellent", 250, 600, 0.6, "On the bedside table"),
      new Seed("Duvet and pillows", "Bedding & Linens", null, "good", 80, 250, 0.7, null));

  private static final List<Seed> GENERIC = List.of(
      new Seed("Storage shelving", "Furniture", null, "good", 80, 250, 0.85, "Metal, five tiers"),
      new Seed("Cordless drill", "Tools & Equipment", "Bosch", "good", 80, 200, 0.8, "With case"),
      new Seed("Bicycle", "Sports & Outdoor", null, "good", 300, 900, 0.78, "Adult hybrid bike"),
      new Seed("Plastic storage boxes", "Other", null, "good", 40, 120, 0.7, "Six boxes, contents unknown"),
      new Seed("Guitar", "Musical Instruments", null, "fair", 150, 500, 0.5, "Acoustic, in a corner"));

  static JsonNode itemsFor(String roomType, int imageCount, ObjectMapper mapper) {
    String key = roomType == null ? "" : roomType.toLowerCase(Locale.ROOT);
    List<Seed> seeds;
    if (key.contains("kitchen") || key.contains("dining")) seeds = KITCHEN;
    else if (key.contains("living") || key.contains("office")) seeds = LIVING;
    else if (key.contains("bedroom")) seeds = BEDROOM;
    else seeds = GENERIC;

    ObjectNode root = mapper.createObjectNode();
    ArrayNode items = root.putArray("items");
    int i = 0;
    for (Seed s : seeds) {
      ObjectNode n = items.addObject();
      n.put("name", s.name());
      n.put("category", s.category());
      if (s.brand() == null) n.putNull("brand"); else n.put("brand", s.brand());
      n.putNull("model");
      n.putNull("serial");
      n.put("qty", s.name().equals("Dining chair") ? 4 : s.name().equals("Bedside table") ? 2 : 1);
      n.put("condition", s.condition());
      n.put("est_low", s.low());
      n.put("est_high", s.high());
      n.put("confidence", s.confidence());
      n.put("source_image_index", imageCount == 0 ? 0 : i % imageCount);
      if (s.note() == null) n.putNull("note"); else n.put("note", s.note());
      i++;
    }
    return root;
  }
}
