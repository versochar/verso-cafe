#!/usr/bin/env bash
# Ortam değişkenlerini ayarlar. Kullanım: source scripts/env.sh
export SOSYAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Flutter
export FLUTTER_ROOT="$HOME/flutter"
# JDK 21 (sistemdeki JDK 27 Gradle ile uyumsuz)
export JAVA_HOME="$HOME/.local/opt/jdk21"
# Android SDK (kullanıcı alanında)
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

export PATH="$HOME/.npm-global/bin:$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$HOME/.cargo/bin:$PATH"

# Gradle'ın doğru JDK'yı kullanması için
export GRADLE_OPTS="-Dorg.gradle.java.home=$JAVA_HOME"

echo "sosyal ortamı hazır:"
echo "  flutter : $(command -v flutter || echo YOK)"
echo "  java    : $(command -v java || echo YOK)"
echo "  sdk     : $ANDROID_HOME"
