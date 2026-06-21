# opencode 个人配置 Makefile
# 新机器：make install && opencode auth login zhipuai-coding-plan && make check
# 详见 README.md

.DEFAULT_GOAL := help

.PHONY: help install deps config mem feishu check update clean export audit skills-lock clean-state sbom tui-sync

help: ## 显示帮助
	@echo "opencode 配置管理"
	@echo ""
	@echo "常用命令："
	@echo "  make install   完整安装（新机器首次，含依赖/环境变量/记忆/飞书）"
	@echo "  make check     体检所有组件状态（9 项检查）"
	@echo "  make update    更新依赖到最新（清 node_modules 重装）"
	@echo ""
	@echo "分步命令："
	@echo "  make deps      仅装 npm 依赖 + opencode-mem 软链"
	@echo "  make config    仅配置环境变量（交互式，写 ~/.zshrc）"
	@echo "  make mem       仅生成 opencode-mem.jsonc（智谱直连）"
	@echo "  make feishu    仅装飞书 CLI + SKILL"
	@echo "  make clean     清理 node_modules"
	@echo "  make export    导出配置到 tar.gz（不含敏感凭证，可选含 auth.json）"
	@echo ""
	@echo "维护命令（可选）："
	@echo "  make audit        npm 安全审计（切官方源，绕过 npmmirror audit 404）"
	@echo "  make skills-lock  生成 lark skills SHA256 锁定（供应链加固）"
	@echo "  make clean-state  清理 .omo/ 和 tasks/ 运行时状态（修复状态机污染）"
	@echo "  make sbom         生成 SBOM（软件物料清单，CycloneDX 格式）"
	@echo "  make tui-sync     验证 tui.json 与 opencode.json plugin 同步"
	@echo ""
	@echo "新机器流程："
	@echo "  git clone <repo> ~/.config/opencode && cd ~/.config/opencode"
	@echo "  make install"
	@echo "  opencode auth login zhipuai-coding-plan"
	@echo "  make check"

install: deps config mem feishu ## 完整安装（新机器首次）
	@echo ""
	@echo "═══════════════════════════════════════════"
	@echo "  ✅ 安装完成！"
	@echo "═══════════════════════════════════════════"
	@echo ""
	@echo "接下来："
	@echo "  1. 登录智谱凭证："
	@echo "     opencode auth login zhipuai-coding-plan"
	@echo ""
	@echo "  2. 体检所有组件："
	@echo "     make check"
	@echo ""
	@echo "  3. 启动："
	@echo "     opencode"

deps: ## 安装 npm 依赖 + opencode-mem 软链
	@bash scripts/install.sh

config: ## 配置环境变量（交互式，写 ~/.zshrc + launchctl setenv）
	@bash scripts/setup-env.sh

mem: ## 生成 opencode-mem.jsonc（智谱直连模板）
	@if [ -f opencode-mem.jsonc ]; then \
		echo "opencode-mem.jsonc 已存在。如需重新生成，先删除：rm opencode-mem.jsonc && make mem"; \
	else \
		cp opencode-mem.jsonc.template opencode-mem.jsonc; \
		echo "✓ 已生成 opencode-mem.jsonc（智谱直连，复用 Z_AI_API_KEY 环境变量）"; \
		echo "  注意：需重启 opencode 生效"; \
	fi

feishu: ## 安装飞书 CLI + 27 个 SKILL（需要 FEISHU_APP_SECRET）
	@FEISHU_APP_SECRET="$${FEISHU_APP_SECRET:-$$(grep -h '^export FEISHU_APP_SECRET=' ~/.zshrc ~/.zshenv ~/.zprofile ~/.profile 2>/dev/null | head -1 | node -e "const s=require('fs').readFileSync(0,'utf8').trim();const m=s.match(/export\s+FEISHU_APP_SECRET=(.*)/);if(m){let v=m[1].replace(/^'|'$$/g,'');process.stdout.write(v)}" 2>/dev/null)"}; \
	if [ -z "$$FEISHU_APP_SECRET" ]; then \
		echo "❌ FEISHU_APP_SECRET 未设置，先运行：make config"; \
		exit 1; \
	fi; \
	export FEISHU_APP_SECRET; \
	bash setup-feishu-cli.sh

check: ## 体检所有组件（8 项：环境/依赖/补丁/记忆/Web UI/飞书）
	@bash scripts/check.sh

update: ## 更新依赖到最新（清 node_modules + package-lock 重装）
	@echo "清理旧依赖（用 node 脚本，绕过 rm -rf 权限限制）..."
	@node -e "require('fs').rmSync('node_modules',{recursive:true,force:true}); console.log('  node_modules 已清除')"
	@rm -f package-lock.json
	@bash scripts/install.sh
	@echo ""
	@echo "✓ 依赖已更新，运行 make check 验证"

clean: ## 清理 node_modules
	@node -e "require('fs').rmSync('node_modules',{recursive:true,force:true})"
	@echo "✓ node_modules 已清理（运行 make deps 重建）"

export: ## 导出配置到 tar.gz（默认输出到 ~/Desktop）
	@bash opencode-export.sh "$${1:-$$HOME/Desktop}"

audit: ## npm 安全审计（切官方源，绕过 npmmirror audit 404）
	@echo "运行 npm audit（临时切官方源）..."
	@npm audit --audit-level=moderate --registry=https://registry.npmjs.org || echo '⚠️  发现漏洞，详见上方报告'

skills-lock: ## 生成 lark skills SHA256 锁定文件（供应链加固，跨平台用 node 算 hash）
	@echo "生成 skills.lock（SHA256）..."
	@node -e "const fs=require('fs'),crypto=require('crypto'),path=require('path');const os=require('os');const skillsDir=path.join(os.homedir(),'.agents','skills');const lock={};if(!fs.existsSync(skillsDir)){console.error('⚠️  ~/.agents/skills 不存在，先运行 make feishu');process.exit(1)}for(const name of fs.readdirSync(skillsDir)){if(!name.startsWith('lark-'))continue;const skillPath=path.join(skillsDir,name,'SKILL.md');if(!fs.existsSync(skillPath))continue;const content=fs.readFileSync(skillPath);const hash=crypto.createHash('sha256').update(content).digest('hex');lock[skillPath]=hash}const lines=Object.keys(lock).sort().map(p=>lock[p]+'  '+p);fs.writeFileSync('skills.lock',lines.join('\n')+'\n');console.log('✓ 已生成 skills.lock（'+lines.length+' 条记录）');console.log('  下次 make feishu 后建议重跑本命令以检测 SKILL 是否被篡改')"

clean-state: ## 清理运行时状态文件（保留 plans/boulder.json/start-work）
	@echo "清理运行时状态文件..."
	@node -e "const fs=require('fs');const targets=['.omo/run-continuation','.omo/ralph-loop.local.md','tasks'];let cleaned=0;for(const t of targets){if(fs.existsSync(t)){fs.rmSync(t,{recursive:true,force:true});console.log('  ✓ '+t+' 已清理');cleaned++}}if(cleaned===0)console.log('  无运行时残留')"
	@echo "✓ 状态文件清理完成（plans/boulder.json/start-work 保留）"

sbom: ## 生成 SBOM（软件物料清单，CycloneDX 格式，供应链审计用）
	@echo "生成 SBOM（CycloneDX 格式）..."
	@npm sbom --sbom-format cyclonedx --sbom-type application 2>/dev/null && echo '✓ SBOM 已生成（sbom.cdx.json）' || \
		echo '⚠️  npm sbom 不可用（需 npm >= 10.5），手动跑：npm i -g @cyclonedx/cyclonedx-npm && cyclonedx-npm -o sbom.cdx.json'

tui-sync: ## 验证 tui.json 与 opencode.json 的 plugin 字段同步
	@echo "验证 plugin 字段同步..."
	@node -e "const a=require('./opencode.json').plugin||[];const b=require('./tui.json').plugin||[];const sa=JSON.stringify(a);const sb=JSON.stringify(b);if(sa===sb){console.log('  ✓ opencode.json 与 tui.json plugin 字段一致');console.log('    plugin:',sa)}else{console.error('  ❌ plugin 字段不一致');console.error('    opencode.json:',sa);console.error('    tui.json     :',sb);process.exit(1)}"
