CREATE CATALOG iceberg_rest WITH (
  'type' = 'iceberg',
  'catalog-type' = 'rest',
  'uri' = 'http://hive-metastore:9001/iceberg',
  'warehouse' = 's3://warehouse',
  'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
  's3.endpoint' = 'http://rustfs:9000',
  's3.access-key-id' = 'rustfsadmin',
  's3.secret-access-key' = 'rustfsadmin',
  's3.path-style-access' = 'true',
  'client.region' = 'us-east-1'
);
SET 'execution.runtime-mode' = 'batch';
SET 'sql-client.execution.result-mode' = 'TABLEAU';
USE CATALOG iceberg_rest;
SHOW DATABASES;
SELECT * FROM fluss.fluss_order_with_lake ORDER BY order_key;
