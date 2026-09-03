#!/bin/bash
# ============================================================
# _lib.sh - install.sh / postinstall.sh 共享的 npm wrapper
#
# 用法：source scripts/_lib.sh（在 cd 到项目根之后）
# 依赖：$NPM_REGISTRY（install.sh 预检后 export，postinstall.sh 继承）
# ============================================================

# npm wrapper：NPM_REGISTRY 非空时自动加 --registry（镜像延迟时切官方源）
_npm() {
  if [ -n "${NPM_REGISTRY:-}" ]; then
    npm "$@" --registry="$NPM_REGISTRY"
  else
    npm "$@"
  fi
}

# check_mem_patch <spec目录名>：三态检查 pin 目录 tags patch（在/缺/目录缺失）
# 返回 0=patch 在，1=缺 patch，2=pin 目录缺失；echo 判定结果供展示（严格 -F 前缀防碰撞）
check_mem_patch() {
  local spec="$1"
  local dir="$HOME/.cache/opencode/packages/$spec/node_modules/opencode-mem"
  if [ ! -d "$dir" ]; then
    echo "DIR_MISSING $spec"
    return 2
  fi
  if grep -qF "PATCH(tags-fallback)" "$dir/dist/services/client.js" 2>/dev/null; then
    echo "PATCHED $spec"
    return 0
  fi
  echo "NO_PATCH $spec"
  return 1
}
