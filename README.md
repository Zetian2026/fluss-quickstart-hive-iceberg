# fluss-quickstart-hive-iceberg
本仓库演示如何用 Fluss 1.0.0 构建流式湖仓：Fluss 负责实时写入与读取，后台把数据 tiering 到 Apache Iceberg，元数据统一由 Hive Metastore 4.1.0 内嵌的 Iceberg REST Catalog 管理，底层对象存储用 RustFS（S3 兼容）。
