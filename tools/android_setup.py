#!/usr/bin/env python3
"""flutter create 로 만든 android 폴더를 스토어 출시용으로 고쳐요.
사용: android_setup.py <앱 이름> <아이콘 1024 png> [--notifications]"""
import re, sys, glob, os

label, icon_path = sys.argv[1], sys.argv[2]
notifications = '--notifications' in sys.argv

# 1) 매니페스트: 앱 이름, (알림 앱이면) 권한과 알림 수신기
m = 'android/app/src/main/AndroidManifest.xml'
s = open(m, encoding='utf-8').read()
s = re.sub(r'android:label="[^"]*"', f'android:label="{label}"', s, count=1)
if notifications:
    perms = ('<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
             '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
             '    <uses-permission android:name="android.permission.VIBRATE"/>\n    ')
    s = s.replace('<application', perms + '<application', 1)
    recv = ('<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>\n'
            '        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n'
            '            <intent-filter>\n'
            '                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n'
            '                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n'
            '            </intent-filter>\n'
            '        </receiver>\n        ')
    s = s.replace('</application>', '    ' + recv.rstrip() + '\n    </application>', 1)
open(m, 'w', encoding='utf-8').write(s)

# 2) gradle: 서명 + (알림 앱이면) desugaring
g = glob.glob('android/app/build.gradle*')[0]
t = open(g, encoding='utf-8').read()
kts = g.endswith('.kts')
if notifications:
    if kts:
        t = t.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
        t = t.rstrip() + '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n'
    else:
        t = t.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
        t = t.rstrip() + '\n\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.5"\n}\n'
if os.environ.get('KEYSTORE_PATH'):
    if kts:
        sign = ('signingConfigs {\n        create("release") {\n'
                '            storeFile = file(System.getenv("KEYSTORE_PATH"))\n'
                '            storePassword = System.getenv("ANDROID_STORE_PASSWORD")\n'
                '            keyAlias = System.getenv("ANDROID_KEY_ALIAS")\n'
                '            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")\n'
                '        }\n    }\n    buildTypes {')
        t = t.replace('buildTypes {', sign, 1)
        t = t.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
    else:
        sign = ('signingConfigs {\n        release {\n'
                '            storeFile file(System.getenv("KEYSTORE_PATH"))\n'
                '            storePassword System.getenv("ANDROID_STORE_PASSWORD")\n'
                '            keyAlias System.getenv("ANDROID_KEY_ALIAS")\n'
                '            keyPassword System.getenv("ANDROID_KEY_PASSWORD")\n'
                '        }\n    }\n    buildTypes {')
        t = t.replace('buildTypes {', sign, 1)
        t = t.replace('signingConfigs.debug', 'signingConfigs.release')
open(g, 'w', encoding='utf-8').write(t)

# 3) 아이콘: 적응형 아이콘(배경색 + 가운데 그림) 과 옛 방식 아이콘, 스토어용 512
from PIL import Image
src = Image.open(icon_path).convert('RGBA')
bg = src.getpixel((4, 4))[:3]
res = 'android/app/src/main/res'
legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
fg = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
for d, px in legacy.items():
    os.makedirs(f'{res}/mipmap-{d}', exist_ok=True)
    src.resize((px, px), Image.LANCZOS).save(f'{res}/mipmap-{d}/ic_launcher.png')
for d, px in fg.items():
    canvas = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    inner = int(px * 72 / 108)
    pic = src.resize((inner, inner), Image.LANCZOS)
    canvas.paste(pic, ((px - inner) // 2, (px - inner) // 2))
    canvas.save(f'{res}/mipmap-{d}/ic_launcher_foreground.png')
os.makedirs(f'{res}/mipmap-anydpi-v26', exist_ok=True)
open(f'{res}/mipmap-anydpi-v26/ic_launcher.xml', 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n')
os.makedirs(f'{res}/values', exist_ok=True)
open(f'{res}/values/ic_launcher_background.xml', 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n</resources>\n' % bg)
os.makedirs('store', exist_ok=True)
src.resize((512, 512), Image.LANCZOS).convert('RGB').save('store/icon-512.png')
print('안드로이드 설정 완료', label)
