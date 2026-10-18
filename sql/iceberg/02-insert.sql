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

INSERT INTO iceberg_rest.db_flink.orders VALUES
  (1, 10, 99.50, DATE '2026-10-01', 'high'),
  (2, 11, 12.30, DATE '2026-10-02', 'low'),
  (3, 12, 45.00, DATE '2026-10-03', 'medium');

SELECT * FROM iceberg_rest.db_flink.orders ORDER BY order_id;
