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
SET 'execution.runtime-mode' = 'batch';
SET 'sql-client.execution.result-mode' = 'TABLEAU';
USE CATALOG fluss_catalog;
SELECT * FROM fluss_order_with_lake$lake ORDER BY order_key;
