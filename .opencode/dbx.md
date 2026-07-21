# DBX 数据库连接字典

DBX MCP 提供数据库查询能力。当前连接按 `{项目}-{环境}` 命名分组：

| 连接名 | 环境 | Type | Host | 默认库 | 用途 |
| --- | --- | --- | --- | --- | --- |
| `hooloo-prod` | **生产** | mysql | rm-2zes5639eb0ia4luv...aliyuncs.com | 留空（多库） | hooloo 业务主库，含 `hooloo_saas` / `hooloo_brain` / `shop_deployment_auth` 等 |
| `hooloo-prod` | **生产** | redis | r-2zeegqcuk2jaf8m0l3...aliyuncs.com | — | hooloo 生产缓存 |
| `hooloo-test` | 测试 | mysql | 127.0.0.1 | `brain` | 本地开发库，与线上 schema 同步但数据不同步 |
| `dts-prod` | **生产** | mysql | rm-2zej6bf3i84u2dm2g6o...aliyuncs.com | 留空 | 阿里云 DTS 数据传输专用 |

## 关键库 / 表索引

**`hooloo_saas`**（线上主业务库）：
- `shop` — 店铺主表（303 家，字段含 `name`/`code`/`province`/`city`/`zone`/`state`(1正常/2暂停/3关闭)/`shop_type`(0普通/2太空舱)）
- `goods` / `goods_sku` / `goods_category` — 商品体系
- `order` / `order_detail` / `order_refund` — 订单体系
- `customer` / `user` — 用户体系
- `coupon` / `coupon_user` — 优惠券
- `warehouse` / `warehouse_shop` — 仓储 + 门店关联
- `machine` — 机器（与本地 brain 库 schema 部分重叠）

**`hooloo_brain`**（机器人大脑控制库）：机器控制 / 设备指令 / 组件属性 / ROS 配置

**`brain`**（本地测试库）：与线上 `hooloo_brain` schema 相似，用于本地开发联调

**`shop_deployment_auth`**（线上）：店铺部署授权，敏感库

## 安全护栏（硬约束）

1. **生产连接默认只读**：`hooloo-prod` / `dts-prod` 仅允许 `SELECT` / `SHOW` / `DESC`。
2. **生产写操作需显式批准**：任何 `INSERT` / `UPDATE` / `DELETE` / `DROP` / `ALTER` / `TRUNCATE` 指向生产连接时，**必须先展示 SQL + 影响范围预估，等待用户明确批准**后再执行。
3. **测试连接自由读写**：`hooloo-test` 可直接 DDL/DML，无需确认（本地库可重建）。
4. **redis 谨慎操作**：`hooloo-prod` redis 连接禁止 `FLUSHDB` / `FLUSHALL` / 大批量 `KEYS *`（用 `SCAN` 替代）；任何删除 key 操作需先列 key 类型/TTL 再确认。
5. **跨环境不动数据**：禁止从 `hooloo-prod` 导出数据写入 `hooloo-test`，反之亦然，除非用户明确要求。
6. **大查询限量**：生产 `SELECT` 应优先加 `LIMIT`；无 `LIMIT` 的全表扫需先估算行数 (`SHOW TABLE STATUS LIKE`)。

## 默认查询路径

- 用户问「线上店铺 / 商品 / 订单」→ `hooloo-prod` + `hooloo_saas`
- 用户问「本地测试数据」→ `hooloo-test` + `brain`
- 用户问「机器/设备」→ 先 `hooloo-prod.hooloo_brain`（线上控制）；本地联调走 `hooloo-test.brain`
- 用户未指明环境时，默认走 `hooloo-prod`，并在结果末尾标注「⚠️ 生产数据」
