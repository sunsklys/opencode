#!/usr/bin/env bash
# opencode-export.sh - 导出 opencode 配置（不含敏感凭证）
# Usage: ./opencode-export.sh [输出目录，默认 ~/Desktop]

set -euo pipefail

OUT_DIR="${1:-$HOME/Desktop}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE="opencode-config-${TIMESTAMP}.tar.gz"
FULL_PATH="${OUT_DIR}/${ARCHIVE}"

CONFIG_DIR="$HOME/.config/opencode"
DATA_DIR="$HOME/.local/share/opencode"

if [[ ! -d "$CONFIG_DIR" ]]; then
  echo "❌ $CONFIG_DIR not found" >&2
  exit 1
fi

# 创建临时工作目录
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# 拷贝配置文件（排除 node_modules / db / cache）
mkdir -p "$TMP/config/opencode"
cp "$CONFIG_DIR"/*.json "$TMP/config/opencode/" 2>/dev/null || true
cp "$CONFIG_DIR"/*.jsonc "$TMP/config/opencode/" 2>/dev/null || true
cp "$CONFIG_DIR/.gitignore" "$TMP/config/opencode/" 2>/dev/null || true
# package-lock.json 一起带上保证依赖一致
[[ -f "$CONFIG_DIR/package-lock.json" ]] && cp "$CONFIG_DIR/package-lock.json" "$TMP/config/opencode/"

# 询问是否包含 auth.json
echo ""
read -p "是否包含 auth.json (含 API key，可在新机器免登录)? [y/N] " include_auth
if [[ "$include_auth" =~ ^[yY]$ ]]; then
  mkdir -p "$TMP/data/opencode"
  cp "$DATA_DIR/auth.json" "$TMP/data/opencode/" 2>/dev/null || true
  echo "⚠️  已包含 auth.json - 注意保护此压缩包"
else
  echo "ℹ️  未包含 auth.json - 新机器需重新 'opencode auth login'"
fi

# 写入恢复说明
cat > "$TMP/README.md" <<'EOF'
# opencode 配置恢复指南

## 前置依赖（在新机器）

```bash
# 1. 安装 Node.js (推荐 fnm 管理)
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 22

# 2. 安装 opencode
curl -fsSL https://opencode.ai/install | bash
# 或: npm i -g opencode-ai
```

## 恢复配置

```bash
# 1. 解压到正确位置
tar -xzf opencode-config-*.tar.gz
mkdir -p ~/.config/opencode ~/.local/share/opencode
cp -r config/opencode/* ~/.config/opencode/
[[ -d data/opencode ]] && cp -r data/opencode/* ~/.local/share/opencode/

# 2. 安装依赖
cd ~/.config/opencode
npm install

# 3. 若未带 auth.json，需重新登录
opencode auth login zhipuai-coding-plan

# 4. 验证
opencode --version
```

## 配置文件清单
- opencode.json   - provider 定义 + 模型 limit
- opencode.jsonc  - MCP 服务 + plugin
- oh-my-openagent.json - 11 agent + 8 category 路由
- package.json    - OMO 依赖锁
- tui.json        - 主题
EOF

# 打包
cd "$TMP"
tar -czf "$FULL_PATH" .

echo ""
echo "✅ 导出成功"
echo "📦 $FULL_PATH"
echo "📏 $(du -sh "$FULL_PATH" | cut -f1)"
echo ""
echo "📋 包含文件:"
tar -tzf "$FULL_PATH" | sort
