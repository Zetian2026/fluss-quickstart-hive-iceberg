-- ============================================================
-- Fluss table with lakehouse enabled. Data is tiered into the
-- Iceberg catalog served by the Hive Metastore REST API.
--
-- Re-runnable: dropping a Fluss table does NOT drop the mirrored
-- Iceberg table, so the Iceberg side is dropped explicitly first.
-- ============================================================
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

CREATE CATALOG iceberg_rest WITH (
  'type'                = 'iceberg',
  'catalog-type'        = 'rest',
  'uri'                 = 'http://hive-metastore:9001/iceberg',
  'warehouse'           = 's3://warehouse',
  'io-impl'             = 'org.apache.iceberg.aws.s3.S3FileIO',
  's3.endpoint'         = 'http://rustfs:9000',
  's3.access-key-id'    = 'rustfsadmin',
  's3.secret-access-key'= 'rustfsadmin',
  's3.path-style-access'= 'true',
  'client.region'       = 'us-east-1'
);

SET 'sql-client.execution.result-mode' = 'TABLEAU';

DROP TABLE IF EXISTS fluss_catalog.fluss.fluss_order_with_lake;
DROP TABLE IF EXISTS iceberg_rest.fluss.fluss_order_with_lake;

CREATE TABLE fluss_catalog.fluss.fluss_order_with_lake (
  order_key      BIGINT,
  cust_key       INT NOT NULL,
  total_price    DECIMAL(15, 2),
  order_date     DATE,
  order_priority STRING,
  clerk          STRING,
  PRIMARY KEY (order_key) NOT ENFORCED
) WITH (
  'table.datalake.enabled'   = 'true',
  'table.datalake.freshness' = '30s',
  'bucket.num'               = '4'
);

USE CATALOG fluss_catalog;
USE fluss;
SHOW TABLES;
DESCRIBE fluss_order_with_lake;
