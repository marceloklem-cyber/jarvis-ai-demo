"""Ajusta o projeto Android gerado pelo `flutter create` para o JARVIS.

Executado pela compilação automática (GitHub Actions) depois do `flutter create`.
- permissões: microfone, notificações, alarme exato, reinício do aparelho
- receptores do flutter_local_notifications (avisos com o app fechado e após reiniciar)
- consultas de pacote para voz (Android 11+)
- nome do app, desugaring (exigido pelas notificações), assinatura e R8 desligado
A assinatura fixa vem dos segredos do GitHub (JARVIS_KEYSTORE_B64 / JARVIS_KEY_PASSWORD), nunca do código.
Sem eles, usa a assinatura temporária de depuração (atualizar exigirá desinstalar o app).
Funciona com build.gradle (Groovy) e build.gradle.kts (Kotlin).
"""
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
m = manifest.read_text(encoding="utf-8")

PERMS = """
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.BLUETOOTH"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
"""
RECEIVERS = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
QUERIES_ITEMS = """
        <intent><action android:name="android.speech.RecognitionService"/></intent>
        <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
"""

if "RECORD_AUDIO" not in m:
    m = re.sub(r"(<manifest[^>]*>)", r"\1" + PERMS, m, count=1)
if "ScheduledNotificationReceiver" not in m:
    m = m.replace("</application>", RECEIVERS + "    </application>", 1)
if "RecognitionService" not in m:
    if "<queries>" in m:
        m = m.replace("<queries>", "<queries>" + QUERIES_ITEMS, 1)
    else:
        m = m.replace("</manifest>", "    <queries>" + QUERIES_ITEMS + "    </queries>\n</manifest>", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="JARVIS"', m, count=1)
if "showWhenLocked" not in m:
    m = m.replace('android:name=".MainActivity"', 'android:name=".MainActivity"\n            android:showWhenLocked="true"\n            android:turnScreenOn="true"', 1)
manifest.write_text(m, encoding="utf-8")

groovy = ROOT / "android/app/build.gradle"
kts = ROOT / "android/app/build.gradle.kts"
SIGNED = bool(os.environ.get("JARVIS_KEYSTORE_PATH")) and bool(os.environ.get("JARVIS_KEY_PASSWORD"))

if groovy.exists():
    g = groovy.read_text(encoding="utf-8")
    if "coreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", g, count=1)
    if SIGNED and "JARVIS_KEYSTORE_PATH" not in g:
        g = re.sub(r"(\n\s*buildTypes\s*\{)", "\n    signingConfigs {\n        jarvis {\n            storeFile file(System.getenv('JARVIS_KEYSTORE_PATH'))\n"
                   "            storePassword System.getenv('JARVIS_KEY_PASSWORD')\n            keyAlias 'jarvis'\n            keyPassword System.getenv('JARVIS_KEY_PASSWORD')\n        }\n    }\\1", g, count=1)
    cfg = "signingConfigs.jarvis" if SIGNED else "signingConfigs.debug"
    g = re.sub(r"signingConfig\s*=?\s*signingConfigs\.debug(?!\n\s*minifyEnabled)", "signingConfig = " + cfg + "\n            minifyEnabled false\n            shrinkResources false", g)
    if "desugar_jdk_libs" not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'\n}\n"
    groovy.write_text(g, encoding="utf-8")
    print("build.gradle ajustado")
elif kts.exists():
    k = kts.read_text(encoding="utf-8")
    if "isCoreLibraryDesugaringEnabled" not in k:
        k = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", k, count=1)
    if SIGNED and "JARVIS_KEYSTORE_PATH" not in k:
        k = re.sub(r"(\n\s*buildTypes\s*\{)", "\n    signingConfigs {\n        create(\"jarvis\") {\n            storeFile = file(System.getenv(\"JARVIS_KEYSTORE_PATH\"))\n"
                   "            storePassword = System.getenv(\"JARVIS_KEY_PASSWORD\")\n            keyAlias = \"jarvis\"\n            keyPassword = System.getenv(\"JARVIS_KEY_PASSWORD\")\n        }\n    }\\1", k, count=1)
    name = "jarvis" if SIGNED else "debug"
    k = re.sub(r"signingConfig\s*=\s*signingConfigs\.getByName\(\"debug\"\)(?!\n\s*isMinifyEnabled)",
               "signingConfig = signingConfigs.getByName(\"" + name + "\")\n            isMinifyEnabled = false\n            isShrinkResources = false", k)
    if "desugar_jdk_libs" not in k:
        k += "\ndependencies {\n    coreLibraryDesugaring(\"com.android.tools:desugar_jdk_libs:2.0.4\")\n}\n"
    kts.write_text(k, encoding="utf-8")
    print("build.gradle.kts ajustado")
else:
    sys.exit("build.gradle não encontrado")

# Kotlin mais novo (alguns plugins exigem >= 1.8)
settings = ROOT / "android/settings.gradle"
if settings.exists():
    s = settings.read_text(encoding="utf-8")
    s = re.sub(r'(id\s+"org\.jetbrains\.kotlin\.android"\s+version\s+)"[^"]+"', r'\1"1.9.24"', s)
    settings.write_text(s, encoding="utf-8")
print("AndroidManifest.xml ajustado")
print("Assinatura: " + ("fixa (segredo do GitHub)" if SIGNED else "TEMPORÁRIA de depuração — configure os segredos JARVIS_KEYSTORE_B64 e JARVIS_KEY_PASSWORD"))
