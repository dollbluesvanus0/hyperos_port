#!/bin/bash

# Define color output function
error() {
    if [ "$#" -eq 2 ]; then
        
        if [[ "$LANG" == zh_CN* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;31m"$1"\033[0m"
        elif [[ "$LANG" == en* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;31m"$2"\033[0m"
        else
            echo -e \[$(date +%m%d-%T)\] "\033[1;31m"$2"\033[0m"
        fi
    elif [ "$#" -eq 1 ]; then
        echo -e \[$(date +%m%d-%T)\] "\033[1;31m"$1"\033[0m"
    else
        echo "Usage: error <Chinese> <English>"
    fi
}

yellow() {
    if [ "$#" -eq 2 ]; then
        
        if [[ "$LANG" == zh_CN* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;33m"$1"\033[0m"
        elif [[ "$LANG" == en* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;33m"$2"\033[0m"
        else
            echo -e \[$(date +%m%d-%T)\] "\033[1;33m"$2"\033[0m"
        fi
    elif [ "$#" -eq 1 ]; then
        echo -e \[$(date +%m%d-%T)\] "\033[1;33m"$1"\033[0m"
    else
        echo "Usage: yellow <Chinese> <English>"
    fi
}

blue() {
    if [ "$#" -eq 2 ]; then

        if [[ "$LANG" == zh_CN* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;34m"$1"\033[0m"
        elif [[ "$LANG" == en* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;34m"$2"\033[0m"
        else
            echo -e \[$(date +%m%d-%T)\] "\033[1;34m"$2"\033[0m"
        fi
    elif [ "$#" -eq 1 ]; then
        echo -e \[$(date +%m%d-%T)\] "\033[1;34m"$1"\033[0m"
    else
        echo "Usage: blue <Chinese> <English>"
    fi
}

red() {
    if [ "$#" -eq 2 ]; then

        if [[ "$LANG" == zh_CN* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[0;31m"$1"\033[0m"
        elif [[ "$LANG" == en* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[0;31m"$2"\033[0m"
        else
            echo -e \[$(date +%m%d-%T)\] "\033[0;31m"$2"\033[0m"
        fi
    elif [ "$#" -eq 1 ]; then
        echo -e \[$(date +%m%d-%T)\] "\033[0;31m"$1"\033[0m"
    else
        echo "Usage: red <Chinese> <English>"
    fi
}

green() {
    if [ "$#" -eq 2 ]; then
        if [[ "$LANG" == zh_CN* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;32m"$1"\033[0m"
        elif [[ "$LANG" == en* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;32m"$2"\033[0m"
        else
            echo -e \[$(date +%m%d-%T)\] "\033[1;32m"$2"\033[0m"
        fi
    elif [ "$#" -eq 1 ]; then
        echo -e \[$(date +%m%d-%T)\] "\033[1;32m"$1"\033[0m"
    else
        echo "Usage: green <Chinese> <English>"
    fi
}

#Check for the existence of the requirements command, proceed if it exists, or abort otherwise.
exists() {
    command -v "$1" > /dev/null 2>&1
}

abort() {
    error "--> Missing $1 abort! please run ./setup.sh first (sudo is required on Linux system)"
    error "--> 命令 $1 缺失!请重新运行setup.sh (Linux系统sudo ./setup.sh)"
    exit 1
}

check() {
    for b in "$@"; do
        exists "$b" || abort "$b"
    done
}


# Replace Smali code in an APK or JAR file, without supporting resource patches.
# $1: Target APK/JAR file
# $2: Target Smali file (supports relative paths for Smali files)
# $3: Value to be replaced
# $4: Replacement value
patch_smali() {
    if [[ $is_eu_rom == "true" ]]; then
       SMALI_COMMAND="java -jar bin/apktool/smali-3.0.5.jar"
       BAKSMALI_COMMAND="java -jar bin/apktool/baksmali-3.0.5.jar" 
    else
       SMALI_COMMAND="java -jar bin/apktool/smali.jar"
       BAKSMALI_COMMAND="java -jar bin/apktool/baksmali.jar"
    fi
    targetfilefullpath=$(find build/portrom/images -type f -name $1)
    if [ -f $targetfilefullpath ];then
        targetfilename=$(basename $targetfilefullpath)
        yellow "正在修改 $targetfilename" "Modifying $targetfilename"
        foldername=${targetfilename%.*}
        rm -rf tmp/$foldername/
        mkdir -p tmp/$foldername/
        cp -rf $targetfilefullpath tmp/$foldername/
        7z x -y tmp/$foldername/$targetfilename *.dex -otmp/$foldername >/dev/null
        for dexfile in tmp/$foldername/*.dex;do
            smalifname=${dexfile%.*}
            smalifname=$(echo $smalifname | cut -d "/" -f 3)
            ${BAKSMALI_COMMAND} d --api ${port_android_sdk} ${dexfile} -o tmp/$foldername/$smalifname 2>&1 || error " Baksmaling 失败" "Baksmaling failed"
        done
        if [[ $2 == *"/"* ]];then
            targetsmali=$(find tmp/$foldername/*/$(dirname $2) -type f -name $(basename $2))
        else
            targetsmali=$(find tmp/$foldername -type f -name $2)
        fi
        if [ -f $targetsmali ];then
            smalidir=$(echo $targetsmali |cut -d "/" -f 3)
            yellow "I: 开始patch目标 ${smalidir}" "Target ${smalidir} Found"
            search_pattern=$3
            repalcement_pattern=$4
            if [[ $5 == 'regex' ]];then
                 sed -i "/${search_pattern}/c\\${repalcement_pattern}" $targetsmali
            else
            sed -i "s/$search_pattern/$repalcement_pattern/g" $targetsmali
            fi
            ${SMALI_COMMAND} a --api ${port_android_sdk} tmp/$foldername/${smalidir} -o tmp/$foldername/${smalidir}.dex > /dev/null 2>&1 || error " Smaling 失败" "Smaling failed"
            pushd tmp/$foldername/ >/dev/null || exit
            7z a -y -mx0 -tzip $targetfilename ${smalidir}.dex  > /dev/null 2>&1 || error "修改$targetfilename失败" "Failed to modify $targetfilename"
            popd >/dev/null || exit
            yellow "修补$targetfilename 完成" "Fix $targetfilename completed"
            if [[ $targetfilename == *.apk ]]; then
                yellow "检测到apk，进行zipalign处理。。" "APK file detected, initiating ZipAlign process..."
                rm -rf ${targetfilefullpath}

                # Align moddified APKs, to avoid error "Targeting R+ (version 30 and above) requires the resources.arsc of installed APKs to be stored uncompressed and aligned on a 4-byte boundary" 
                zipalign -p -f -v 4 tmp/$foldername/$targetfilename ${targetfilefullpath} > /dev/null 2>&1 || error "zipalign错误，请检查原因。" "zipalign error,please check for any issues"
                yellow "apk zipalign处理完成" "APK ZipAlign process completed."
                yellow "复制APK到目标位置：${targetfilefullpath}" "Copying APK to target ${targetfilefullpath}"
            else
                yellow "复制修改文件到目标位置：${targetfilefullpath}" "Copying file to target ${targetfilefullpath}"
                cp -rf tmp/$foldername/$targetfilename ${targetfilefullpath}
            fi
        fi
    else
        error "Failed to find $1,please check it manually".
    fi

}

unlock_device_feature() {
    feature_type=$2
    feature_name=$3
    feature_value=$4

    if [[ ! -z "$1" ]]; then
        comment=$1
    else
        comment="Whether enable $feature feature"
    fi
    if [[ $feature_type == "bool" ]] && [[ $feature_value == "" ]];then
        feature_value="true"
    fi

    if ! grep -q "$feature_name" build/portrom/images/product/etc/device_features/${base_rom_code}.xml;then
        sed -i "/<features>/a\\\t<!-- ${comment} -->\n\t<${feature_type} name=\"${feature_name}\">${feature_value}</${feature_type}> " build/portrom/images/product/etc/device_features/${base_rom_code}.xml
    else
        sed -i "s/<${feature_type} name=\"${feature_name}\">.*<\/${feature_type}>/<${feature_type} name=\"$feature_name\">${feature_value}<\/${feature_type}>/" build/portrom/images/product/etc/device_features/${base_rom_code}.xml
    fi
}

#check if a prperty is avaialble
is_property_exists () {
    if [ $(grep -c "$1" "$2") -ne 0 ]; then
        return 0
    else
        return 1
    fi
}

extract_partition() {
    part_img=$1
    part_name=$(basename ${part_img})
    target_dir=$2
    if [[ -f ${part_img} ]];then
        if [[ $($tools_dir/gettype -i ${part_img} ) == "ext" ]];then
            blue "[ext] 正在分解${part_name}" "[ext] Extracing ${part_name} "
            sudo python3 bin/imgextractor/imgextractor.py ${part_img} ${target_dir} >/dev/null 2>&1 || { error "分解 ${part_name} 失败" "Extracting ${part_name} failed."; exit 1; }
            green "[ext]分解[${part_name}] 完成" "[ext] ${part_name} extracted."
            rm -rf ${part_img}
        elif [[ $($tools_dir/gettype -i ${part_img}) == "erofs" ]]; then
            blue "[erofs] 正在分解${part_name} " "[erofs] Extracing ${part_name} "
            extract.erofs -x -i ${part_img}  -o $target_dir > /dev/null 2>&1 || { error "分解 ${part_name} 失败" "Extracting ${part_name} failed." ; exit 1; }
            green "[erofs] 分解[${part_name}] 完成" "[erofs] ${part_name} extracted."
            rm -rf ${part_img}
        else
            error "无法识别img文件类型，请检查" "Unable to handle img, exit."
            exit 1
        fi
    fi
}

disable_avb_verify() {
    fstab=$(find $1 -name "fstab*")
    if [[ $fstab == "" ]];then
        error "未找到 fstab 文件！" "No fstab found!"
        sleep 5
    else
        blue "禁用 AVB 验证中..." "Disabling AVB verfication...."
        for file in $fstab; do
            sed -i 's/,avb.*system//g' $file
            sed -i 's/,avb,/,/g' $file
            sed -i 's/,avb=.*a,/,/g' $file
            sed -i 's/,avb_keys.*key//g' $file
            if [[ "${pack_type}" == "EXT" ]];then
                sed -i "/erofs/d" $file
            fi
        done
        blue "AVB 验证禁用完成" "AVB verification disabled successfully"
    fi
}

# Check that a jar actually contains loadable dex bytecode (classes.dex /
# classes2.dex starting with the dex magic). Guards against broken jar
# rebuilds that would crash zygote at boot.
jar_has_valid_dex() {
    local j="$1" d=""
    [ -f "$j" ] || return 1
    d=$(unzip -p "$j" classes.dex 2>/dev/null | head -c 4)
    [ "${d:0:3}" = "dex" ] && return 0
    d=$(unzip -p "$j" classes2.dex 2>/dev/null | head -c 4)
    [ "${d:0:3}" = "dex" ]
}

# Fallback: disable the APK signature scheme enforcement inside services.jar.
# Used on Android 14+ ports when the external FrameworkPatcher is unavailable or fails,
# otherwise replaced/patched system apps fail to install and the ROM never finishes booting.
bypass_apk_signature_check() {
    yellow "开始移除 APK 签名校验 (services.jar)" "Disabling APK Signature Verifier (services.jar)"
    if [[ ! -f build/portrom/images/system/system/framework/services.jar ]]; then
        error "未找到 services.jar，跳过签名补丁" "services.jar not found, skipping signature patch"
        return 1
    fi

    if [[ ! -d tmp ]]; then
        mkdir -p tmp/
    fi
    rm -rf tmp/services tmp/services.jar tmp/services_patched.jar
    cp -f build/portrom/images/system/system/framework/services.jar tmp/services.jar

    java -jar bin/apktool/APKEditor.jar d -f -i tmp/services.jar -o tmp/services > /dev/null 2>&1

    target_method='getMinimumSignatureSchemeVersionForTargetSdk'
    old_smali_dir=""
    declare -a smali_dirs

    while read -r smali_file; do
        smali_dir=$(echo "$smali_file" | cut -d "/" -f 3)

        if [[ $smali_dir != $old_smali_dir ]]; then
            smali_dirs+=("$smali_dir")
        fi

        method_line=$(grep -n "$target_method" "$smali_file" | cut -d ':' -f 1)
        register_number=$(tail -n +"$method_line" "$smali_file" | grep -m 1 "move-result" | tr -dc '0-9')
        move_result_end_line=$(awk -v ML=$method_line 'NR>=ML && /move-result /{print NR; exit}' "$smali_file")
        orginal_line_number=$method_line
        replace_with_command="const/4 v${register_number}, 0x0"
        { sed -i "${orginal_line_number},${move_result_end_line}d" "$smali_file" && sed -i "${orginal_line_number}i\\${replace_with_command}" "$smali_file"; } &&    blue "${smali_file}  修改成功" "${smali_file} patched"
        old_smali_dir=$smali_dir
    done < <(find tmp/services/smali/*/com/android/server/pm/ tmp/services/smali/*/com/android/server/pm/pkg/parsing/ -maxdepth 1 -type f -name "*.smali" -exec grep -H "$target_method" {} \; 2>/dev/null | cut -d ':' -f 1)

    java -jar bin/apktool/APKEditor.jar b -f -i tmp/services -o tmp/services_patched.jar > /dev/null 2>&1
    if [ -f tmp/services_patched.jar ] && jar_has_valid_dex tmp/services_patched.jar; then
        cp -f build/portrom/images/system/system/framework/services.jar build/portrom/images/system/system/framework/services.jar.bak
        cp -rf tmp/services_patched.jar build/portrom/images/system/system/framework/services.jar
        green "APK 签名校验已移除" "APK signature verifier disabled successfully"
    elif [ -f tmp/services_patched.jar ]; then
        red "Пересобранный services.jar содержит битый dex, откат к оригиналу" "Rebuilt services.jar has broken dex, keeping original"
    else
        error "services.jar 重打包失败" "Failed to rebuild services.jar"
    fi
    rm -rf tmp/services tmp/services.jar tmp/services_patched.jar
}

# Function to update netlink in build.prop
update_netlink() {
  local netlink_version=$1
  local prop_file=$2

  if grep -q "ro.millet.netlink" "$prop_file"; then
    blue "找到ro.millet.netlink修改值为$netlink_version" "millet_netlink propery found, changing value to $netlink_version"
    sed -i "s/ro.millet.netlink=.*/ro.millet.netlink=$netlink_version/" "$prop_file"
  else
    blue "PORTROM未找到ro.millet.netlink值,添加为$netlink_version" "millet_netlink not found in portrom, adding new value $netlink_version"
    echo -e "ro.millet.netlink=$netlink_version\n" >> "$prop_file"
  fi
}

# Android 17 support (HyperOS 3/4 donors): retarget the old base vendor sepolicy
# from version 30 to version 31 so it matches the new system policy mappings.
# Based on the guide by @itsxiima. Runs offline on the extracted trees:
#   - vendor:   build/portrom/images/vendor/etc/selinux/{vendor_sepolicy,plat_pub_versioned}.cil
#   - mappings: build/portrom/images/{system,system_ext,product}/.../selinux/mapping/31.0.cil
retarget_vendor_sepolicy_31() {
    local selinux_dir="build/portrom/images/vendor/etc/selinux"
    local vendor_cil="${selinux_dir}/vendor_sepolicy.cil"
    local plat_pub_cil="${selinux_dir}/plat_pub_versioned.cil"
    local tmpdir have_count need_count

    if [[ ! -f "${vendor_cil}" || ! -f "${plat_pub_cil}" ]]; then
        yellow "vendor_sepolicy.cil/plat_pub_versioned.cil не найдены, ретаргетинг пропущен" "vendor_sepolicy.cil/plat_pub_versioned.cil not found, skipping sepolicy retarget"
        return 1
    fi

    # Donor mapping files: at least the system one must exist
    map_list=()
    [ -f "build/portrom/images/system/system/etc/selinux/mapping/31.0.cil" ] && map_list+=("build/portrom/images/system/system/etc/selinux/mapping/31.0.cil")
    [ -f "build/portrom/images/system_ext/etc/selinux/mapping/31.0.cil" ] && map_list+=("build/portrom/images/system_ext/etc/selinux/mapping/31.0.cil")
    [ -f "build/portrom/images/product/etc/selinux/mapping/31.0.cil" ] && map_list+=("build/portrom/images/product/etc/selinux/mapping/31.0.cil")
    if [ ${#map_list[@]} -eq 0 ]; then
        error "В доноре нет mapping/31.0.cil — ретаргетинг sepolicy невозможен" "Donor has no mapping/31.0.cil - cannot retarget vendor sepolicy"
        exit 1
    fi

    blue "Ретаргетинг vendor sepolicy на версию 31" "Retargeting vendor sepolicy to version 31"

    # Step 2: rename all _30_0 references to _31_0 in vendor policy
    sed -i 's/_30_0/_31_0/g' "${vendor_cil}"
    sed -i 's/_30_0/_31_0/g' "${plat_pub_cil}"

    tmpdir=$(mktemp -d)

    # Attributes the vendor declares
    grep -ohE '\(typeattribute [A-Za-z0-9_-]+_31_0\)' \
        "${vendor_cil}" "${plat_pub_cil}" \
        | sed -E 's/\(typeattribute (.*)\)/\1/' | sort -u > "${tmpdir}/have.txt"
    have_count=$(wc -l < "${tmpdir}/have.txt")

    # Attributes the new system references
    cat "${map_list[@]}" \
        | grep -ohE '\(expandtypeattribute \([A-Za-z0-9_-]+_31_0\)|\(typeattributeset [A-Za-z0-9_-]+_31_0' \
        | grep -oE '[A-Za-z0-9_-]+_31_0' | sort -u > "${tmpdir}/want.txt"

    # Missing declarations -> append them to plat_pub_versioned.cil
    comm -13 "${tmpdir}/have.txt" "${tmpdir}/want.txt" > "${tmpdir}/need.txt"
    need_count=$(wc -l < "${tmpdir}/need.txt")
    if [ "${need_count}" -gt 0 ]; then
        echo ';; added when retargeting vendor sepolicy to 31' >> "${plat_pub_cil}"
        sed 's/^/(typeattribute /; s/$/)/' "${tmpdir}/need.txt" >> "${plat_pub_cil}"
    fi

    # Step 4: spoof platform sepolicy version so init picks the 31.0 mapping
    printf '31.0\n' > "${selinux_dir}/plat_sepolicy_vers.txt"

    green "Sepolicy ретаргечен на 31 (объявлено: ${have_count}, дописано деклараций: ${need_count})" "Vendor sepolicy retargeted to 31 (declared: ${have_count}, added declarations: ${need_count})"
    rm -rf "${tmpdir}"
}

# HyperOS 3/4 vibration fix (Android 17): installs the vibrator-bridge AIDL HAL
# from devices/common/vibrator_hos4.zip into the vendor tree, appends its sepolicy
# rules and stores its fs_config/file_contexts overrides for the packer.
apply_vibrator_fix_hos4() {
    local zipfile="devices/common/vibrator_hos4.zip"
    local vendir="build/portrom/images/vendor"
    local extract_dir="tmp/vibrator_hos4"

    if [[ ! -f "${zipfile}" ]]; then
        yellow "${zipfile} не найден, пропуск фикса вибрации" "${zipfile} not found, skipping vibration fix"
        return 1
    fi

    blue "Устанавливаю фикс вибрации vibrator-bridge (HyperOS 3/4)" "Installing vibrator-bridge vibration fix (HyperOS 3/4)"
    rm -rf "${extract_dir}"
    mkdir -p "${extract_dir}"
    unzip -oq "${zipfile}" -d "${extract_dir}" || { error "Не удалось распаковать vibrator_hos4.zip" "Failed to extract vibrator_hos4.zip"; rm -rf "${extract_dir}"; return 1; }

    # 1) Copy payload into vendor with correct host-side permissions
    mkdir -p "${vendir}/bin/hw" "${vendir}/etc/init" "${vendir}/etc/vintf/manifest"
    cp -f "${extract_dir}/vendor/bin/hw/vibrator-bridge"                 "${vendir}/bin/hw/"
    cp -f "${extract_dir}/vendor/etc/init/vibrator-bridge.rc"            "${vendir}/etc/init/"
    cp -f "${extract_dir}/vendor/etc/vintf/manifest/vibrator-bridge.xml" "${vendir}/etc/vintf/manifest/"
    chmod 0755 "${vendir}/bin/hw/vibrator-bridge"
    chmod 0644 "${vendir}/etc/init/vibrator-bridge.rc" "${vendir}/etc/vintf/manifest/vibrator-bridge.xml"

    # 2) Append sepolicy allow rules (idempotent)
    if [ -f "${extract_dir}/policy.cil" ] && [ -f "${vendir}/etc/selinux/vendor_sepolicy.cil" ]; then
        if ! grep -q "hal_vibrator_default" "${vendir}/etc/selinux/vendor_sepolicy.cil"; then
            yellow "Тип hal_vibrator_default отсутствует в vendor_sepolicy.cil, правила могут не примениться" "Type hal_vibrator_default missing from vendor_sepolicy.cil, rules may not take effect"
        fi
        if ! grep -q ";; vibrator-bridge (HyperOS 3/4 fix)" "${vendir}/etc/selinux/vendor_sepolicy.cil"; then
            {
                echo ""
                echo ";; vibrator-bridge (HyperOS 3/4 fix)"
                cat "${extract_dir}/policy.cil"
            } >> "${vendir}/etc/selinux/vendor_sepolicy.cil"
        fi
    else
        yellow "vendor_sepolicy.cil не найден, sepolicy-часть фикса пропущена" "vendor_sepolicy.cil not found, skipping sepolicy part of the fix"
    fi

    # 3) Store permission/label overrides, merged into generated packer
    #    configs by merge_vibrator_pack_configs() right before image creation
    mkdir -p build/portrom/images/config
    cat "${extract_dir}/config/vendor_fs_config"     > build/portrom/images/config/vibrator_fs_config
    cat "${extract_dir}/config/vendor_file_contexts" > build/portrom/images/config/vibrator_file_contexts

    green "Фикс вибрации установлен (0755 root:shell для HAL, контексты и sepolicy)" "Vibration fix installed (HAL 0755 root:shell, contexts and sepolicy applied)"
}

# Merge the vibrator-bridge fs_config / file_contexts overrides into the
# configs generated by fspatch.py / contextpatch.py. Those tools guess labels
# for new files (usually plain vendor_file), which breaks HAL startup - these
# authoritative entries guarantee correct ownership/mode/labels:
#   vendor/bin/hw/vibrator-bridge         -> 0 2000 0755, hal_vibrator_default_exec
#   vendor/etc/{init,vintf/manifest}/...  -> 0 0 0644,   vendor_configs_file
merge_vibrator_pack_configs() {
    local part="$1"
    local cfgdir="build/portrom/images/config"
    local fsf="${cfgdir}/${part}_fs_config"
    local ctxf="${cfgdir}/${part}_file_contexts"

    [ -s "${cfgdir}/vibrator_fs_config" ] || return 0
    [ -f "${fsf}" ] || return 0

    # fs_config: normalize the zip's slot-prefixed style (vendor_a/...) to the
    # generated format (vendor/...), drop any auto-generated duplicates, append
    sed 's|^vendor_a/|'"${part}"'/|' "${cfgdir}/vibrator_fs_config" > "${cfgdir}/vibrator_fs_config.norm"
    sed -i '\#bin/hw/vibrator-bridge 0 #d;\#etc/init/vibrator-bridge\.rc 0 #d;\#etc/vintf/manifest/vibrator-bridge\.xml 0 #d' "${fsf}"
    cat "${cfgdir}/vibrator_fs_config.norm" >> "${fsf}"
    rm -f "${cfgdir}/vibrator_fs_config.norm"

    # file_contexts: drop guessed labels for our files, append authoritative ones
    if [ -f "${ctxf}" ]; then
        sed -i '/vibrator-bridge/d' "${ctxf}"
        cat "${cfgdir}/vibrator_file_contexts" >> "${ctxf}"
    fi

    green "Права и контексты vibrator-bridge применены к ${part}" "vibrator-bridge permissions/contexts merged into ${part} configs"
}

patch_kernel_to_bootimg() {
    kernel_file=$1
    dtb_file=$2
    bootimg_name=$3
    mkdir -p ${work_dir}/tmp/boot
    cd ${work_dir}/tmp/boot
    bootimg=$(find ${work_dir}/build/baserom -name "boot.img")
    cp $bootimg ${work_dir}/tmp/boot/boot.img
    magiskboot unpack -h ${work_dir}/tmp/boot/boot.img > /dev/null 2>&1
    if [ -f ramdisk.cpio ]; then
    comp=$(magiskboot decompress ramdisk.cpio | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
    if [ "$comp" ]; then
        mv -f ramdisk.cpio ramdisk.cpio.$comp
        magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio > /dev/null 2>&1
        if [ $? != 0 ] && $comp --help; then
        $comp -dc ramdisk.cpio.$comp >ramdisk.cpio
        fi
    fi
    mkdir -p ramdisk
    chmod 755 ramdisk
    cd ramdisk
    EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F ../ramdisk.cpio -i
    disable_avb_verify ${work_dir}/tmp/boot/
    #添加erofs文件系统fstab
    if [[ ${pack_type} == "EROFS" ]];then
        blue "检查 ramdisk fstab.qcom是否需要添加erofs挂载点" "Check if ramdisk fstab.qcom needs to add erofs mount point."
        if ! grep -q "erofs" ${work_dir}/tmp/boot/ramdisk/fstab.qcom ; then
                for pname in ${super_list}; do
                    sed -i "/\/${pname}[[:space:]]\+ext4/{p;s/ext4/erofs/;s/ro,barrier=1,discard/ro/;}" ${work_dir}/tmp/boot/ramdisk/fstab.qcom
                    added_line=$(sed -n "/\/${pname}[[:space:]]\+erofs/p" ${work_dir}/tmp/boot/ramdisk/fstab.qcom)
    
                    if [ -n "$added_line" ]; then
                        yellow "添加${pname}成功" "Adding erofs mount point [$pname]"
                    else
                        error "添加失败，请检查" "Adding faild, please check."
                        exit 1 
                    fi
                done
          fi
      fi
    fi
    sudo cp -f $kernel_file ${work_dir}/tmp/boot/kernel
    if [ -n "${dtb_file}" ] && [ -f "${dtb_file}" ]; then
        sudo cp -f $dtb_file ${work_dir}/tmp/boot/dtb
    else
        yellow "dtb не найден в архиве ядра, оставляю стоковый dtb" "No dtb found in kernel zip, keeping stock dtb"
    fi
    cd ${work_dir}/tmp/boot/ramdisk/
    find | sed 1d | cpio -H newc -R 0:0 -o -F ../ramdisk_new.cpio > /dev/null 2>&1
    cd ..
    if [ "$comp" ]; then
      magiskboot compress=$comp ramdisk_new.cpio
      if [ $? != 0 ] && $comp --help > /dev/null 2>&1; then
          $comp -9c ramdisk_new.cpio >ramdisk.cpio.$comp
      fi
    fi
    ramdisk=$(ls ramdisk_new.cpio* | tail -n1)
    if [ "$ramdisk" ]; then
      cp -f $ramdisk ramdisk.cpio
      case $comp in
      cpio) nocompflag="-n" ;;
      esac
      magiskboot repack $nocompflag ${work_dir}/tmp/boot/boot.img ${work_dir}/devices/$base_rom_code/${bootimg_name} >/dev/null 2>&1
    fi
    rm -rf ${work_dir}/tmp/boot
    cd $work_dir
}