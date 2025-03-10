-- pg database size

SELECT pg_database.datname Database_Name , pg_size_pretty(pg_database_size(pg_database.datname)) AS Database_Size FROM pg_database;


-- oldest xid
SELECT max(age(datfrozenxid)) oldest_xid FROM pg_database;

WITH max_age AS ( SELECT 2^31-3000000 as max_old_xid , setting AS 
autovacuum_freeze_max_age FROM pg_catalog.pg_settings 
WHERE name = 'autovacuum_freeze_max_age' ) , 
per_database_stats AS ( SELECT datname , m.max_old_xid::int , 
m.autovacuum_freeze_max_age::int , age(d.datfrozenxid) AS oldest_current_xid 
FROM pg_catalog.pg_database d JOIN max_age m ON (true) WHERE d.datallowconn ) 
SELECT max(oldest_current_xid) AS oldest_current_xid , 
max(ROUND(100*(oldest_current_xid/max_old_xid::float))) AS percent_towards_wraparound
 , max(ROUND(100*(oldest_current_xid/autovacuum_freeze_max_age::float))) AS percent_towards_emergency_autovac 
 FROM per_database_stats ;

-- current autovacuum process
SELECT datname,usename,state,query,
now() - pg_stat_activity.query_start AS duration, 
wait_event from pg_stat_activity where query ~ '^autovacuum:' order by 5;


SELECT datname,usename,state,query,
now() - pg_stat_activity.query_start AS duration,
 wait_event from pg_stat_activity where query ~* '\A\s*vacuum\M' order by 5


 -- vacuum progress

SELECT p.pid, now() - a.xact_start AS duration, coalesce(wait_event_type ||'.'|| wait_event, 'f') AS waiting, 
  CASE WHEN a.query ~ '^autovacuum.*to prevent wraparound' THEN 'wraparound' WHEN a.query ~ '^vacuum' THEN 'user' ELSE 'regular' END AS mode, 
  p.datname AS database, p.relid::regclass AS table, p.phase, a.query ,
  pg_size_pretty(p.heap_blks_total * current_setting('block_size')::int) AS table_size, 
  pg_size_pretty(pg_total_relation_size(p.relid)) AS total_size, 
  pg_size_pretty(p.heap_blks_scanned * current_setting('block_size')::int) AS scanned, 
  pg_size_pretty(p.heap_blks_vacuumed * current_setting('block_size')::int) AS vacuumed, 
  round(100.0 * p.heap_blks_scanned / p.heap_blks_total, 1) AS scanned_pct, 
  round(100.0 * p.heap_blks_vacuumed / p.heap_blks_total, 1) AS vacuumed_pct, 
  p.index_vacuum_count,
  p.max_dead_tuples as max_dead_tuples_per_cycle,
  s.n_dead_tup as total_num_dead_tuples ,
  ceil(s.n_dead_tup::float/p.max_dead_tuples::float) index_cycles_required
FROM pg_stat_progress_vacuum p JOIN pg_stat_activity a using (pid) 
     join pg_stat_all_tables s on s.relid = p.relid
ORDER BY now() - a.xact_start DESC;

-- active replication slot

select *,age(xmin) age_xmin,age(catalog_xmin) age_catalog_xmin 
from pg_replication_slots 
where active = true 
order by age(xmin) desc;

-- invalid database count
select count(*) FROM pg_database WHERE datconnlimit = '-2' ;

-- orphaned prepared transactions
SELECT gid, prepared, owner, database, age(transaction) AS ag_xmin 
FROM pg_prepared_xacts
ORDER BY age(transaction) DESC;

-- autovacuum and maintenance parameters
SELECT name,setting,source,sourcefile from pg_settings where name like '%vacuum%' order by 1;
SELECT name,setting,source,sourcefile from pg_settings where name ='maintenance_work_mem';

-- which tables are currently eligible for auto-vacuum

WITH vbt AS (SELECT setting AS autovacuum_vacuum_threshold FROM pg_settings WHERE name = 'autovacuum_vacuum_threshold')
    , vsf AS (SELECT setting AS autovacuum_vacuum_scale_factor FROM pg_settings WHERE name = 'autovacuum_vacuum_scale_factor')
    , fma AS (SELECT setting AS autovacuum_freeze_max_age FROM pg_settings WHERE name = 'autovacuum_freeze_max_age')
    , sto AS (select opt_oid, split_part(setting, '=', 1) as param, split_part(setting, '=', 2) as value from (select oid opt_oid, unnest(reloptions) setting from pg_class) opt)
SELECT
    '"'||ns.nspname||'"."'||c.relname||'"' as relation
    , pg_size_pretty(pg_table_size(c.oid)) as table_size
    , age(relfrozenxid) as xid_age
    , coalesce(cfma.value::float, autovacuum_freeze_max_age::float) autovacuum_freeze_max_age
    , (coalesce(cvbt.value::float, autovacuum_vacuum_threshold::float) + coalesce(cvsf.value::float,autovacuum_vacuum_scale_factor::float) * c.reltuples) as autovacuum_vacuum_tuples
    , n_dead_tup as dead_tuples
FROM pg_class c join pg_namespace ns on ns.oid = c.relnamespace
join pg_stat_all_tables stat on stat.relid = c.oid
join vbt on (1=1) join vsf on (1=1) join fma on (1=1)
left join sto cvbt on cvbt.param = 'autovacuum_vacuum_threshold' and c.oid = cvbt.opt_oid
left join sto cvsf on cvsf.param = 'autovacuum_vacuum_scale_factor' and c.oid = cvsf.opt_oid
left join sto cfma on cfma.param = 'autovacuum_freeze_max_age' and c.oid = cfma.opt_oid
WHERE c.relkind = 'r' and nspname <> 'pg_catalog'
and (
    age(relfrozenxid) >= coalesce(cfma.value::float, autovacuum_freeze_max_age::float)
    or
    coalesce(cvbt.value::float, autovacuum_vacuum_threshold::float) + coalesce(cvsf.value::float,autovacuum_vacuum_scale_factor::float) * c.reltuples <= n_dead_tup
   -- or 1 = 1
)
ORDER BY age(relfrozenxid) DESC ;

-- auto-vacuum progress per day
select to_char(last_autovacuum, 'YYYY-MM-DD') as date , count(*) as table_count from pg_stat_all_tables   group by to_char(last_autovacuum, 'YYYY-MM-DD') order by 1;


--The most recent 20 tables that have been vacuumed by the autovacuum
select schemaname as schema_name,relname as table_name,n_live_tup, n_tup_upd, n_tup_del, n_dead_tup, 
last_vacuum, last_autovacuum, last_analyze, last_autoanalyze 
from pg_stat_all_tables 
order by last_autovacuum desc limit 20 ;

--Top-20 tables order by xid age:
SELECT c.oid::regclass as relation_name,     
        greatest(age(c.relfrozenxid),age(t.relfrozenxid)) as age,
        pg_size_pretty(pg_table_size(c.oid)) as table_size,
        c.relkind
FROM pg_class c
LEFT JOIN pg_class t ON c.reltoastrelid = t.oid
WHERE c.relkind in ('r', 't','m')
order by 2 desc limit 20;

-- index information of top tables by xid age
SELECT schemaname,relname AS tablename,
indexrelname AS indexname,
idx_scan ,
pg_relation_size(indexrelid) as index_size,
pg_size_pretty(pg_relation_size(indexrelid)) AS pretty_index_size
FROM pg_catalog.pg_stat_all_indexes
WHERE  relname in (select relation_name::text from (SELECT c.oid::regclass as relation_name,     
        greatest(age(c.relfrozenxid),age(t.relfrozenxid)) as age,
        pg_size_pretty(pg_table_size(c.oid)) as table_size,
        c.relkind
FROM pg_class c
LEFT JOIN pg_class t ON c.reltoastrelid = t.oid
WHERE c.relkind in ('r', 't','m')
order by 2 desc limit 20) as r1 )
order by 2,4 ;

-- table size

SELECT *, pg_size_pretty(total_bytes) AS TOTAL_PRETTY
    , pg_size_pretty(index_bytes) AS INDEX_PRETTY
    , pg_size_pretty(toast_bytes) AS TOAST_PRETTY
    , pg_size_pretty(table_bytes) AS TABLE_PRETTY
  FROM (
  SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS TABLE_BYTES FROM (
      SELECT c.oid,nspname AS table_schema, relname AS TABLE_NAME
              , c.reltuples::bigint AS ROW_ESTIMATE
              , pg_total_relation_size(c.oid) AS TOTAL_BYTES
              , pg_indexes_size(c.oid) AS INDEX_BYTES
              , pg_total_relation_size(reltoastrelid) AS TOAST_BYTES
          FROM pg_class c
          LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE relkind = 'r'
  ) a
) a
order by 2,8 desc;

-- biggest 50 tables in DB
SELECT *, pg_size_pretty(total_bytes) AS TOTAL_PRETTY
    , pg_size_pretty(index_bytes) AS INDEX_PRETTY
    , pg_size_pretty(toast_bytes) AS TOAST_PRETTY
    , pg_size_pretty(table_bytes) AS TABLE_PRETTY
  FROM (
  SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS TABLE_BYTES FROM (
      SELECT c.oid,nspname AS table_schema, relname AS TABLE_NAME
              , c.reltuples::bigint AS ROW_ESTIMATE
              , pg_total_relation_size(c.oid) AS TOTAL_BYTES
              , pg_indexes_size(c.oid) AS INDEX_BYTES
              , pg_total_relation_size(reltoastrelid) AS TOAST_BYTES
          FROM pg_class c
          LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE relkind = 'r'
  ) a
) a
order by 5 desc
LIMIT 50;

-- index size by schema and size
SELECT
schemaname,relname as "Table",
indexrelname AS indexname,
pg_relation_size(indexrelid),
pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_catalog.pg_statio_all_indexes  ORDER BY 1,2 desc ;

-- biggest indexes in DB
SELECT
schemaname as schema_name,relname as "Table",
indexrelname AS indexname,
pg_relation_size(indexrelid),
pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_catalog.pg_statio_all_indexes  ORDER BY 4 desc limit 50;

-- memory settings

(
select name as parameter_name , setting , unit, (setting::BIGINT/1024)::BIGINT  as "size_MB" ,(setting::BIGINT/1024/1024)::BIGINT  as "size_GB" ,  pg_size_pretty((setting::BIGINT*1024)::BIGINT)   
from pg_settings where name in ('work_mem','maintenance_work_mem')
)
UNION ALL
(
select name as parameter_name, setting , unit , (((setting::BIGINT)*8)/1024)::BIGINT  as "size_MB" ,(((setting::BIGINT)*8)/1024/1024)::BIGINT  as "size_GB", pg_size_pretty((((setting::BIGINT)*8)*1024)::BIGINT)  
from pg_settings where name in ('shared_buffers','wal_buffers','effective_cache_size','temp_buffers')
) order by 4  desc;

-- cache hit for all dbs
select 
round((sum(blks_hit)::numeric / (sum(blks_hit) + sum(blks_read)::numeric))*100,2) as cache_read_hit_percentage
from pg_stat_database ;

-- cache hit by dbs
select datname as database_name, 
round((blks_hit::numeric / (blks_hit + blks_read)::numeric)*100,2) as cache_read_hit_percentage
from pg_stat_database 
where blks_hit + blks_read > 0
and datname is not null 
order by 2 desc;

-- cache hit by tables
SELECT schemaname,relname as table_name,
 round((heap_blks_hit::numeric / (heap_blks_hit + heap_blks_read)::numeric)*100,2) as read_hit_percentage
FROM 
  pg_statio_all_tables
  where heap_blks_hit + heap_blks_read > 0
  and schemaname not in ('pg_catalog','information_schema')
  order by 3;

-- cache hit by indexes
SELECT schemaname,relname as table_name,indexrelname as index_name ,
 round((idx_blks_hit::numeric / (idx_blks_hit + idx_blks_read)::numeric)*100,2) as read_hit_percentage
FROM 
  pg_statio_all_indexes
  where idx_blks_hit + idx_blks_read > 0
  and schemaname not in ('pg_catalog','information_schema')
  order by 4;

--Top SQL order by total_exec_time
select queryid,substring(query,1,60) as query , calls, 
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by total_time_Msec desc limit 20;

--Top SQL order by avg_time
select queryid,substring(query,1,60) as query , calls,
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by avg_time_Msec desc limit 20;

--Top SQL order by percent of total DB time
select queryid,substring(query,1,60) as query , calls, 
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by percent desc limit 20;

--Top SQL order by number of execution (CALLs)  
select queryid,substring(query,1,60) as query , calls,
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent
from pg_stat_statements 
order by calls desc limit 20;

--Top SQL order by shared blocks read (physical reads) 
select queryid, substring(query,1,60) as query , calls,
round(total_exec_time::numeric, 2) as total_time_Msec, 
round((total_exec_time::numeric/1000), 2) as total_time_sec,
round(mean_exec_time::numeric,2) as avg_time_Msec,
round((mean_exec_time::numeric/1000),2) as avg_time_sec,
round(stddev_exec_time::numeric, 2) as standard_deviation_time_Msec, 
round((stddev_exec_time::numeric/1000), 2) as standard_deviation_time_sec, 
round(rows::numeric/calls,2) rows_per_exec,
round((100 * total_exec_time / sum(total_exec_time) over ())::numeric, 4) as percent,
shared_blks_read
from pg_stat_statements 
order by shared_blks_read desc limit 20;

-- list of users
select * FROM pg_user;

-- list of role grants
SELECT m.rolname AS "Role name", r.rolname AS "Member of",
  pg_catalog.concat_ws(', ',
    CASE WHEN pam.admin_option THEN 'ADMIN' END,
    CASE WHEN pam.inherit_option THEN 'INHERIT' END,
    CASE WHEN pam.set_option THEN 'SET' END
  ) AS "Options",
  g.rolname AS "Grantor"
FROM pg_catalog.pg_roles m
     JOIN pg_catalog.pg_auth_members pam ON (pam.member = m.oid)
     LEFT JOIN pg_catalog.pg_roles r ON (pam.roleid = r.oid)
     LEFT JOIN pg_catalog.pg_roles g ON (pam.grantor = g.oid)
WHERE m.rolname !~ '^pg_'
ORDER BY 1, 2, 4;

-- object count per schema
select 
n.nspname as schema_name, count (*) 
from pg_catalog.pg_class c
lEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
GROUP BY n.nspname
order by  2 desc ;

--object count by type per schema
SELECT
n.nspname as schema_name
,CASE c.relkind
   WHEN 'r' THEN 'table'
   WHEN 'v' THEN 'view'
   WHEN 'i' THEN 'index'
   WHEN 'S' THEN 'sequence'
   WHEN 't' THEN 'TOAST table'
   WHEN 'm' THEN 'materialized view'
   WHEN 'c' THEN 'composite type'
   WHEN 'f' THEN 'foreign table'
   WHEN 'p' THEN 'partitioned table'
   WHEN 'I' THEN 'partitioned index'
END as object_type
,count(1) as object_count
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','v','i','S','s')
GROUP BY  n.nspname,
CASE c.relkind
   WHEN 'r' THEN 'table'
   WHEN 'v' THEN 'view'
   WHEN 'i' THEN 'index'
   WHEN 'S' THEN 'sequence'
   WHEN 't' THEN 'TOAST table'
   WHEN 'm' THEN 'materialized view'
   WHEN 'c' THEN 'composite type'
   WHEN 'f' THEN 'foreign table'
   WHEN 'p' THEN 'partitioned table'
   WHEN 'I' THEN 'partitioned index'
END
ORDER BY n.nspname,
CASE c.relkind
   WHEN 'r' THEN 'table'
   WHEN 'v' THEN 'view'
   WHEN 'i' THEN 'index'
   WHEN 'S' THEN 'sequence'
   WHEN 't' THEN 'TOAST table'
   WHEN 'm' THEN 'materialized view'
   WHEN 'c' THEN 'composite type'
   WHEN 'f' THEN 'foreign table'
   WHEN 'p' THEN 'partitioned table'
   WHEN 'I' THEN 'partitioned index'
END;

-- list of objects
select nsp.nspname as schema,
       rol.rolname as owner, 
       cls.relname as object_name,        
       case cls.relkind
         WHEN 'r' THEN 'table'
         WHEN 'v' THEN 'view'
         WHEN 'i' THEN 'index'
         WHEN 'S' THEN 'sequence'
         WHEN 't' THEN 'TOAST table'
         WHEN 'm' THEN 'materialized view'
         WHEN 'c' THEN 'composite type'
         WHEN 'f' THEN 'foreign table'
         WHEN 'p' THEN 'partitioned table'
         WHEN 'I' THEN 'partitioned index'
         else cls.relkind::text
       end as object_type
from pg_class cls
  join pg_roles rol on rol.oid = cls.relowner
  join pg_namespace nsp on nsp.oid = cls.relnamespace
order by 1,2,4;

-- tablespace info
SELECT spcname as Tablespace_Name,
  pg_catalog.pg_get_userbyid(spcowner) as Owner,
CASE
WHEN 
pg_tablespace_location(oid)=''
AND     spcname='pg_default'
THEN
current_setting('data_directory')||'/base/'
WHEN 
pg_tablespace_location(oid)=''
AND     spcname='pg_global'
THEN
current_setting('data_directory')||'/global/'
ELSE
pg_tablespace_location(oid)
END
AS      location          ,
spcacl,spcoptions
FROM pg_catalog.pg_tablespace
ORDER BY 1;

-- table scan profile
with table_size_info as 
(SELECT
schemaname as schema_name,relname as "Table",
pg_relation_size(relid) relation_size,
relid,
pg_size_pretty(pg_relation_size(relid)) AS "table_size",
pg_size_pretty(pg_total_relation_size(relid)) AS "TABLE size + indexes",
pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) as "indexes size"
FROM pg_catalog.pg_statio_all_tables ORDER BY 1,3  desc)
Select
b.schema_name,
a.relname as "Table_Name",
b.table_size as "Table_Size",
a.seq_scan  total_fts_scan ,
a.seq_tup_read total_fts_num_rows_reads,
a.seq_tup_read/NULLIF(a.seq_scan,0)  fts_rows_per_read ,
a.idx_scan total_idx_scan,
a.idx_tup_fetch total_Idx_num_rows_read ,
a.idx_tup_fetch/NULLIF(a.idx_scan,0)  idx_rows_per_read,
trunc((idx_scan::numeric/NULLIF((idx_scan::numeric+seq_scan::numeric),0)) * 100,2) as "IDX_scan_%",
trunc((seq_scan::numeric/NULLIF((idx_scan::numeric+seq_scan::numeric),0)) * 100,2) as "FTS_scan_%",
case when seq_scan>idx_scan then 'FTS' else 'IDX' end access_profile,
a.n_live_tup,
a.n_dead_tup,
trunc((n_dead_tup::numeric/NULLIF(n_live_tup::numeric,0)) * 100,2) as "dead_tup_%",
a.n_tup_ins,
a.n_tup_upd, 
a.n_tup_del,
trunc((n_tup_ins::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_ins_%",
trunc((n_tup_upd::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_upd_%",
trunc((n_tup_del::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_del_%" 
from pg_stat_all_tables  a ,  table_size_info  b
where a.relid=b.relid 
and schema_name not in ('pg_catalog')
order  by b.relation_size  desc;

-- table have more Full table scan than index scan
with table_size_info as 
(SELECT
schemaname as schema_name,relname as "Table",
pg_relation_size(relid) relation_size,
relid,
pg_size_pretty(pg_relation_size(relid)) AS "table_size",
pg_size_pretty(pg_total_relation_size(relid)) AS "TABLE size + indexes",
pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) as "indexes size"
FROM pg_catalog.pg_statio_all_tables ORDER BY 1,3  desc)
Select
b.schema_name,
a.relname as "Table_Name",
b.table_size as "Table_Size",
a.seq_scan  total_fts_scan ,
a.seq_tup_read total_fts_num_rows_reads,
a.seq_tup_read/NULLIF(a.seq_scan,0)  fts_rows_per_read ,
a.idx_scan total_idx_scan,
a.idx_tup_fetch total_Idx_num_rows_read ,
a.idx_tup_fetch/NULLIF(a.idx_scan,0)  idx_rows_per_read,
trunc((idx_scan::numeric/NULLIF((idx_scan::numeric+seq_scan::numeric),0)) * 100,2) as "IDX_scan_%",
trunc((seq_scan::numeric/NULLIF((idx_scan::numeric+seq_scan::numeric),0)) * 100,2) as "FTS_scan_%",
case when seq_scan>idx_scan then 'FTS' else 'IDX' end access_profile,
a.n_live_tup,
a.n_dead_tup,
trunc((n_dead_tup::numeric/NULLIF(n_live_tup::numeric,0)) * 100,2) as "dead_tup_%",
a.n_tup_ins,
a.n_tup_upd, 
a.n_tup_del,
trunc((n_tup_ins::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_ins_%",
trunc((n_tup_upd::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_upd_%",
trunc((n_tup_del::numeric/NULLIF((n_tup_ins::numeric+n_tup_upd::numeric+n_tup_del::numeric),0)) * 100,2) as "tup_del_%" 
from pg_stat_all_tables  a ,  table_size_info  b
where a.relid=b.relid 
and schema_name not in ('pg_catalog', 'pg_toast')
and seq_scan>idx_scan
and b.relation_size > 10485760
order by b.relation_size desc;


-- top 50 tables by total physical reads
select
s2.* , 
coalesce(trunc((s2.total_physical_reads::numeric/NULLIF((s2.total_physical_reads::numeric+s2.total_logical_reads::numeric),0)) * 100,2),0)  as physical_reads_percent,
coalesce(trunc((s2.total_logical_reads::numeric/NULLIF((s2.total_physical_reads::numeric+s2.total_logical_reads::numeric),0)) * 100,2),0)  as logical_reads_percent
from 
(
select 
s.* ,
s.table_disk_blocks_read+
s.indexes_disk_blocks_read+
s.TOAST_table_disk_blocks_read+
s.TOAST_indexes_disk_blocks_read as total_physical_reads,

s.table_buffer_hits+
s.indexes_buffer_hits+
s.TOAST_table_buffer_hits+
s.TOAST_indexes_buffer_hits as total_logical_reads 
from
(
select
schemaname as schema_name,
relname as table_name,
coalesce(heap_blks_read,0) table_disk_blocks_read ,
coalesce(heap_blks_hit,0)  table_buffer_hits ,
coalesce(idx_blks_read,0) indexes_disk_blocks_read ,
coalesce(idx_blks_hit,0)   indexes_buffer_hits ,
coalesce(toast_blks_read,0) TOAST_table_disk_blocks_read ,
coalesce(toast_blks_hit,0)  TOAST_table_buffer_hits ,
coalesce(tidx_blks_read,0)  TOAST_indexes_disk_blocks_read ,
coalesce(tidx_blks_hit,0)   TOAST_indexes_buffer_hits 
from pg_statio_all_tables 
where schemaname not in ('pg_toast','pg_catalog','information_schema')
 ) as s

) as s2
order by s2.total_physical_reads  desc limit 50 ;


-- top tables by total physical read percent
select 
s2.* , 
coalesce(trunc((s2.total_physical_reads::numeric/NULLIF((s2.total_physical_reads::numeric+s2.total_logical_reads::numeric),0)) * 100,2),0)  as physical_reads_percent,
coalesce(trunc((s2.total_logical_reads::numeric/NULLIF((s2.total_physical_reads::numeric+s2.total_logical_reads::numeric),0)) * 100,2),0)  as logical_reads_percent
from 
(
select 
s.* ,
s.table_disk_blocks_read+
s.indexes_disk_blocks_read+
s.TOAST_table_disk_blocks_read+
s.TOAST_indexes_disk_blocks_read as total_physical_reads,

s.table_buffer_hits+
s.indexes_buffer_hits+
s.TOAST_table_buffer_hits+
s.TOAST_indexes_buffer_hits as total_logical_reads 
from
(
select
schemaname as schema_name,
relname as table_name,
coalesce(heap_blks_read,0) table_disk_blocks_read ,
coalesce(heap_blks_hit,0)  table_buffer_hits ,
coalesce(idx_blks_read,0) indexes_disk_blocks_read ,
coalesce(idx_blks_hit,0)   indexes_buffer_hits ,
coalesce(toast_blks_read,0) TOAST_table_disk_blocks_read ,
coalesce(toast_blks_hit,0)  TOAST_table_buffer_hits ,
coalesce(tidx_blks_read,0)  TOAST_indexes_disk_blocks_read ,
coalesce(tidx_blks_hit,0)   TOAST_indexes_buffer_hits 
from pg_statio_all_tables
where schemaname not in ('pg_toast','pg_catalog','information_schema')  
) as s

) as s2 
order by physical_reads_percent  desc limit 50  ;

-- unused indexes
SELECT ai.schemaname,ai.relname AS tablename,ai.indexrelid  as index_oid ,
ai.indexrelname AS indexname,i.indisunique ,
ai.idx_scan ,
pg_relation_size(ai.indexrelid) as index_size,
pg_size_pretty(pg_relation_size(ai.indexrelid)) AS pretty_index_size
FROM pg_catalog.pg_stat_all_indexes ai , pg_index i
WHERE ai.indexrelid=i.indexrelid
and ai.idx_scan = 0 
and ai.schemaname not in ('pg_catalog')
order by index_size desc;

-- index access profile 

with index_size_info as 
(
SELECT
schemaname,relname as "Table",
indexrelname AS indexname,
indexrelid,
pg_relation_size(indexrelid) index_size_byte,
pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_catalog.pg_statio_all_indexes  ORDER BY 1,4 desc) 
Select a.schemaname, 
a.relname as "Table_Name",
a.indexrelname AS indexname,
b.index_size,
a.idx_scan,
a.idx_tup_read,
a.idx_tup_fetch
from pg_stat_all_indexes a ,  index_size_info b
where a.idx_scan >0  
and a.indexrelid=b.indexrelid
and a.schemaname not in ('pg_catalog')
order by b.index_size_byte desc,a.idx_scan asc ;

-- top indexes by total physical reads

select
schemaname        as schema_name  ,
relname            as table_name     ,
indexrelname    as index_name,
coalesce(idx_blks_read,0)   as indexe_disk_blocks_read,
coalesce(idx_blks_hit,0)    as indexe_buffer_hits    ,
coalesce(trunc((coalesce(idx_blks_read,0)
/ 
NULLIF(
coalesce(idx_blks_read,0)
+coalesce(idx_blks_hit,0)
,0) ) * 100,2),0) as physical_reads_percent ,
coalesce(trunc((coalesce(idx_blks_hit,0)
/ 
NULLIF(
coalesce(idx_blks_read,0)
+coalesce(idx_blks_hit,0)
,0) ) * 100,2),0) as logical_reads_percent
from 
pg_statio_all_indexes 
where schemaname not in ('pg_toast','pg_catalog','information_schema')
order by indexe_disk_blocks_read desc limit 50 ;

-- fragmentation
-- Tables and indexes Bloat [Fragmentation] order by table wasted size


SELECT
  current_database(), schemaname, tablename, /*reltuples::bigint, relpages::bigint, otta,*/
  ROUND((CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages::FLOAT/otta END)::NUMERIC,1) AS "table_bloat_ratio",
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END AS wastedbytes,
  pg_size_pretty(CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END) AS table_wasted_size,
  iname AS Index_nam, /*ituples::bigint, ipages::bigint, iotta,*/
  ROUND((CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages::FLOAT/iotta END)::NUMERIC,1) AS "Index_bloat_ratio",
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  pg_size_pretty(CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) ::BIGINT END) AS Index_wasted_size
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::FLOAT)) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::FLOAT)),0) AS iotta -- very rough approximation, assumes all cols
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(CASE WHEN hdr%ma=0 THEN ma ELSE hdr%ma END)))::NUMERIC AS datahdr,
      (maxfracsum*(nullhdr+ma-(CASE WHEN nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+COUNT(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          (SELECT current_setting('block_size')::NUMERIC) AS bs,
          CASE WHEN SUBSTRING(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml
ORDER BY wastedbytes DESC; 


-- bloat by ratio
SELECT
  current_database(), schemaname, tablename, /*reltuples::bigint, relpages::bigint, otta,*/
  ROUND((CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages::FLOAT/otta END)::NUMERIC,1) AS "table_bloat_ratio",
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END AS wastedbytes,
  pg_size_pretty(CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END) AS table_wasted_size,
  iname AS Index_nam, /*ituples::bigint, ipages::bigint, iotta,*/
  ROUND((CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages::FLOAT/iotta END)::NUMERIC,1) AS "Index_bloat_ratio",
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  pg_size_pretty(CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) ::BIGINT END) AS Index_wasted_size
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::FLOAT)) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::FLOAT)),0) AS iotta -- very rough approximation, assumes all cols
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(CASE WHEN hdr%ma=0 THEN ma ELSE hdr%ma END)))::NUMERIC AS datahdr,
      (maxfracsum*(nullhdr+ma-(CASE WHEN nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+COUNT(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          (SELECT current_setting('block_size')::NUMERIC) AS bs,
          CASE WHEN SUBSTRING(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml
ORDER BY 4 desc; 


SELECT
  current_database(), schemaname, tablename, /*reltuples::bigint, relpages::bigint, otta,*/
  ROUND((CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages::FLOAT/otta END)::NUMERIC,1) AS "table_bloat_ratio",
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END AS wastedbytes,
  pg_size_pretty(CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::BIGINT END) AS table_wasted_size,
  iname AS Index_nam, /*ituples::bigint, ipages::bigint, iotta,*/
  ROUND((CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages::FLOAT/iotta END)::NUMERIC,1) AS "Index_bloat_ratio",
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  pg_size_pretty(CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) ::BIGINT END) AS Index_wasted_size
FROM (
  SELECT
    schemaname, tablename, cc.reltuples, cc.relpages, bs,
    CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::FLOAT)) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::FLOAT)),0) AS iotta -- very rough approximation, assumes all cols
  FROM (
    SELECT
      ma,bs,schemaname,tablename,
      (datawidth+(hdr+ma-(CASE WHEN hdr%ma=0 THEN ma ELSE hdr%ma END)))::NUMERIC AS datahdr,
      (maxfracsum*(nullhdr+ma-(CASE WHEN nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        schemaname, tablename, hdr, ma, bs,
        SUM((1-null_frac)*avg_width) AS datawidth,
        MAX(null_frac) AS maxfracsum,
        hdr+(
          SELECT 1+COUNT(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
        ) AS nullhdr
      FROM pg_stats s, (
        SELECT
          (SELECT current_setting('block_size')::NUMERIC) AS bs,
          CASE WHEN SUBSTRING(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname AND nn.nspname <> 'information_schema'
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml
ORDER BY 8 desc; 

-- toast table mapping
select t.relname table_name, r.relname toast_name,r.oid as toast_oid, pg_relation_size(t.reltoastrelid) as toast_size_bytes  ,pg_size_pretty(pg_relation_size(t.reltoastrelid)) as toast_size
FROM
    pg_class r
INNER JOIN pg_class t ON r.oid = t.reltoastrelid
order by toast_size_bytes desc ;  


-- replication lag
select slot_name,slot_type,database,active,
coalesce(round(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) / 1024 / 1024 , 2),0) AS Lag_MB_behind ,
coalesce(round(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) / 1024 / 1024 / 1024, 2),0) AS Lag_GB_behind
from pg_replication_slots 
order by Lag_MB_behind desc;



select 
name as parameter_name,setting,unit,short_desc  
FROM pg_catalog.pg_settings 
WHERE name in ('max_slot_wal_keep_size' ) ;

select slot_name,slot_type,database,active,wal_status ,safe_wal_size ,
coalesce(round(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) / 1024 / 1024 , 2),0) AS Lag_MB_behind ,
coalesce(round(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) / 1024 / 1024 / 1024, 2),0) AS Lag_GB_behind
from pg_replication_slots 
order by safe_wal_size ;

-- replication parameters

select 
name as parameter_name,setting,unit,short_desc  
FROM pg_catalog.pg_settings 
WHERE name in ('wal_level','max_wal_senders','max_replication_slots',
'max_worker_processes','max_logical_replication_workers','wal_receiver_timeout',
'max_sync_workers_per_subscription','wal_receiver_status_interval','wal_retrieve_retry_interval','logical_decoding_work_mem','max_slot_wal_keep_size' ) ;

-- connection utilization

with
settings as (SELECT setting::float AS "max_connections" FROM pg_settings WHERE name = 'max_connections'),
connections as (select sum (numbackends)::float total_connections from pg_stat_database)
select   settings.max_connections AS "Max_connections" ,total_connections as "Total_connections",ROUND((100*(connections.Total_connections/settings.max_connections))::numeric,2) as "Connections utilization %" from  settings, connections;

select  name as parameter_name , setting , short_desc from pg_settings WHERE name in ('superuser_reserved_connections', 'reserved_connections');

select 
datname as Database_name
,session_time
,active_time
,idle_in_transaction_time
,sessions
,sessions_abandoned
,sessions_fatal
,sessions_killed
from pg_stat_database 
where datname is not null 
order by active_time desc ;

SELECT datname as "Database_Name",count(*) as "Connections_count" FROM pg_stat_activity where datname is not null group by datname order by 2 desc;

SELECT datname as "Database_Name",usename as "User_Name" ,count(*) as "Connections_count" FROM pg_stat_activity  where datname is not null  group by datname,usename order by 1,3 desc;


SELECT usename as "User_Name",count(*) as "connections_count" FROM pg_stat_activity  where datname is not null  group by usename order by 2 desc;


SELECT usename as "User_Name",state as status,count(*) as "Connections_count" FROM pg_stat_activity  where datname is not null group by usename,state order by 1,2 desc;

select datname as "Database_Name" ,usename as "User_Name",state as status,count(*) as "Connections_count" FROM pg_stat_activity where datname is not null group by datname ,usename,state order by 4 desc;

SELECT state as status ,count(*) as "Connections_count" FROM pg_stat_activity where datname is not null GROUP BY status order by 2 desc;

SELECT usename as "User_Name" , state as status , query, count(*) FROM pg_stat_activity where datname is not null group by usename,state,query ;

SELECT usename as "User_Name" , state as status , query_id, count(*) FROM pg_stat_activity where datname is not null group by usename,state,query_id ;

-- active session monitor
/* active_session_monitor*/ select * from
(
    SELECT
usename,pid, now() - pg_stat_activity.xact_start AS xact_duration ,now() - pg_stat_activity.query_start AS query_duration,
substr(query,1,50) as query,query_id,state,wait_event
FROM pg_stat_activity
) as s where (xact_duration is not null  or query_duration is not null ) and state!='idle' and query not like '%active_session_monitor%'
order by xact_duration desc, query_duration desc;

-- invalid indexes
select count (*) as count_of_invalid_indxes from pg_index WHERE pg_index.indisvalid = false ;
with table_info as 
(SELECT pg_index.indrelid , pg_class.oid, pg_class.relname as table_name 
from   pg_class , pg_index
where pg_index.indrelid = pg_class.oid )
SELECT distinct pg_index.indexrelid as INDX_ID,pg_class.relname as index_name ,table_info.table_name,pg_namespace.nspname as schema_name  , pg_class.relowner as owner_id , pg_index.indisvalid as indx_is_valid
FROM pg_class , pg_index ,pg_namespace , table_info
WHERE pg_index.indisvalid = false 
AND pg_index.indexrelid = pg_class.oid
and pg_class.relnamespace = pg_namespace.oid
and pg_index.indrelid = table_info.oid
;


-- access privilege
SELECT n.nspname as "Schema",
  c.relname as "Name",
  CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized view' WHEN 'S' THEN 'sequence' WHEN 'f' THEN 'foreign table' END as "Type",
  pg_catalog.array_to_string(c.relacl, E'\n') AS "Access privileges",
  pg_catalog.array_to_string(ARRAY(
    SELECT attname || E':\n  ' || pg_catalog.array_to_string(attacl, E'\n  ')
    FROM pg_catalog.pg_attribute a
    WHERE attrelid = c.oid AND NOT attisdropped AND attacl IS NOT NULL
  ), E'\n') AS "Column access privileges"
FROM pg_catalog.pg_class c
     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'v', 'm', 'S', 'f')
  AND n.nspname !~ '^pg_' AND pg_catalog.pg_table_is_visible(c.oid)
ORDER BY 1, 3, 2;

-- temp tables
select 
name as parameter_name,setting,unit,short_desc  
FROM pg_catalog.pg_settings 
WHERE name in ('temp_tablespaces','temp_file_limit','log_temp_files' ) ;

-- temp table stats
select datname as database_name, temp_bytes/1024/1024 temp_size_MB,
temp_bytes/1024/1024/1024 temp_size_GB ,temp_files  from  pg_stat_database
where  temp_bytes + temp_files > 0
and datname is not null  
order by 2  desc;


SELECT
n.nspname as SchemaName
,c.relname as RelationName
,CASE c.relkind
WHEN 'r' THEN 'table'
WHEN 'v' THEN 'view'
WHEN 'i' THEN 'index'
WHEN 'S' THEN 'sequence'
WHEN 's' THEN 'special'
END as RelationType
,pg_catalog.pg_get_userbyid(c.relowner) as RelationOwner
,pg_size_pretty(pg_relation_size(n.nspname ||'.'|| c.relname)) as RelationSize
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n
ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','s')
AND (n.nspname !~ '^pg_toast' and nspname like 'pg_temp%')
ORDER BY pg_relation_size(n.nspname ||'.'|| c.relname) DESC ;


-- partition tables
SELECT
    parent.oid                        AS parent_table_oid,
    parent.relname                    AS parent_table_name,
    count(child.oid)                  AS partition_count
FROM pg_inherits
    JOIN pg_class parent            ON pg_inherits.inhparent = parent.oid
    JOIN pg_class child             ON pg_inherits.inhrelid   = child.oid 
    group by 1,2
    order by 3 desc;

SELECT
    parent.relnamespace::regnamespace AS parent_table_schema,
    parent.relowner::regrole          AS parent_table_owner,
    parent.oid                        AS parent_table_oid,
    parent.relname                    AS parent_table_name,
  --child.relnamespace::regnamespace  AS partition_schema,
    child.oid                         AS partition_oid,
    child.relname                     AS partition_name
FROM pg_inherits
    JOIN pg_class parent            ON pg_inherits.inhparent = parent.oid
    JOIN pg_class child             ON pg_inherits.inhrelid   = child.oid 
    order by 3 ,6;

-- FK without indexes
SELECT c.conrelid::regclass AS "table",
       /* list of key column names in order */
       string_agg(a.attname, ',' ORDER BY x.n) AS columns,
       pg_catalog.pg_size_pretty(
          pg_catalog.pg_relation_size(c.conrelid)
       ) AS size,
       c.conname AS constraint,
       c.confrelid::regclass AS referenced_table
FROM pg_catalog.pg_constraint c
   /* enumerated key column numbers per foreign key */
   CROSS JOIN LATERAL
      unnest(c.conkey) WITH ORDINALITY AS x(attnum, n)
   /* name for each key column */
   JOIN pg_catalog.pg_attribute a
      ON a.attnum = x.attnum
         AND a.attrelid = c.conrelid
WHERE NOT EXISTS
        /* is there a matching index for the constraint? */
        (SELECT 1 FROM pg_catalog.pg_index i
         WHERE i.indrelid = c.conrelid
           /* the first index columns must be the same as the
              key columns, but order doesn't matter */
           AND (i.indkey::smallint[])[0:cardinality(c.conkey)-1]
               OPERATOR(pg_catalog.@>) c.conkey)
  AND c.contype = 'f'
GROUP BY c.conrelid, c.conname, c.confrelid
ORDER BY pg_catalog.pg_relation_size(c.conrelid) DESC;


-- sequences with less than 10% remaining
--sequence wraparound
select * from 
(
select * ,(sec.max_value - coalesce(sec.last_value,0)) as remain_values ,round((((sec.max_value - coalesce(sec.last_value,0)::float)/sec.max_value::float) *100)::int,2) remain_values_pct from pg_sequences sec ) t
where remain_values_pct <= 10 
and cycle is false 
order by remain_values_pct;

-- all sequences
select * ,(sec.max_value - coalesce(sec.last_value,0)) as remain_values ,round((((sec.max_value - coalesce(sec.last_value,0)::float)/sec.max_value::float) *100)::int,2) remain_values_pct from pg_sequences sec order by remain_values_pct;


-- duplicate indexes
SELECT pg_size_pretty(sum(pg_relation_size(idx))::bigint) as size,
       (array_agg(idx))[1] as idx1, (array_agg(idx))[2] as idx2,
       (array_agg(idx))[3] as idx3, (array_agg(idx))[4] as idx4
FROM (
    SELECT indexrelid::regclass as idx, (indrelid::text ||E'\n'|| indclass::text ||E'\n'|| indkey::text ||E'\n'||
                                         coalesce(indexprs::text,'')||E'\n' || coalesce(indpred::text,'')) as key
    FROM pg_index) sub
GROUP BY key HAVING count(*)>1
ORDER BY sum(pg_relation_size(idx)) DESC;


-- db load
select coalesce(count(*),'0') as  count_of_sessions_waiting_on_CPU
FROM pg_stat_activity 
where wait_event is null and state = 'active' group by wait_event ;
\qecho <br>
select coalesce(sum(count),'0') as count_of_sessions_waiting_on_Non_CPU
from (SELECT count(*) as count
FROM pg_stat_activity  
where wait_event is not null and state = 'active' 
group by wait_event) as c;

-- wait events
SELECT coalesce(wait_event,'CPU') as wait_event , count(*) FROM pg_stat_activity group by wait_event order by 2 desc;
SELECT  coalesce(wait_event,'CPU') as wait_event, substr(query,1,150) as query,count(*) FROM pg_stat_activity   group by  query,wait_event order by 3 desc;

SELECT  coalesce(wait_event,'CPU') as wait_event, query_id ,count(*) FROM pg_stat_activity   group by  query_id,wait_event order by 3 desc;

SELECT coalesce(wait_event,'CPU') wait_event,usename as user_name, count(*) FROM pg_stat_activity group by wait_event, usename order by 3 desc ;

-- blocked sessions
select count(*) from pg_stat_activity where cardinality(pg_blocking_pids(pid)) > 0 ;
