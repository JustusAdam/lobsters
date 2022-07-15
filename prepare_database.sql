CREATE USER dev_username IDENTIFIED BY 'dev_password';
CREATE DATABASE lobsters_dev;
GRANT ALL ON lobsters_dev.* TO dev_username;
CREATE USER test_username IDENTIFIED BY 'test_password';
CREATE DATABASE lobsters_test;
GRANT ALL ON lobsters_test.* TO test_username;
CREATE USER lobsters IDENTIFIED BY 'lobsters';
CREATE DATABASE lobsters;
GRANT ALL ON lobsters.* TO lobsters;

SET GLOBAL max_heap_table_size = 1024 * 1024 * 512;
