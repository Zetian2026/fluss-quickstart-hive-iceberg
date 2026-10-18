-- ============================================================
-- Union Read on a LOG table (append-only).
-- Batch mode merges committed Iceberg data with the Fluss log tail.
--
-- Re-runnable: the Iceberg mirror table is dropped explicitly,
-- because dropping the Fluss table does not drop it.
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

CREATE DATABASE IF NOT EXISTS fluss_catalog.union_test;
CREATE DATABASE IF NOT EXISTS iceberg_rest.union_test;

DROP TABLE IF EXISTS fluss_catalog.union_test.log_table;
DROP TABLE IF EXISTS iceberg_rest.union_test.log_table;

CREATE TABLE fluss_catalog.union_test.log_table (
  id  BIGINT,
  msg STRING
) WITH (
  'bucket.num'             = '1',
  'table.datalake.enabled' = 'true'
);

SET 'execution.runtime-mode' = 'batch';
INSERT INTO fluss_catalog.union_test.log_table VALUES (1, 'a'), (2, 'b'), (3, 'c');

-- Union Read: committed Iceberg data + Fluss log tail
SELECT * FROM fluss_catalog.union_test.log_table ORDER BY id;
