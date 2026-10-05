#!/usr/bin/env bash
set -euo pipefail

repository_dir=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$repository_dir/tmp"
fixture_root=$(mktemp -d "$repository_dir/tmp/archive-test-mode.XXXXXX")
case "$fixture_root" in "$repository_dir"/tmp/archive-test-mode.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$fixture_root"' EXIT

# Extract and execute the real archive-handling stages, with tools that record
# any accidental invocation. Fixtures include every patched/replaced app family.
"${PYTHON_FOR_TESTS:-python3}" - "$repository_dir" "$fixture_root" <<'PY'
from pathlib import Path
import re
import sys

repository, fixture = map(Path, sys.argv[1:])
source = (repository / 'port.sh').read_text(encoding='utf-8')
stages = re.findall(r'^# APK/JAR_STAGE: ([\w-]+)\n(.*?)^# END_APK/JAR_STAGE$',
                    source, flags=re.MULTILINE | re.DOTALL)
assert len(stages) == 8, 'Archive-handling stage boundaries must be complete.'
(fixture / 'stages').mkdir()
for name, body in stages:
    (fixture / 'stages' / (name + '.sh')).write_text(body, encoding='utf-8', newline='\n')
archives = [
    'product/overlay/' + name + '.apk' for name in (
        'AospFrameworkResOverlay', 'MiuiFrameworkResOverlay', 'DevicesAndroidOverlay',
        'DevicesOverlay', 'SettingsRroDeviceHideStatusBarOverlay',
        'MiuiBiometricResOverlay', 'MiuiFrameworkTelephonyResOverlay')]
archives += ['product/app/' + name + '/' + name + '.apk' for name in (
    'MiSound', 'MiuiBiometric', 'HotwordEnrollmentXGoogleHEXAGON_WIDEBAND',
    'MSA', 'Updater', 'MiuiCamera', 'MiLinkOS2CN', 'MIUIThemeManager',
    'Settings', 'PowerKeeper', 'MISettings', 'NQNfcNci')]
archives += ['product/data-app/MIUINotes/MIUINotes.apk',
             'system/system/framework/services.jar',
             'system/system/framework/miui-services.jar',
             'system/system/framework/com.nxp.nfc.nq.jar',
             'system_ext/framework/com.xiaomi.nfc.jar',
             'system_ext/framework/framework-ext-res.apk']
for tree, prefix in (('baserom', 'stock'), ('portrom', 'donor')):
    for relative in archives:
        path = fixture / 'build' / tree / 'images' / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((prefix + ':' + relative).encode())
(fixture / 'devices/common').mkdir(parents=True)
(fixture / 'bin/apktool').mkdir(parents=True)
PY

mkdir -p "$fixture_root/tools"
cat > "$fixture_root/tools/python3" <<'SH'
#!/usr/bin/env bash
case "$1" in
    bin/miuicamera.py|bin/debloat.py|bin/patchmethod.py)
        printf '%s\n' "$*" >> "$TOOL_CALL_LOG"; exit 91 ;;
esac
"${PYTHON_FOR_TESTS:-/usr/bin/python3}" "$@"
SH
cat > "$fixture_root/tools/archive-tool" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$0" "$*" >> "$TOOL_CALL_LOG"
exit 91
SH
chmod +x "$fixture_root/tools/"*
for tool in java 7z zipalign; do
    cp "$fixture_root/tools/archive-tool" "$fixture_root/tools/$tool"
done
cp "$fixture_root/tools/archive-tool" "$fixture_root/bin/apktool/apktool"
export PATH="$fixture_root/tools:$PATH" TOOL_CALL_LOG="$fixture_root/tool-calls.log"
cp "$repository_dir/bin/archive_test_mode.py" "$fixture_root/bin/"
source "$repository_dir/functions.sh"
cd "$fixture_root"
work_dir=$PWD
test_mode=true
is_eu_rom=false
port_android_version=15
nfc_fix_type=legacy

python3 bin/archive_test_mode.py capture build/portrom/images baseline.json
for stage in stages/*.sh; do
    source "$stage"
done
# The EU JAR path and shared smali helper must also avoid invoking tools.
is_eu_rom=true
source stages/services-signature-patch.sh
patch_smali 'PowerKeeper.apk' 'DisplayFrameSetting.smali' unicorn umi
patch_smali 'miui-services.jar' 'SystemServerImpl.smali' original replacement
python3 bin/archive_test_mode.py verify build/portrom/images baseline.json
[[ ! -e "$TOOL_CALL_LOG" ]] || { cat "$TOOL_CALL_LOG" >&2; exit 1; }

# Normal mode continues to replace stock resource APKs.
test_mode=false
source stages/stock-resource-overlays.sh
cmp build/baserom/images/product/overlay/AospFrameworkResOverlay.apk \
    build/portrom/images/product/overlay/AospFrameworkResOverlay.apk
cmp build/baserom/images/product/overlay/MiuiFrameworkResOverlay.apk \
    build/portrom/images/product/overlay/MiuiFrameworkResOverlay.apk
printf 'PASS: test-mode APK/JAR stages preserve files and skip tools; normal replacements remain enabled\n'
