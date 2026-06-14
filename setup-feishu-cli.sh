#!/bin/bash
# ============================================================
# 飞书 CLI + SKILL 一键安装脚本
# 在新电脑上运行此脚本即可完成配置
# ============================================================
set -e

echo "=== 1/4 安装飞书 CLI ==="
npm install -g @larksuite/cli

echo ""
echo "=== 2/4 安装飞书 SKILL（27 个） ==="
npx -y skills add https://open.feishu.cn --skill -y

echo ""
echo "=== 3/4 配置应用凭证 ==="
if [ -z "$FEISHU_APP_SECRET" ]; then
  echo "❌ 请先设置环境变量: export FEISHU_APP_SECRET='你的App Secret'"
  exit 1
fi
echo "$FEISHU_APP_SECRET" | lark-cli config init --app-id "cli_aaa482d9dcb8dbcd" --app-secret-stdin

echo ""
echo "=== 验证 ==="
lark-cli auth status

echo ""
echo "✅ 飞书 CLI 配置完成！（Bot 身份已就绪，无需用户登录）"
echo ""
echo "如需用户身份（发消息、查日程等），手动运行："
echo "  lark-cli auth login --recommend"
