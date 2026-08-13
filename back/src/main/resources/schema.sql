-- pgj 이미지에 포함된 확장들. Hibernate가 DDL을 만들기 전에 켜져 있어야 한다
-- (geography/vector 같은 타입을 컬럼 정의에서 쓰기 때문)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgroonga;
CREATE EXTENSION IF NOT EXISTS vector;
