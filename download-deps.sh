#!/usr/bin/env bash
#
# 下载运行时依赖的 jar 到 ./lib 目录（该目录不入库）。
#
# 用法：
#   ./download-deps.sh
#   MAVEN_MIRROR=https://maven.aliyun.com/repository/public ./download-deps.sh
#
set -euo pipefail

cd "$(dirname "$0")"

MAVEN_MIRROR="${MAVEN_MIRROR:-https://repo1.maven.org/maven2}"
MAVEN_MIRROR="${MAVEN_MIRROR%/}"

# 相对 Maven 仓库的路径 -> 落地的文件名
ARTIFACTS=(
  "org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar"
  "org/apache/iceberg/iceberg-aws/1.10.1/iceberg-aws-1.10.1.jar"
  "org/apache/iceberg/iceberg-aws-bundle/1.10.1/iceberg-aws-bundle-1.10.1.jar"
)

mkdir -p lib

for path in "${ARTIFACTS[@]}"; do
  name="$(basename "$path")"
  target="lib/$name"

  # Docker 会把缺失的 bind-mount 源创建成目录，这里先清掉
  if [[ -d "$target" ]]; then
    echo "[warn] $target 是目录（可能由 docker compose 创建），删除后重新下载"
    rmdir "$target" 2>/dev/null || rm -rf "$target"
  fi

  if [[ -f "$target" && -s "$target" ]]; then
    echo "[skip] $name 已存在"
    continue
  fi

  url="$MAVEN_MIRROR/$path"
  echo "[fetch] $url"
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$target.part" "$url"

  # 防止把 HTML 错误页当成 jar 保存下来
  if ! head -c 2 "$target.part" | grep -q 'PK'; then
    echo "[error] $name 不是有效的 jar（可能下载到了错误页）" >&2
    rm -f "$target.part"
    exit 1
  fi

  mv "$target.part" "$target"
done

echo
echo "依赖已就绪："
ls -lh lib
