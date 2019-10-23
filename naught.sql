drop schema pgt cascade;
drop schema mat_views cascade;
drop schema heimdal cascade;
drop schema hdb cascade;
drop schema test cascade;
\i mat_views.sql
set client_min_messages = notice;
\i hdb.sql
\i security.sql
\i test-hdb.sql
