# Reconhecimento de escrita (ML Kit Digital Ink). O ML Kit acha os próprios
# componentes por reflexão (nomes de classe no manifesto). Se o R8 renomear ou
# remover essas classes, o plugin não registra no app de release e o Dart recebe
# MissingPluginException no canal google_mlkit_digital_ink_recognizer.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_digital_ink_recognition.** { *; }
-dontwarn com.google.mlkit.**
