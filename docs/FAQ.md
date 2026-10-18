# 常见问题

本文件记录搭建「Fluss + Iceberg REST Catalog on Hive Metastore」过程中实际遇到的问题、
根因与解决办法。所有结论都在本仓库的镜像版本上实测验证过。

环境版本：

| 组件 | 版本 |
|---|---|
| Hive Metastore | 4.1.0（`apache/hive:standalone-metastore-4.1.0`） |
| Iceberg（HMS 内 shaded） | 1.9.1 |
| Iceberg（Fluss / Flink 客户端） | 1.10.1 |
| Fluss | 1.0.0 |
| Flink | 1.20（`apache/fluss-quickstart-flink:1.20-1.0.0`） |
| RustFS | `rustfs/rustfs:latest`（v1.0.3） |
| PostgreSQL | 17 |

---

## 一、启动与配置

### Q1. Hive Metastore 报 `Warehouse location is not set: hive.metastore.warehouse.external.dir=null`

建 namespace 时返回 500。只配置 HMS 的 `metastore.warehouse.dir` 不够。

**原因**：HMS 内嵌的 Iceberg REST servlet 用的是 Iceberg `HiveCatalog`，
它直接读 **Hadoop 配置**里的 `hive.metastore.warehouse.dir` /
`hive.metastore.warehouse.external.dir`，完全不看 HMS 自己的 `metastore.warehouse.dir`。

**解决**：在 `conf/hive/core-site.xml` 里同时配置这两个 key：

```xml
<property>
  <name>hive.metastore.warehouse.dir</name>
  <value>s3://warehouse/</value>
</property>
<property>
  <name>hive.metastore.warehouse.external.dir</name>
  <value>s3://warehouse/</value>
</property>
```

### Q2. HMS 访问 S3 报 `ClassNotFoundException: S3AFileSystem` 或 `No FileSystem for scheme "s3"`

镜像里 `/opt/hadoop/share/hadoop/tools/lib/` **有** `hadoop-aws-3.4.1.jar` 和
AWS SDK v2 的 `bundle-2.24.6.jar`，但它们**不在默认 classpath 上**。

**解决**：显式设置 `HADOOP_CLASSPATH`：

```yaml
environment:
  - HADOOP_CLASSPATH=/opt/hadoop/share/hadoop/tools/lib/hadoop-aws-3.4.1.jar:/opt/hadoop/share/hadoop/tools/lib/bundle-2.24.6.jar
```

### Q3. 为什么配置里 `fs.s3.impl` 和 `fs.s3a.impl` 都要设成 S3A？

因为 warehouse 位置写的是 `s3://warehouse/...`。如果不覆盖 `fs.s3.impl`，
Hadoop 会去加载已废弃的 `s3://`（NativeS3FileSystem）实现，而镜像里并没有它，
表现为 `No FileSystem for scheme "s3"`。把两者都指向 S3A 后，
`s3://` 和 `s3a://` 统一走 S3A：

```xml
<property><name>fs.s3.impl</name><value>org.apache.hadoop.fs.s3a.S3AFileSystem</value></property>
<property><name>fs.s3a.impl</name><value>org.apache.hadoop.fs.s3a.S3AFileSystem</value></property>
```

### Q4. 报 `Unable to load region from any of the providers` / S3A 卡住在 IMDS

hadoop-aws 3.4.x 对非 AWS endpoint 会尝试通过 IMDS 或 STS 解析 region，
在本地容器里必然失败。

**解决**：显式指定 region：

```xml
<property>
  <name>fs.s3a.endpoint.region</name>
  <value>us-east-1</value>
</property>
```

### Q5. RustFS 需要哪些额外配置？

RustFS 是 S3 兼容但非 AWS 实现，需要 path-style 访问和关闭 SSL：

```xml
<property><name>fs.s3a.endpoint</name><value>http://rustfs:9000</value></property>
<property><name>fs.s3a.path.style.access</name><value>true</value></property>
<property><name>fs.s3a.connection.ssl.enabled</name><value>false</value></property>
<property>
  <name>fs.s3a.aws.credentials.provider</name>
  <value>org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider</value>
</property>
```

另外建议 `fs.s3a.fast.upload.buffer=bytebuffer`，避免依赖本地磁盘临时目录。

### Q6. 端口 9001 冲突

RustFS 控制台默认也用 9001，和 Iceberg REST Catalog 撞了。
本仓库把 RustFS 控制台映射到宿主机 **9002**，9001 留给 REST Catalog。

---

## 二、REST Catalog 访问

### Q7. `POST /iceberg/v1/hive/namespaces` 返回 400 `No route for request`

REST 路径里**没有 warehouse 前缀**。不管 `warehouse` 配的是什么，
endpoint 都是：

```
http://hive-metastore:9001/iceberg/v1/...
```

正确/错误对照：

```bash
# 正确
curl http://localhost:9001/iceberg/v1/namespaces

# 错误 → 400 No route for request
curl http://localhost:9001/iceberg/v1/hive/namespaces
```

### Q8. 客户端 `uri` 应该填到哪一层？

填到 `/iceberg`，**不要**带 `/v1`：

```sql
'uri' = 'http://hive-metastore:9001/iceberg'
```

### Q9. 本地开发怎么关掉 REST Catalog 的鉴权？

```xml
<property>
  <name>metastore.catalog.servlet.auth</name>
  <value>none</value>
</property>
```

同时通过 `metastore.catalog.servlet.port` 和
`metastore.iceberg.catalog.servlet.path` 指定端口与路径。

> 生产环境不要用 `none`，应配置 Kerberos 或 OAuth。

### Q10. 客户端还需要 Hive 依赖吗？

不需要。`catalog-type=rest` 时 Flink 只依赖 `iceberg-flink-runtime` 里的
REST 客户端 + `S3FileIO`，不需要 `HiveCatalog`，也不需要连 9083。
9083 之所以还暴露，只是为了 `schematool` 和排障。

---

## 三、Fluss 集成

### Q11. Fluss 报 `No LakeStoragePlugin can be found for datalake format: iceberg`

缺少 `fluss-lake-iceberg` 插件。`apache/fluss:1.0.0` 镜像已经内置该 jar，
但 `S3FileIO` 还需要 AWS 依赖，必须把 `iceberg-aws-*.jar` 挂到插件目录：

```yaml
volumes:
  - ./lib/iceberg-aws-1.10.1.jar:/opt/fluss/plugins/iceberg/iceberg-aws-1.10.1.jar:ro
  - ./lib/iceberg-aws-bundle-1.10.1.jar:/opt/fluss/plugins/iceberg/iceberg-aws-bundle-1.10.1.jar:ro
```

### Q12. Fluss 日志里 `Hadoop not found on classpath` 是错误吗？

不是。使用 `datalake.iceberg.type=rest` + `io-impl=S3FileIO` 时不会走 Hadoop，
这条 warning 可以忽略。

### Q13. Fluss 的 Iceberg 配置项前缀是什么？

Fluss **服务端**用 `datalake.iceberg.*`：

```
datalake.iceberg.type          rest
datalake.iceberg.uri           http://hive-metastore:9001/iceberg
datalake.iceberg.warehouse     s3://warehouse
datalake.iceberg.io-impl       org.apache.iceberg.aws.s3.S3FileIO
datalake.iceberg.s3.endpoint   http://rustfs:9000
datalake.iceberg.client.region us-east-1
```

Fluss 的 **Flink connector** 在 `CREATE CATALOG` 上用 `iceberg.` 前缀（见 Q15）。

### Q14. tiering 作业报 `The bootstrap server to fluss is not configured`

启动 `FlussLakeTieringEntrypoint` 时必须显式给 Fluss 地址：

```bash
--fluss.bootstrap.servers coordinator-server:9123
```

### Q15. Union Read 报 `SdkClientException: Unable to load credentials`

**原因**：Union Read 走 `LakeFlinkCatalog`，它从 **Fluss catalog 的选项**里
按 `<format>.` 前缀提取 Iceberg 客户端配置（catalog 属性优先级高于表属性）。
只给 `bootstrap.servers` 时，Iceberg 客户端拿不到 S3 凭据。

**解决**：在 `CREATE CATALOG fluss_catalog` 上补齐 `iceberg.` 前缀配置：

```sql
CREATE CATALOG fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'coordinator-server:9123',
  'iceberg.catalog-type' = 'rest',
  'iceberg.uri' = 'http://hive-metastore:9001/iceberg',
  'iceberg.warehouse' = 's3://warehouse',
  'iceberg.io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
  'iceberg.s3.endpoint' = 'http://rustfs:9000',
  'iceberg.s3.access-key-id' = 'rustfsadmin',
  'iceberg.s3.secret-access-key' = 'rustfsadmin',
  'iceberg.s3.path-style-access' = 'true',
  'iceberg.client.region' = 'us-east-1'
);
```

（注意这里的前缀是 `iceberg.`，不是 `datalake.iceberg.`。）

### Q16. 主键表批模式 Union Read 报 `lake records must instance of sorted view`

**这是 Fluss 1.0.0 的已知限制，不是配置问题。**

`LakeSnapshotAndLogSplitScanner`（`fluss-client`）要求 lake source 返回
`SortedRecordReader`，否则抛：

```java
throw new UnsupportedOperationException(
        "lake records must instance of sorted view.");
```

而 1.0.0 的 `IcebergRecordReader` 只实现了 `RecordReader`（`PaimonSortedRecordReader`、
`HudiSortedRecordReader` 已实现 sorted 变体，Iceberg 没有）。

**影响范围**：

| 场景 | 是否可用 |
|---|---|
| 日志表 + 批模式 Union Read | 可用 |
| 主键表 + 流模式 Union Read | 可用 |
| 主键表 + 批模式 Union Read | **不可用** |
| `$lake` 只读湖（批） | 可用 |
| 通过 REST Catalog 直接读 Iceberg | 可用 |

**规避方式**：

- 主键表改用流模式 Union Read；
- 只需要历史数据时用 `$lake` 后缀，或直接走 Iceberg REST Catalog。

### Q17. `DROP TABLE` 之后重建同名表报 `LakeTableAlreadyExistException`

**原因**：Fluss 的 `DROP TABLE` 只删 Fluss 侧的表，**不会删除 Iceberg 里的镜像表**。
镜像表里已有数据，所以重建会被拒绝：

```
The table fluss.fluss_order_with_lake already exists in Iceberg catalog,
and the table is not empty.
```

**解决**：先删 Iceberg 侧的表，再重建。仓库的建表脚本已经内置这一步，可重复执行：

```sql
DROP TABLE IF EXISTS fluss_catalog.fluss.fluss_order_with_lake;
DROP TABLE IF EXISTS iceberg_rest.fluss.fluss_order_with_lake;

CREATE TABLE fluss_catalog.fluss.fluss_order_with_lake (...) WITH (...);
```

### Q18. Fluss 表建在哪个 database？

镜像表的位置由表所在的 Fluss database 决定。`fluss.fluss_order_with_lake`
对应 Iceberg 中的 `fluss.db/fluss_order_with_lake`。用非 `fluss` 的 database 时，
Iceberg 侧也会跟着变。

---

## 四、Flink / SQL Client

### Q19. `sql-client.sh -f` 报 `FileNotFoundException ... (Permission denied)`

宿主机上创建的 `.sql` 文件默认权限可能是 `600`，容器内以其他用户运行就读不到。

**解决**：

```bash
chmod 644 sql/**/*.sql
```

在 compose 里以 `:ro` 挂载目录也更安全。

### Q20. 非交互执行查询看不到结果

需要显式设置结果模式：

```sql
SET 'sql-client.execution.result-mode' = 'TABLEAU';
```

仓库所有脚本都已包含这一行。

### Q21. 用 `docker run` 临时起容器时报 `Connection refused`

必须走镜像的入口脚本并指定 `rest.address`，否则 sql-client 找不到集群：

```bash
docker run --rm --network fluss-quickstart-iceberg_default \
  -v "$PWD/sql":/opt/sql:ro \
  -e FLINK_PROPERTIES=$'jobmanager.rpc.address: jobmanager\nrest.address: jobmanager' \
  apache/fluss-quickstart-flink:1.20-1.0.0 \
  /opt/flink/init_iceberg.sh /opt/flink/bin/sql-client.sh -f /opt/sql/iceberg/03-select.sql
```

注意 `entrypoint` 必须是 `/opt/flink/init_iceberg.sh`——它负责把 Iceberg jar 拷进
`/opt/flink/lib/`，直接覆盖 entrypoint 会导致 Iceberg 依赖缺失。

### Q22. `CREATE CATALOG` 成功但 `SHOW DATABASES` 里没有新建的库

`USE CATALOG` 之后再建表/建库。脚本里用全限定名（`iceberg_rest.db_flink.orders`）
也可以，但 `SHOW TABLES` 依赖当前 catalog 和 database：

```sql
USE CATALOG iceberg_rest;
USE db_flink;
SHOW TABLES;
```

---

## 五、验证与排查

### Q23. 怎么确认元数据真的写进了 PostgreSQL？

```bash
docker compose exec postgres psql -U hive -d metastore -c \
  'SELECT "NAME", "DB_LOCATION_URI" FROM "DBS";'
```

注意 HMS 建的表名是**大写并带引号**的（`"DBS"`、`"TBLS"`、`"SDS"`），
小写会提示表不存在。

### Q24. 怎么确认数据文件真的写进了 RustFS？

```bash
docker compose run --rm --entrypoint sh rustfs-init -c \
  'rc alias set r http://rustfs:9000 rustfsadmin rustfsadmin >/dev/null; rc find r/warehouse'
```

或者从宿主机直接查 REST Catalog：

```bash
curl -s http://localhost:9001/iceberg/v1/namespaces/fluss/tables
```

### Q25. tiering 作业状态去哪看？

```bash
curl -s http://localhost:8083/jobs/overview
```

或打开 Flink Web UI：<http://localhost:8083>，找 `Fluss Lake Tiering Service - iceberg`。

### Q26. 数据写入后湖里读不到

按顺序排查：

1. tiering 作业是否 `RUNNING`（Q25）；
2. 是否等够一个 `table.datalake.freshness` 周期（默认脚本里是 `30s`，建议 `sleep 60`）；
3. 该表是否 `table.datalake.enabled = 'true'`（`DESCRIBE` 看不到，需要看建表语句）；
4. RustFS 里该表目录下是否有新的 parquet 文件（Q24）。

---

## 六、其他

### Q27. 为什么客户端 Iceberg 是 1.10.1，HMS 里是 1.9.1？

HMS 4.1.0 镜像把 Iceberg 1.9.1 shaded 进了 `hive-iceberg-handler-4.1.0.jar`，
无法替换。客户端（Flink、Fluss）用 1.10.1，通过 REST 协议交互，
只要都遵循 Iceberg REST 规范即可共存——本仓库的读写链路已实测通过。

### Q28. 可以换成 AWS S3 或 MinIO 吗？

可以。把 `s3.endpoint` / `fs.s3a.endpoint` 换成对应地址，
并按需调整 `path-style-access` 和凭据配置即可，其余配置不变。

### Q29. 这个栈能在生产用吗？

不能直接用于生产。至少需要处理：

- REST Catalog 鉴权（本仓库为 `none`）；
- PostgreSQL 高可用与备份；
- Hive Metastore 多实例与 Thrift/REST 的负载均衡；
- RustFS 换成生产级对象存储；
- 凭据改用 IAM / Vault，而不是明文写在 compose 里。
