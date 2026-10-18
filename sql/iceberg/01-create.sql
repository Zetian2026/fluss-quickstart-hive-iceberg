-- ============================================================
-- Stage 2: Flink talks to Iceberg exclusively through the
--          Iceberg REST Catalog API served by Hive Metastore.
--          (No Hive Thrift, no HiveCatalog on the client side.)
-- ============================================================
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

SET 'execution.runtime-mode' = 'batch';
SET 'sql-client.execution.result-mode' = 'TABLEAU';

USE CATALOG iceberg_rest;

CREATE DATABASE IF NOT EXISTS db_flink;

CREATE TABLE IF NOT EXISTS db_flink.orders (
  order_id       BIGINT,
  cust_key       INT,
  total_price    DECIMAL(15, 2),
  order_date     DATE,
  order_priority STRING
);

SHOW DATABASES;

USE db_flink;
SHOW TABLES;
DESCRIBE orders;
