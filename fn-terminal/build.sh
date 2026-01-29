#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

WORKDIR="$(
  cd "$(dirname "$0")"
  pwd
)"

ARCH=(
  x86_64
  aarch64
)

DEBS=(
  https://mirrors.ustc.edu.cn/debian/pool/main/libu/libutempter/libutempter0_1.2.1-3_@ARCH@.deb
  https://mirrors.ustc.edu.cn/debian/pool/main/t/tmux/tmux_3.3a-3_@ARCH@.deb
)

command -v dpkg-deb >/dev/null 2>&1 || apt update >/dev/null 2>&1 && apt install -y dpkg-deb >/dev/null 2>&1

for a in "${ARCH[@]}"; do
  rm -rf "${WORKDIR}/app/server/${a}" 2>/dev/null || true
  for d in "${DEBS[@]}"; do
    p="$(echo "${a}" | sed 's/x86_64/amd64/; s/aarch64/arm64/')"
    url=$(echo "${d}" | sed "s/@ARCH@/${p}/g")
    deb=$(basename ${url})
    echo "getting ${deb} for ${a}..."
    wget -O "${deb}" "${url}" >/dev/null
    if [ $? -ne 0 ]; then
      echo "ERROR: Failed to download ${deb}"
      exit 1
    fi
    mkdir -p "${WORKDIR}/app/server/${a}"
    dpkg-deb -X "${deb}" "${WORKDIR}/app/server/${a}"
    if [ $? -ne 0 ]; then
      echo "ERROR: dpkg-deb extraction failed"
      exit 1
    fi
    # rm -rf "${WORKDIR}/app/server/${a}/usr/share" 2>/dev/null || true
    rm -f "${deb}"
  done
  echo "getting ttyd for ${a}..."
  mkdir -p "${WORKDIR}/app/server/${a}/usr/bin"
  wget -O "${WORKDIR}/app/server/${a}/usr/bin/ttyd" "https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.${a}" >/dev/null 2>&1 || {
    echo "ERROR: Failed to download ttyd"
    exit 1
  }
  chmod +x "${WORKDIR}/app/server/${a}/usr/bin/ttyd" 2>/dev/null
  [ ! -x "${WORKDIR}/app/server/${a}/usr/bin/ttyd" ] && {
    echo "ERROR: Failed to set execute permission for ttyd"
    exit 1
  }
done

echo "Done"

APPNAME=$(grep '^appname' "${WORKDIR}/manifest" | awk -F= '{print $2}' | xargs)
VERSION=$(grep '^version' "${WORKDIR}/manifest" | awk -F= '{print $2}' | xargs)
PLATFORM=$(grep '^platform' "${WORKDIR}/manifest" | awk -F= '{print $2}' | xargs)
rm -f "${WORKDIR}/app.tgz" "$(dirname "${WORKDIR}")/${APPNAME}_${PLATFORM}_v${VERSION}.fpk" 2>/dev/null || true
tar -czf "${WORKDIR}/app.tgz" -C "${WORKDIR}/app" . >/dev/null 2>&1
tar -czf "$(dirname "${WORKDIR}")/${APPNAME}_${PLATFORM}_v${VERSION}.fpk" -C "${WORKDIR}" cmd config wizard app.tgz ICON.PNG ICON_256.PNG manifest >/dev/null 2>&1

if [ "${PLATFORM}" = "all" ]; then
  for P in x86 arm; do
    sed -i "s/= all/= ${P}/" "${WORKDIR}/manifest"
    rm -f "$(dirname "${WORKDIR}")/${APPNAME}_${P}_v${VERSION}.fpk" 2>/dev/null || true
    tar -czf "$(dirname "${WORKDIR}")/${APPNAME}_${P}_v${VERSION}.fpk" -C "${WORKDIR}" cmd config wizard app.tgz ICON.PNG ICON_256.PNG manifest >/dev/null 2>&1
    sed -i "s/= ${P}/= all/" "${WORKDIR}/manifest"
  done
fi

rm -f "${WORKDIR}/app.tgz"

exit 0
