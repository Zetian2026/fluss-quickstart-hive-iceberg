# Fluss + Iceberg 湖仓快速上手（Hive Metastore REST Catalog）

本仓库演示如何用 **Fluss 1.0.0** 构建流式湖仓：Fluss 负责实时写入与读取，后台把数据
tiering 到 **Apache Iceberg**，元数据统一由 **Hive Metastore 4.1.0** 内嵌的
**Iceberg REST Catalog** 管理，底层对象存储用 **RustFS**（S3 兼容）。

与官方 lakehouse quickstart 的差别在**元数据访问路径**：

> 客户端（Flink、Fluss）只通过 **Iceberg REST Catalog API** 访问 Iceberg，
> 不使用 Hive Thrift 协议，客户端也不需要 HiveCatalog 依赖。

```
                    ┌──────────────────────────────┐
   Flink SQL ────>  │ Iceberg REST Catalog (:9001) │  /iceberg/v1/...
   (Flink 1.20)     │  Hive Metastore 4.1.0        │
                    │   └─ Iceberg 1.9.1 (shaded)  │
                    └───────────┬──────────────────┘
                                │ JDBC
                    ┌───────────▼──────────┐
                    │ PostgreSQL 17        │
                    └──────────────────────┘
                                │ S3A FileIO
                    ┌───────────▼──────────┐
                    │ RustFS (S3 API :9000)│  s3://warehouse, s3://fluss
                    └───────────▲──────────┘
                                │ tiering
   Fluss 1.0.0 ─────────────────┘
   coordinator + tablet（datalake.enabled = true）
```

| 组件 | 镜像 | 端口 |
|---|---|---|
| RustFS | `rustfs/rustfs:latest` | 9000 (S3)、9002 (控制台) |
| PostgreSQL | `postgres:17` | 仅容器网络内 |
| Hive Metastore + REST Catalog | `apache/hive:standalone-metastore-4.1.0` | 9001 (REST)、9083 (Thrift，仅供调试) |
| Fluss | `apache/fluss:1.0.0` | 容器网络内 9123 |
| Flink | `apache/fluss-quickstart-flink:1.20-1.0.0` | 8083 (Web UI) |

---

## 环境准备

### 前置条件

- Docker 与 Docker Compose v2
- 已拉取下列镜像：

```bash
docker pull rustfs/rustfs:latest
docker pull rustfs/rc:v0.1.36
docker pull postgres:17
docker pull zookeeper:3.9.2
docker pull apache/hive:standalone-metastore-4.1.0
docker pull apache/fluss:1.0.0
docker pull apache/fluss-quickstart-flink:1.20-1.0.0
```

- 空闲端口：`9000`、`9001`、`9002`、`9083`、`8083`

### 下载运行时依赖

仓库不包含 jar 文件。执行脚本下载到 `lib/`（该目录已在 `.gitignore` 中忽略）：

```bash
./download-deps.sh
```

脚本从 Maven 中央仓库拉取下面三个 jar，已存在则跳过：

| 文件 | 用途 |
|---|---|
| `postgresql-42.7.4.jar` | Hive Metastore 的 JDBC 驱动 |
| `iceberg-aws-1.10.1.jar` | Fluss 的 `S3FileIO` 依赖 |
| `iceberg-aws-bundle-1.10.1.jar` | Fluss 的 AWS SDK 打包依赖 |

如需走镜像站：

```bash
MAVEN_MIRROR=https://maven.aliyun.com/repository/public ./download-deps.sh
```

等价的手工下载命令：

```bash
mkdir -p lib
curl -fL -o lib/postgresql-42.7.4.jar \
  https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar
curl -fL -o lib/iceberg-aws-1.10.1.jar \
  https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws/1.10.1/iceberg-aws-1.10.1.jar
curl -fL -o lib/iceberg-aws-bundle-1.10.1.jar \
  https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/1.10.1/iceberg-aws-bundle-1.10.1.jar
```

### 启动组件

```bash
docker compose up -d
docker compose ps
```

`rustfs-init`（建 bucket）和 `tiering`（提交 tiering 作业）是一次性容器，
状态为 `Exited (0)` 即正常。

等 `hive-metastore` 变成 `healthy` 后，可以直接从宿主机验证 REST Catalog：

```bash
curl http://localhost:9001/iceberg/v1/config
curl http://localhost:9001/iceberg/v1/namespaces
```

第一条返回 `{"defaults":{},"overrides":{}}`，第二条返回 namespace 列表。

---

## 进入 SQL Client

所有操作都在容器内的 Flink SQL Client 中完成：

```bash
docker compose exec sql-client /opt/flink/bin/sql-client.sh
```

仓库的 `sql/` 目录挂载在容器内 `/opt/sql`，可以直接执行脚本：

```bash
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/iceberg/01-create.sql
```

---

## 通过 Iceberg REST Catalog 直接读写

先验证「Flink → REST Catalog → RustFS」这条链路，这一步不涉及 Fluss。

```bash
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/iceberg/01-create.sql
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/iceberg/02-insert.sql
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/iceberg/03-select.sql
```

关键配置（`sql/iceberg/01-create.sql`）：

```sql
CREATE CATALOG iceberg_rest WITH (
  'type'                = 'iceberg',
  'catalog-type'        = 'rest',                               -- 关键：走 REST，不是 hive
  'uri'                 = 'http://hive-metastore:9001/iceberg',  -- REST endpoint
  'warehouse'           = 's3://warehouse',
  'io-impl'             = 'org.apache.iceberg.aws.s3.S3FileIO',
  's3.endpoint'         = 'http://rustfs:9000',
  's3.access-key-id'    = 'rustfsadmin',
  's3.secret-access-key'= 'rustfsadmin',
  's3.path-style-access'= 'true',
  'client.region'       = 'us-east-1'
);
```

`03-select.sql` 应返回 3 行（`order_id` 1/2/3）。此时元数据已写入 PostgreSQL，
数据文件落在 RustFS 的 `s3://warehouse/db_flink.db/orders/`。

---

## 创建 Fluss 表

### 创建 Catalog

```sql
CREATE CATALOG fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'coordinator-server:9123'
);

USE CATALOG fluss_catalog;
```

### 创建开启湖仓的表

```bash
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/fluss/01-create-table.sql
```

核心表属性：

```sql
CREATE TABLE fluss_catalog.fluss.fluss_order_with_lake (
  order_key      BIGINT,
  cust_key       INT NOT NULL,
  total_price    DECIMAL(15, 2),
  order_date     DATE,
  order_priority STRING,
  clerk          STRING,
  PRIMARY KEY (order_key) NOT ENFORCED
) WITH (
  'table.datalake.enabled'   = 'true',   -- 开启湖仓
  'table.datalake.freshness' = '30s',    -- tiering 频率
  'bucket.num'               = '4'
);
```

`table.datalake.enabled = 'true'` 会让 Fluss 在 Iceberg REST Catalog 中同时创建一张
镜像表（`fluss.fluss_order_with_lake`）。

---

## 写入数据

```bash
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/fluss/02-insert.sql
```

写入 3 条订单记录。此时数据在 Fluss 中已可读，但还没进 Iceberg。

---

## 湖仓集成

### 启动 Tiering 服务

`docker-compose.yml` 里的 `tiering` 服务会在 `jobmanager` 就绪后自动提交作业，
无需手工操作。确认作业在运行：

```bash
curl -s http://localhost:8083/jobs/overview | grep -o '"name":"Fluss Lake Tiering[^"]*"'
```

或者在 Flink Web UI（<http://localhost:8083>）中查看 `Fluss Lake Tiering Service - iceberg`。

作业参数与 Fluss 服务端配置一致，都指向 REST Catalog：

```
--datalake.iceberg.type      rest
--datalake.iceberg.uri       http://hive-metastore:9001/iceberg
--datalake.iceberg.warehouse s3://warehouse
```

### 验证数据已进入 Iceberg

等待一个 tiering 周期（`table.datalake.freshness = 30s`，脚本里 `sleep 60` 足够），
然后用 Flink 通过 REST Catalog 直接读 Iceberg：

```bash
sleep 60
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/lake/01-read-via-rest.sql
```

返回 3 行即为 tiering 成功。也可以直接从对象存储确认 parquet 文件：

```bash
docker compose run --rm --entrypoint sh rustfs-init -c \
  'rc alias set r http://rustfs:9000 rustfsadmin rustfsadmin >/dev/null; rc find r/warehouse'
```

### 写入数据并实时分析（Union Read）

Fluss 提供 Union Read：自动合并「已 tiering 的湖数据」和「Fluss 中的实时数据」，
并按主键去重。

日志表（append-only）在批模式下可用：

```bash
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/fluss/03-union-read-log-table.sql
```

主键表在**流模式**下可用（会持续输出，`Ctrl-C` 结束）：

```bash
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/fluss/04-union-read-streaming.sql
```

> 主键表的**批模式** Union Read 在 Fluss 1.0.0 中不可用，原因见 [docs/FAQ.md](docs/FAQ.md)。

### 只读湖数据

用 `$lake` 后缀可以跳过 Fluss，只读 Iceberg 中的历史数据：

```bash
docker compose exec sql-client /opt/flink/bin/sql-client.sh -f /opt/sql/lake/02-lake-only-read.sql
```

```sql
SELECT * FROM fluss_order_with_lake$lake ORDER BY order_key;
```

### 退出 SQL Client

```sql
QUIT;
```

---

## 清理

```bash
# 停止容器，保留 RustFS 数据卷
docker compose down

# 停止并删除数据卷（元数据与对象全部清空）
docker compose down -v
```

---

## 目录结构

```
.
├── docker-compose.yml            # 完整栈：RustFS / PostgreSQL / HMS / Fluss / Flink
├── download-deps.sh              # 下载运行时 jar 到 lib/
├── conf/hive/
│   ├── core-site.xml             # S3A 文件系统、warehouse 位置、RustFS 端点
│   └── metastore-site.xml        # PostgreSQL 后端、REST Catalog servlet
├── sql/
│   ├── iceberg/                  # 通过 REST Catalog 建表 / 写入 / 读取
│   ├── fluss/                    # Fluss 建表 / 写入 / Union Read
│   └── lake/                     # 通过 REST 读湖 / $lake 只读湖
└── docs/
    └── FAQ.md                    # 常见问题与配置说明
```

`lib/` 由 `download-deps.sh` 生成，不纳入版本管理。
