# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keep,includedescriptorclasses class com.sulav.sleepblock.**$$serializer { *; }
-keepclassmembers class com.sulav.sleepblock.** {
    *** Companion;
}
-keepclasseswithmembers class com.sulav.sleepblock.** {
    kotlinx.serialization.KSerializer serializer(...);
}
