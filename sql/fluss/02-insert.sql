-- Insert rows into the Fluss table; the tiering service moves them to Iceberg.
CREATE CATALOG fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'coordinator-server:9123'
);

USE CATALOG fluss_catalog;

SET 'execution.runtime-mode' = 'batch';

INSERT INTO fluss_order_with_lake VALUES
  (1001, 10, 99.50, DATE '2026-10-01', 'high',   'Clerk1'),
  (1002, 11, 12.30, DATE '2026-10-02', 'low',    'Clerk2'),
  (1003, 12, 45.00, DATE '2026-10-03', 'medium', 'Clerk3');
