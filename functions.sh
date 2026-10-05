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

merge_mi_ext_metadata() {
    local source_file=$1 target_file=$2 source_prefix=$3 target_prefix=$4
    local merged_file
    [[ -f "$source_file" ]] || return 0
    touch "$target_file" || return 1
    merged_file=$(mktemp "${target_file}.XXXXXX") || return 1
    if cp -p "$target_file" "$merged_file" && awk -v source_prefix="$source_prefix" -v target_prefix="$target_prefix" '
        FILENAME == ARGV[1] {
            path = $1
            suffix = substr(path, length(source_prefix) + 1)
            if (index(path, source_prefix) == 1 && (suffix == "" || suffix ~ /^[\/\(]/)) {
                $1 = target_prefix suffix
                if (!($1 in entries)) order[++count] = $1
                entries[$1] = $0
            }
            next
        }
        !($1 in entries) { print }
        END { for (i = 1; i <= count; i++) print entries[order[i]] }
    ' "$source_file" "$target_file" > "$merged_file"; then
        mv -f "$merged_file" "$target_file" && return 0
    fi
    rm -f "$merged_file"
    return 1
}

merge_mi_ext_props() {
    local source_file=$1 target_file=$2 merged_file
    [[ -f "$source_file" ]] || return 0
    mkdir -p "$(dirname "$target_file")" || return 1
    touch "$target_file" || return 1
    merged_file=$(mktemp "${target_file}.XXXXXX") || return 1
    if cp -p "$target_file" "$merged_file" && awk '
        function property_key(line, key) {
            if (line !~ /^[[:space:]]*[[:alnum:]_.-]+[[:space:]]*=/) return ""
            key = substr(line, 1, index(line, "=") - 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            return key
        }
        { sub(/\r$/, "") }
        FILENAME == ARGV[1] {
            key = property_key($0)
            if (key != "") {
                if (!(key in props)) order[++count] = key
                props[key] = $0
            }
            next
        }
        {
            key = property_key($0)
            if (key in props) {
                if (!seen[key]++) print props[key]
            } else print
        }
        END { for (i = 1; i <= count; i++) if (!seen[order[i]]) print props[order[i]] }
    ' "$source_file" "$target_file" > "$merged_file"; then
        mv -f "$merged_file" "$target_file" && return 0
    fi
    rm -f "$merged_file"
    return 1
}

merge_mi_ext() {
    local images_dir=$1 mi_ext_dir="$1/mi_ext"
    local partition source_dir target_dir target_prefix config_type source_prefix config_target_prefix
    [[ -d "$mi_ext_dir" ]] || return 0
    blue "合并移植包 mi_ext" "Merging donor mi_ext into system, system_ext and product"
    for partition in system system_ext product; do
        source_dir="$mi_ext_dir/$partition"
        [[ -d "$source_dir" ]] || continue
        target_prefix=$partition
        [[ "$partition" == system ]] && target_prefix=system/system
        target_dir="$images_dir/$target_prefix"
        mkdir -p "$target_dir" "$images_dir/config" || return 1
        # Copy directory contents, including hidden files and symlinks, then
        # remove the source only after its files and packing metadata are merged.
        cp -af "$source_dir/." "$target_dir/" || return 1
        for config_type in fs_config file_contexts; do
            source_prefix="mi_ext/$partition"
            config_target_prefix=$target_prefix
            if [[ "$config_type" == file_contexts ]]; then
                source_prefix="/$source_prefix"
                config_target_prefix="/$target_prefix"
            fi
            merge_mi_ext_metadata "$images_dir/config/mi_ext_$config_type" \
                "$images_dir/config/${partition}_$config_type" \
                "$source_prefix" "$config_target_prefix" || return 1
        done
        rm -rf "$source_dir" || return 1
    done
    # Merge properties after the product tree so its build.prop cannot overwrite them.
    # Keep mi_ext/etc/build.prop for the existing ROM-version detection and packing.
    merge_mi_ext_props "$mi_ext_dir/etc/build.prop" "$images_dir/product/etc/build.prop"
}

disable_avb_verify() {
    fstab=$1
    blue "Disabling avb_verify: $fstab"
    if [[ ! -f $fstab ]]; then
        yellow "$fstab not found, please check it manually"
    else
        sed -i "s/,avb_keys=.*avbpubkey//g" $fstab
        sed -i "s/,avb=vbmeta_system//g" $fstab
        sed -i "s/,avb=vbmeta_vendor//g" $fstab
        sed -i "s/,avb=vbmeta//g" $fstab
        sed -i "s/,avb//g" $fstab
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
    sudo cp -f $dtb_file ${work_dir}/tmp/boot/dtb
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
