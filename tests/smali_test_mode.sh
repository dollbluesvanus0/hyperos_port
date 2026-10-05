#!/usr/bin/env bash
set -euo pipefail

repository_dir=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$repository_dir/tmp"
fixture_root=$(mktemp -d "$repository_dir/tmp/smali-test-mode.XXXXXX")
case "$fixture_root" in "$repository_dir"/tmp/smali-test-mode.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$fixture_root"' EXIT

# Execute actual port.sh stages against small fixtures, without downloading ROMs.
"${PYTHON_FOR_TESTS:-python3}" - "$repository_dir" "$fixture_root" <<'PY'
from pathlib import Path
import re
import sys

repository, fixture = map(Path, sys.argv[1:])
source = (repository / 'port.sh').read_text(encoding='utf-8')
stages = dict(re.findall(r'^# SMALI_STAGE: ([\w-]+)\n(.*?)^# END_SMALI_STAGE$',
                        source, flags=re.MULTILINE | re.DOTALL))
assert set(stages) == {'services-signature-patch', 'app-method-patches'}
boundaries = {
    'stock-resource-overlays': ('baseAospFrameworkResOverlay=', '# displayconfig id'),
    'resource-patch': ('# Unlock Celluar Sharing feature', '# SMALI_STAGE: app-method-patches'),
    'camera-download': ('# Fetch and validate the HyperOS 2 camera', '# 提取分区'),
    'nfc-overlay-camera-debloat': ('if [[ -d "devices/common" ]];then', 'for zip in $(find devices/${base_rom_code}/'),
}
for name, (start, end) in boundaries.items():
    first = source.index(start)
    stages[name] = source[first:source.index(end, first)]
(fixture / 'stages').mkdir()
for name, body in stages.items():
    (fixture / 'stages' / (name + '.sh')).write_text(body, encoding='utf-8', newline='\n')
archives = ['product/overlay/' + name + '.apk' for name in (
    'AospFrameworkResOverlay', 'MiuiFrameworkResOverlay', 'DevicesAndroidOverlay',
    'DevicesOverlay', 'SettingsRroDeviceHideStatusBarOverlay', 'MiuiBiometricResOverlay')]
archives += ['product/app/' + name + '/' + name + '.apk' for name in (
    'MiLinkOS2CN', 'MIUIThemeManager', 'Settings', 'PowerKeeper')]
archives += ['system/system/framework/services.jar', 'system/system/framework/miui-services.jar',
             'system_ext/framework/framework-ext-res.apk']
for tree, prefix in (('baserom', 'stock'), ('portrom', 'donor')):
    for relative in archives:
        path = fixture / 'build' / tree / 'images' / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((prefix + ':' + relative).encode())
(fixture / 'devices/common').mkdir(parents=True)
overlay = fixture / 'devices/venus/overlay/product/DeviceReplacement.apk'
overlay.parent.mkdir(parents=True)
overlay.write_bytes(b'device APK replacement')
(fixture / 'build/portrom/images/vendor').mkdir()
(fixture / 'bin').mkdir()
PY

mkdir -p "$fixture_root/tools"
cat > "$fixture_root/tools/java" <<'SH'
#!/usr/bin/env bash
printf 'java %s\n' "$*" >> "$TOOL_CALL_LOG"
command=$3
while (( $# )); do
    case "$1" in -i) input=$2; shift ;; -o) output=$2; shift ;; esac
    shift
done
if [[ "$command" == d ]]; then
    mkdir -p "$output/res/values"
    printf '<bool name="config_celluar_shared_support">false</bool>\n' > "$output/res/values/config.xml"
    if [[ "$input" == tmp/services.jar ]]; then
        directory="$output/smali/classes/com/android/server/pm"
        mkdir -p "$directory/pkg/parsing"
        printf 'invoke-static {v0}, LVerifier;->getMinimumSignatureSchemeVersionForTargetSdk(I)I\nmove-result v1\nreturn-void\n' > "$directory/Verifier.smali"
        printf 'invoke-static {v0}, LVerifier;->canJoinSharedUserId(I)I\nmove-result v2\nreturn-void\n' > "$directory/ReconcilePackageUtils.smali"
    fi
else
    printf 'rebuilt fixture archive' > "$output"
fi
SH
cat > "$fixture_root/tools/python3" <<'SH'
#!/usr/bin/env bash
case "$1" in
    bin/patchmethod.py) printf 'patchmethod %s\n' "$*" >> "$TOOL_CALL_LOG" ;;
    bin/miuicamera.py)
        printf 'camera %s\n' "$*" >> "$TOOL_CALL_LOG"
        if [[ "$2" == download ]]; then
            printf 'downloaded camera' > "$3"
        else
            mkdir -p "$4/product/priv-app/MiuiCamera"
            cp "$3" "$4/product/priv-app/MiuiCamera/MiuiCamera.apk"
        fi ;;
    bin/debloat.py) printf 'debloat %s\n' "$*" >> "$TOOL_CALL_LOG" ;;
    *) "${PYTHON_FOR_TESTS:-/usr/bin/python3}" "$@" ;;
esac
SH
cat > "$fixture_root/tools/unzip" <<'SH'
#!/usr/bin/env bash
printf 'nfc %s\n' "$*" >> "$TOOL_CALL_LOG"
mkdir -p build/portrom/images/system/system/framework
printf 'NFC replacement' > build/portrom/images/system/system/framework/com.nxp.nfc.nq.jar
SH
cat > "$fixture_root/tools/smali-tool" <<'SH'
#!/usr/bin/env bash
printf 'smali tool %s\n' "$*" >> "$TOOL_CALL_LOG"
exit 91
SH
chmod +x "$fixture_root/tools/"*
for tool in 7z zipalign; do cp "$fixture_root/tools/smali-tool" "$fixture_root/tools/$tool"; done
export PATH="$fixture_root/tools:$PATH" TOOL_CALL_LOG="$fixture_root/tool-calls.log"
source "$repository_dir/functions.sh"
cp "$repository_dir/bin/port_config" "$fixture_root/bin/"
cd "$fixture_root"
work_dir=$PWD
base_rom_code=venus
port_android_version=14
nfc_fix_type=a14
test_mode=true
is_eu_rom=false
find build/portrom/images -type f \( -name '*.apk' -o -name '*.jar' \) -exec sha256sum '{}' \; > baseline.sha256
source stages/services-signature-patch.sh
source stages/app-method-patches.sh
is_eu_rom=true
source stages/services-signature-patch.sh
for target in MiuiSystemUI.apk PowerKeeper.apk MiSettings.apk MISettings.apk miui-services.jar; do
    patch_smali "$target" 'Target.smali' original replacement
done
[[ ! -e "$TOOL_CALL_LOG" ]] || { cat "$TOOL_CALL_LOG" >&2; exit 1; }
sha256sum -c baseline.sha256 > /dev/null

# The same test_mode=true must allow resource edits and all app replacements.
source stages/stock-resource-overlays.sh
cmp build/baserom/images/product/overlay/AospFrameworkResOverlay.apk \
    build/portrom/images/product/overlay/AospFrameworkResOverlay.apk
source stages/resource-patch.sh
grep -q '<bool name="config_celluar_shared_support">true</bool>' tmp/framework-ext-res/res/values/config.xml
grep -q 'rebuilt fixture archive' build/portrom/images/system_ext/framework/framework-ext-res.apk
source stages/camera-download.sh
source stages/nfc-overlay-camera-debloat.sh
grep -q '^camera bin/miuicamera.py download' "$TOOL_CALL_LOG"
grep -q '^camera bin/miuicamera.py install' "$TOOL_CALL_LOG"
grep -q '^debloat bin/debloat.py' "$TOOL_CALL_LOG"
grep -q '^nfc .*nfc_a14.zip' "$TOOL_CALL_LOG"
cmp devices/venus/overlay/product/DeviceReplacement.apk build/portrom/images/product/DeviceReplacement.apk
cmp build/MiuiCamera.apk build/portrom/images/product/priv-app/MiuiCamera/MiuiCamera.apk

# Disabling test mode resumes the actual services.jar smali editing pipeline.
test_mode=false
is_eu_rom=false
source stages/services-signature-patch.sh
grep -q 'const/4 v1, 0x0' tmp/services/smali/classes/com/android/server/pm/Verifier.smali
grep -q 'const/4 v2, 0x1' tmp/services/smali/classes/com/android/server/pm/ReconcilePackageUtils.smali
grep -q 'rebuilt fixture archive' build/portrom/images/system/system/framework/services.jar
printf 'PASS: test mode skips only smali; resources, camera, NFC, overlays and debloat remain active\n'
