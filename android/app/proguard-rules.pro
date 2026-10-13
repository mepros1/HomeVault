# ML Kit text recognition (bundled Latin model) — keep the vision internals
# that are reached via reflection.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**

# RevenueCat
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# Google Play Billing (used by RevenueCat)
-keep class com.android.vending.billing.** { *; }

# Flutter deferred-components / Play Core warnings on projects that do not use them
-dontwarn com.google.android.play.core.**
