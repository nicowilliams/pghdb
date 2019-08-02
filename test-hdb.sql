\unset ON_ERROR_STOP

SELECT set_config('hdb.test','true',true);

CREATE SCHEMA test;
DROP TABLE IF EXISTS test.tests;
CREATE TABLE test.tests (testname TEXT PRIMARY KEY, pass BOOLEAN);

CREATE OR REPLACE FUNCTION test.expect_success(testname TEXT, code TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
BEGIN
    EXECUTE code;
    INSERT INTO test.tests (testname, pass)
    SELECT testname, TRUE;
    RETURN TRUE;
EXCEPTION
WHEN OTHERS THEN
    INSERT INTO test.tests (testname, pass)
    SELECT testname, FALSE;
    RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION test.expect_exception(testname TEXT, code TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
BEGIN
    EXECUTE code;
    INSERT INTO test.tests (testname, pass)
    SELECT testname, FALSE;
    RETURN FALSE;
EXCEPTION
WHEN OTHERS THEN
    INSERT INTO test.tests (testname, pass)
    SELECT testname, TRUE;
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION test.expect_true(_testname TEXT, func TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
BEGIN
    EXECUTE format($q$
        INSERT INTO test.tests (testname, pass)
        SELECT %1$L, %2$s
        $q$, _testname, func);
    RETURN pass
    FROM test.tests t
    WHERE t.testname = _testname;
END;
$$;

CREATE OR REPLACE FUNCTION test.expect_false(_testname TEXT, func TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
BEGIN
    EXECUTE format($q$
        INSERT INTO test.tests (testname, pass)
        SELECT %1$L, NOT %2$s
        $q$, _testname, func);
    RETURN pass 
    FROM test.tests t
    WHERE t.testname = _testname;
END;
$$;

CREATE OR REPLACE FUNCTION test.check_against_table(_testname TEXT,
                                                    first_table_schema TEXT,
                                                    first_table_name TEXT,
                                                    second_table_schema TEXT,
                                                    second_table_name TEXT,
                                                    code TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
BEGIN
    EXECUTE code;
    EXECUTE format($q$
        INSERT INTO test.tests (testname, pass)
        SELECT %1$L, count(*) = 0
        FROM (SELECT 1
              FROM %2$I.%3$I AS tleft
              NATURAL FULL OUTER JOIN
              %4$I.%5$I AS tright
              WHERE tleft IS NULL OR tright IS NULL) q;
    $q$, _testname, first_table_schema, first_table_name,
    second_table_schema, second_table_name);
    RETURN pass
    FROM test.tests t
    WHERE t.testname = _testname;
END;
$$;

DROP TABLE IF EXISTS test_hdb_hdb_entry_update;
CREATE TEMP TABLE IF NOT EXISTS test_hdb_hdb_entry_update
    (testname TEXT, name TEXT, realm TEXT, entry JSONB);

CREATE OR REPLACE FUNCTION test.check_hdb_hdb_jsonb_update(
    _testname TEXT,
    _name TEXT,
    _realm TEXT,
    _code TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
BEGIN
    DELETE FROM pg_temp.test_hdb_hdb_entry_update
    WHERE testname = _testname;

    EXECUTE format($q$
        INSERT INTO pg_temp.test_hdb_hdb_entry_update
            (testname, name, realm, entry)
        SELECT %1$L, %2$L, %3$L, %4$s
        FROM hdb.hdb
        WHERE name = %2$L AND realm = %3$L
        $q$, _testname, _name, _realm, _code);

    EXECUTE format($q$
        UPDATE hdb.hdb
        SET entry = %3$s
        WHERE name = %1$L AND realm = %2$L
        $q$, _name, _realm, _code);
/*
    RAISE NOTICE 'check hdb hdb jsonb update here: %', (
        SELECT row(hdb.entry = t.entry, hdb.entry, t.entry)
        FROM hdb.hdb hdb
        JOIN pg_temp.test_hdb_hdb_entry_update t USING (name, realm)
        WHERE name = _name AND realm = _realm AND t.testname = _testname
    );
    */
    DELETE FROM test.tests WHERE testname = _testname;
    INSERT INTO test.tests (testname, pass)
    SELECT testname, hdb.entry = t.entry
    FROM hdb.hdb hdb
    JOIN pg_temp.test_hdb_hdb_entry_update t USING (name, realm)
    WHERE name = _name AND realm = _realm AND t.testname = _testname;

    RETURN pass FROM test.tests WHERE testname = _testname;
END;$$;

CREATE OR REPLACE FUNCTION test.test_insert_PKs(testname TEXT, code TEXT)
RETURNS BOOLEAN LANGUAGE SQL AS $$
SELECT test.expect_success(testname || ' first', code) AND
       test.expect_exception(testname || ' second', code);
$$;
/*
CREATE OR REPLACE FUNCTION test.check_selects(testname TEXT, lft TEXT, rhgt TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
    EXECUTE format($q$
        SELECT count(*) == 0
        FROM (%1s) lft
        NATURAL FULL OUTER JOIN (%2s) rght;
    $q$, lft, rhgt);
$$;

CREATE TEMP TABLE x AS SELECT name, realm, jsonb_set(entry, ...) FROM hdb.hdb;
UPDATE ...;
SELECT test.check_selects('some test',
                          $$SELECT name, realm, entry FROM x$$,
                          $$SELECT name, realm, entry FROM hdb.hdb$$);

\o /dev/null
SELECT test.expect_success('trivial select', $$select 1;$$);
SELECT test.expect_exception('syntax error', $$blah;$$);
\o

\set ON_ERROR_STOP 1
*/

-- DELETE past test data here
DELETE FROM heimdal.entities
WHERE name like 'test%';
-- INSERT test data here
SELECT 'test entity creation',
       test.test_insert_PKs('test entity creation', $$
INSERT INTO heimdal.entities (name, realm, container, entity_type, owner_name, owner_realm, owner_container, owner_entity_type)
VALUES ('testgroup0', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup0', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup1', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup1', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup2', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup2', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup3', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup3', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup4', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup4', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup5', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup5', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup6', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup6', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup7', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup7', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup8', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup8', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup9', 'FOO.EXAMPLE', 'GROUP', 'GROUP', 'testgroup9', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('WRITE', 'FOO.EXAMPLE', 'VERB', 'VERB', 'WRITE', 'FOO.EXAMPLE', 'VERB', 'VERB'),
       ('READ', 'FOO.EXAMPLE', 'VERB', 'VERB', 'READ', 'FOO.EXAMPLE', 'VERB', 'VERB'),
       ('WRITER', 'FOO.EXAMPLE', 'ROLE', 'ROLE', 'WRITER', 'FOO.EXAMPLE', 'ROLE', 'ROLE'),
       ('READER', 'FOO.EXAMPLE', 'ROLE', 'ROLE', 'READER', 'FOO.EXAMPLE', 'ROLE', 'ROLE'),
       ('testlabel0', 'FOO.EXAMPLE', 'LABEL', 'LABEL', 'testlabel0', 'FOO.EXAMPLE', 'LABEL', 'LABEL'),
       ('testlabel1', 'FOO.EXAMPLE', 'LABEL', 'LABEL', 'testlabel1', 'FOO.EXAMPLE', 'LABEL', 'LABEL'),
       ('testlabel2', 'FOO.EXAMPLE', 'LABEL', 'LABEL', 'testlabel2', 'FOO.EXAMPLE', 'LABEL', 'LABEL'),
       ('user0', 'FOO.EXAMPLE', 'USER', 'USER', 'user0', 'FOO.EXAMPLE', 'USER', 'USER'),
       ('user1', 'FOO.EXAMPLE', 'USER', 'USER', 'user1', 'FOO.EXAMPLE', 'USER', 'USER'),
       ('user2', 'FOO.EXAMPLE', 'USER', 'USER', 'user2', 'FOO.EXAMPLE', 'USER', 'USER'),
       ('user3', 'FOO.EXAMPLE', 'USER', 'USER', 'user3', 'FOO.EXAMPLE', 'USER', 'USER'),
       ('user4', 'FOO.EXAMPLE', 'USER', 'USER', 'user4', 'FOO.EXAMPLE', 'USER', 'USER'),
       ('user5', 'FOO.EXAMPLE', 'USER', 'USER', 'user5', 'FOO.EXAMPLE', 'USER', 'USER'),
       ('user0', 'BAR.EXAMPLE', 'USER', 'USER', 'user0', 'BAR.EXAMPLE', 'USER', 'USER');
$$);
SELECT 'test roles2verbs',
       test.test_insert_PKs('test roles2verbs', $$
INSERT INTO heimdal.roles2verbs (role_name, role_realm, role_container, verb_name, verb_realm, verb_container)
VALUES ('WRITER', 'FOO.EXAMPLE', 'ROLE', 'WRITE', 'FOO.EXAMPLE', 'VERB'),
       ('WRITER', 'FOO.EXAMPLE', 'ROLE', 'READ', 'FOO.EXAMPLE', 'VERB'),
       ('READER', 'FOO.EXAMPLE', 'ROLE', 'READ', 'FOO.EXAMPLE', 'VERB');
$$);
SELECT 'test grants creation',
       test.test_insert_PKs('test grants creation', $$
INSERT INTO heimdal.grants (label_name, label_realm, label_container,
                            role_name, role_realm, role_container,
                            subject_name, subjecT_realm, subject_container)
VALUES ('testlabel0', 'FOO.EXAMPLE', 'LABEL', 'WRITER', 'FOO.EXAMPLE', 'ROLE', 'user0', 'FOO.EXAMPLE', 'USER'),
       ('testlabel1', 'FOO.EXAMPLE', 'LABEL', 'WRITER', 'FOO.EXAMPLE', 'ROLE', 'user1', 'FOO.EXAMPLE', 'USER'),
       ('testlabel2', 'FOO.EXAMPLE', 'LABEL', 'WRITER', 'FOO.EXAMPLE', 'ROLE', 'user2', 'FOO.EXAMPLE', 'USER'),
       ('testlabel0', 'FOO.EXAMPLE', 'LABEL', 'READER', 'FOO.EXAMPLE', 'ROLE', 'testgroup5', 'FOO.EXAMPLE', 'GROUP'),
       ('testlabel1', 'FOO.EXAMPLE', 'LABEL', 'READER', 'FOO.EXAMPLE', 'ROLE', 'testgroup0', 'FOO.EXAMPLE', 'GROUP'),
       ('testlabel2', 'FOO.EXAMPLE', 'LABEL', 'READER', 'FOO.EXAMPLE', 'ROLE', 'testgroup1', 'FOO.EXAMPLE', 'GROUP');
$$);
SELECT 'test principal insertion',
       test.test_insert_PKs('test principal insertion', $$
INSERT INTO heimdal.principals (name, realm, password)
VALUES ('test0', 'FOO.EXAMPLE', 'password-00'),
       ('test1', 'FOO.EXAMPLE', 'password-01'),
       ('test2', 'FOO.EXAMPLE', 'password-02'),
       ('test3', 'FOO.EXAMPLE', 'password-03'),
       ('test4', 'FOO.EXAMPLE', 'password-04'),
       ('test5', 'FOO.EXAMPLE', 'password-05'),
       ('test6', 'FOO.EXAMPLE', 'password-06'),
       ('test7', 'FOO.EXAMPLE', 'password-07'),
       ('test8', 'FOO.EXAMPLE', 'password-08'),
       ('test9', 'FOO.EXAMPLE', 'password-09'),
       ('test0', 'BAR.EXAMPLE', 'password-10');
$$);
SELECT 'test entity owner update',
       test.expect_success('test entity owner update', $$
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('user0', 'FOO.EXAMPLE', 'USER', 'USER')
WHERE name = 'test0' AND realm LIKE 'F%';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('user0', 'FOO.EXAMPLE', 'USER', 'USER')
WHERE name = 'test0' AND realm LIKE 'B%';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('user1', 'FOO.EXAMPLE', 'USER', 'USER')
WHERE name = 'test1';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('user2', 'FOO.EXAMPLE', 'USER', 'USER')
WHERE name = 'test2';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('user3', 'FOO.EXAMPLE', 'USER', 'USER')
WHERE name = 'test3';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('user4', 'FOO.EXAMPLE', 'USER', 'USER')
WHERE name = 'test4';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('user5', 'FOO.EXAMPLE', 'USER', 'USER')
WHERE name = 'test5';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('testgroup0', 'FOO.EXAMPLE', 'GROUP', 'GROUP')
WHERE name = 'test6';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('testgroup1', 'FOO.EXAMPLE', 'GROUP', 'GROUP')
WHERE name = 'test7';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('testgroup2', 'FOO.EXAMPLE', 'GROUP', 'GROUP')
WHERE name = 'test8';
UPDATE heimdal.entities
SET (owner_name, owner_realm, owner_container, owner_entity_type)
  = ('testgroup3', 'FOO.EXAMPLE', 'GROUP', 'GROUP')
WHERE name = 'test9';
$$);
SELECT 'test principal flags',
       test.test_insert_PKs('test principal flags', $$
INSERT INTO heimdal.principal_flags (name, realm, flag)
VALUES ('test0', 'FOO.EXAMPLE', 'CLIENT'),
       ('test0', 'FOO.EXAMPLE', 'INITIAL'),
       ('test1', 'FOO.EXAMPLE', 'CLIENT'),
       ('test1', 'FOO.EXAMPLE', 'INITIAL'),
       ('test2', 'FOO.EXAMPLE', 'CLIENT'),
       ('test2', 'FOO.EXAMPLE', 'INITIAL'),
       ('test3', 'FOO.EXAMPLE', 'CLIENT'),
       ('test3', 'FOO.EXAMPLE', 'INITIAL'),
       ('test4', 'FOO.EXAMPLE', 'CLIENT'),
       ('test4', 'FOO.EXAMPLE', 'INITIAL'),
       ('test5', 'FOO.EXAMPLE', 'CLIENT'),
       ('test5', 'FOO.EXAMPLE', 'INITIAL'),
       ('test6', 'FOO.EXAMPLE', 'CLIENT'),
       ('test6', 'FOO.EXAMPLE', 'INITIAL'),
       ('test7', 'FOO.EXAMPLE', 'CLIENT'),
       ('test7', 'FOO.EXAMPLE', 'INITIAL'),
       ('test8', 'FOO.EXAMPLE', 'CLIENT'),
       ('test8', 'FOO.EXAMPLE', 'INITIAL'),
       ('test9', 'FOO.EXAMPLE', 'CLIENT'),
       ('test9', 'FOO.EXAMPLE', 'INITIAL'),
       ('test0', 'BAR.EXAMPLE', 'CLIENT'),
       ('test0', 'BAR.EXAMPLE', 'INITIAL');
$$);
SELECT 'test principal etypes',
       test.test_insert_PKs('test principal etypes', $$
INSERT INTO heimdal.principal_etypes (name, realm, etype)
VALUES ('test0', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test0', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test1', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test1', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test2', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test2', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test3', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test3', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test4', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test4', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test5', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test5', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test6', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test6', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test7', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test7', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test8', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test8', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test9', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test9', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test0', 'BAR.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test0', 'BAR.EXAMPLE', 'aes256-cts-hmac-sha1-96');
$$);
SELECT 'test members',
       test.test_insert_PKs('test members', $$
INSERT INTO heimdal.members (parent_name, parent_container, parent_realm, member_name, member_container, member_realm)
VALUES ('testgroup0', 'GROUP', 'FOO.EXAMPLE', 'user0', 'USER', 'FOO.EXAMPLE'),
       ('testgroup0', 'GROUP', 'FOO.EXAMPLE', 'user1', 'USER', 'FOO.EXAMPLE'),
       ('testgroup0', 'GROUP', 'FOO.EXAMPLE', 'user2', 'USER', 'FOO.EXAMPLE'),
       ('testgroup0', 'GROUP', 'FOO.EXAMPLE', 'user3', 'USER', 'FOO.EXAMPLE'),
       ('testgroup1', 'GROUP', 'FOO.EXAMPLE', 'user1', 'USER', 'FOO.EXAMPLE'),
       ('testgroup2', 'GROUP', 'FOO.EXAMPLE', 'user4', 'USER', 'FOO.EXAMPLE'),
       ('testgroup2', 'GROUP', 'FOO.EXAMPLE', 'user5', 'USER', 'FOO.EXAMPLE'),
       ('testgroup3', 'GROUP', 'FOO.EXAMPLE', 'testgroup1', 'GROUP', 'FOO.EXAMPLE'),
       ('testgroup4', 'GROUP', 'FOO.EXAMPLE', 'testgroup3', 'GROUP', 'FOO.EXAMPLE'),
       ('testgroup5', 'GROUP', 'FOO.EXAMPLE', 'testgroup6', 'GROUP', 'FOO.EXAMPLE'),
       ('testgroup6', 'GROUP', 'FOO.EXAMPLE', 'testgroup4', 'GROUP', 'FOO.EXAMPLE'),
       ('testgroup5', 'GROUP', 'FOO.EXAMPLE', 'testgroup1', 'GROUP', 'FOO.EXAMPLE'),
       ('testgroup6', 'GROUP', 'FOO.EXAMPLE', 'testgroup0', 'GROUP', 'FOO.EXAMPLE');
$$);

DROP TABLE temp_tc;
CREATE TEMP TABLE temp_tc AS
SELECT *
FROM heimdal.tc;

SELECT 'test members 2',
       test.test_insert_PKs('test members 2', $$
INSERT INTO heimdal.members (parent_name, parent_container, parent_realm, member_name, member_container, member_realm)
VALUES ('testgroup3', 'GROUP', 'FOO.EXAMPLE', 'testgroup2', 'GROUP', 'FOO.EXAMPLE');
$$);

DROP TABLE temp_tc2;
CREATE TEMP TABLE temp_tc2 AS
SELECT *
FROM heimdal.tc;

SELECT 'test key creation',
       test.test_insert_PKs('test key creation', $$
INSERT INTO heimdal.keys (name, container, realm, kvno, ktype, etype, key)
VALUES ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0000'),
       ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0100'),
       ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0110'),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0001'),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0101'),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0111'),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0002'),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0102'),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0112'),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0003'),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0103'),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0113'),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0004'),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0104'),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0114'),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0005'),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0105'),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0115'),
       ('test6', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0006'),
       ('test6', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0106'),
       ('test6', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0116'),
       ('test7', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0007'),
       ('test7', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0107'),
       ('test7', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0117'),
       ('test8', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0008'),
       ('test8', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0108'),
       ('test8', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0118'),
       ('test9', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0009'),
       ('test9', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0109'),
       ('test9', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0119'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x2000'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x2100'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x2110'),
       ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1000'),
       ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1100'),
       ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1110'),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1001'),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1101'),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1111'),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1002'),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1102'),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1112'),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1003'),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1103'),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x1113'),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1004'),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1104'),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1114'),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1005'),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1105'),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1115'),
       ('test6', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1006'),
       ('test6', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1106'),
       ('test6', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1116'),
       ('test7', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1007'),
       ('test7', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1107'),
       ('test7', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1117'),
       ('test8', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1008'),
       ('test8', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1108'),
       ('test8', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1118'),
       ('test9', 'PRINCIPAL', 'FOO.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1009'),
       ('test9', 'PRINCIPAL', 'FOO.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1109'),
       ('test9', 'PRINCIPAL', 'FOO.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1119'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x3000'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x3100'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x3110');
$$);
SELECT 'test update principal kvno',
       test.expect_success('test update principal kvno', $$
UPDATE heimdal.principals SET kvno = 3;
$$);
SELECT 'test password_history',
       test.test_insert_PKs('test password_history', $$
INSERT INTO heimdal.password_history (name, container, realm, etype, digest, digest_alg, mkvno)
VALUES ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x8265', 'sha1', 1),
       ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x8275', 'sha1', 2),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x1740', 'sha1', 1),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x7365', 'sha1', 2),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x0275', 'sha1', 1),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x3558', 'sha1', 2),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x9933', 'sha1', 1),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x1737', 'sha1', 2),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x0998', 'sha1', 1),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x1754', 'sha1', 2),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x1758', 'sha1', 1),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x2431', 'sha1', 2),
       ('test6', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x0786', 'sha1', 1),
       ('test6', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x4298', 'sha1', 2),
       ('test7', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x1446', 'sha1', 1),
       ('test7', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x6533', 'sha1', 2),
       ('test8', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x5411', 'sha1', 1),
       ('test8', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x7441', 'sha1', 2),
       ('test9', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x8254', 'sha1', 1),
       ('test9', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x9254', 'sha1', 2),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x9763', 'sha1', 1),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x7125', 'sha1', 2);
$$);
SELECT 'test alias creation',
       test.test_insert_PKs('test alias creation', $$
INSERT INTO heimdal.aliases (name, realm, alias_name, alias_realm)
VALUES ('test0', 'FOO.EXAMPLE', 'alias0',  'FOO.EXAMPLE'),
       ('test0', 'FOO.EXAMPLE', 'alias10', 'FOO.EXAMPLE'),
       ('test1', 'FOO.EXAMPLE', 'alias1',  'FOO.EXAMPLE'),
       ('test1', 'FOO.EXAMPLE', 'alias11', 'FOO.EXAMPLE'),
       ('test2', 'FOO.EXAMPLE', 'alias2',  'FOO.EXAMPLE'),
       ('test2', 'FOO.EXAMPLE', 'alias12', 'FOO.EXAMPLE'),
       ('test3', 'FOO.EXAMPLE', 'alias3',  'FOO.EXAMPLE'),
       ('test3', 'FOO.EXAMPLE', 'alias13', 'FOO.EXAMPLE'),
       ('test4', 'FOO.EXAMPLE', 'alias4',  'FOO.EXAMPLE'),
       ('test4', 'FOO.EXAMPLE', 'alias14', 'FOO.EXAMPLE'),
       ('test5', 'FOO.EXAMPLE', 'alias5',  'FOO.EXAMPLE'),
       ('test5', 'FOO.EXAMPLE', 'alias15', 'FOO.EXAMPLE'),
       ('test6', 'FOO.EXAMPLE', 'alias6',  'FOO.EXAMPLE'),
       ('test6', 'FOO.EXAMPLE', 'alias16', 'FOO.EXAMPLE'),
       ('test7', 'FOO.EXAMPLE', 'alias7',  'FOO.EXAMPLE'),
       ('test7', 'FOO.EXAMPLE', 'alias17', 'FOO.EXAMPLE'),
       ('test8', 'FOO.EXAMPLE', 'alias8',  'FOO.EXAMPLE'),
       ('test8', 'FOO.EXAMPLE', 'alias18', 'FOO.EXAMPLE'),
       ('test9', 'FOO.EXAMPLE', 'alias9',  'FOO.EXAMPLE'),
       ('test9', 'FOO.EXAMPLE', 'alias19', 'FOO.EXAMPLE'),
       ('test0', 'BAR.EXAMPLE', 'alias0',  'BAR.EXAMPLE'),
       ('test0', 'BAR.EXAMPLE', 'alias10', 'BAR.EXAMPLE');
$$);
-- Use SELECTs here to check for incorrect results
SELECT 'test hdb views',
       test.expect_success('test hdb views', $$
SELECT * FROM hdb.modified_info WHERE name LIKE 'test0%';
SELECT * FROM hdb.key WHERE name LIKE 'test0%';
SELECT * FROM hdb.keyset WHERE name LIKE 'test0%';
SELECT * FROM hdb.keysets WHERE name LIKE 'test0%';
SELECT * FROM hdb.aliases WHERE name LIKE 'test0%';
SELECT * FROM hdb.pwh1 WHERE name LIKE 'test0%';
SELECT * FROM hdb.pwh WHERE name LIKE 'test0%';
SELECT * FROM hdb.flags WHERE name LIKE 'test0%';
SELECT * FROM hdb.etypes WHERE name LIKE 'test0%';
SELECT * FROM hdb.hdb WHERE name LIKE 'test0%';
$$);

SELECT 'test delete from heimdal members',
       test.check_against_table('test delete from heimdal members', 'pg_temp', 'temp_tc', 'heimdal', 'tc', $$
DELETE FROM heimdal.members
WHERE parent_name = 'testgroup3' AND
      member_name = 'testgroup2';
$$);

SELECT 'test insert into heimdal members',
       test.check_against_table('test insert into heimdal members', 'pg_temp', 'temp_tc2', 'heimdal', 'tc', $$
INSERT INTO heimdal.members (parent_name, parent_container, parent_realm, member_name, member_container, member_realm)
VALUES ('testgroup3', 'GROUP', 'FOO.EXAMPLE', 'testgroup2', 'GROUP', 'FOO.EXAMPLE');
$$);

SELECT 'test members 3',
       test.test_insert_PKs('test members 3', $$
INSERT INTO heimdal.members (parent_name, parent_container, parent_realm, member_name, member_container, member_realm)
VALUES ('testgroup8', 'GROUP', 'FOO.EXAMPLE', 'testgroup9', 'GROUP', 'FOO.EXAMPLE'),
       ('testgroup9', 'GROUP', 'FOO.EXAMPLE', 'testgroup7', 'GROUP', 'FOO.EXAMPLE'),
       ('testgroup7', 'GROUP', 'FOO.EXAMPLE', 'testgroup4', 'GROUP', 'FOO.EXAMPLE'),
       ('testgroup6', 'GROUP', 'FOO.EXAMPLE', 'testgroup8', 'GROUP', 'FOO.EXAMPLE'),
       ('testgroup9', 'GROUP', 'FOO.EXAMPLE', 'testgroup5', 'GROUP', 'FOO.EXAMPLE');
$$);

DROP TABLE temp_tc3;
CREATE TEMP TABLE temp_tc3 AS
SELECT *
FROM heimdal.tc;

SELECT 'test members 4',
       test.test_insert_PKs('test members 4', $$
INSERT INTO heimdal.members (parent_name, parent_container, parent_realm, member_name, member_container, member_realm)
VALUES ('testgroup7', 'GROUP', 'FOO.EXAMPLE', 'testgroup8', 'GROUP', 'FOO.EXAMPLE');
$$);

DROP TABLE temp_tc4;
CREATE TEMP TABLE temp_tc4 AS
SELECT *
FROM heimdal.tc;

SELECT 'test delete from heimdal members break 3-loop',
       test.check_against_table('test delete from heimdal members break 3-loop', 'pg_temp', 'temp_tc3', 'heimdal', 'tc', $$
DELETE FROM heimdal.members
WHERE parent_name = 'testgroup7' AND
      member_name = 'testgroup8';
$$);

SELECT 'test insert into heimdal members make 3-loop',
       test.check_against_table('test insert into heimdal members make 3-loop', 'pg_temp', 'temp_tc4', 'heimdal', 'tc', $$
INSERT INTO heimdal.members (parent_name, parent_container, parent_realm, member_name, member_container, member_realm)
VALUES ('testgroup7', 'GROUP', 'FOO.EXAMPLE', 'testgroup8', 'GROUP', 'FOO.EXAMPLE');
$$);

DROP TABLE IF EXISTS x;
CREATE TEMP TABLE x AS
SELECT * FROM hdb.hdb WHERE name LIKE 'test0%' AND realm LIKE 'FOO%';

SELECT 'test jsonb_set',
       test.expect_success('test jsonb_set', $$
UPDATE x SET name = 'testfoo', realm = 'BAR.EXAMPLE',
             entry = jsonb_set(jsonb_set(entry::jsonb, '{"name"}'::TEXT[], to_jsonb('testfoo'::TEXT))::jsonb,
                               '{"realm"}'::TEXT[], to_jsonb('BAR.EXAMPLE'::TEXT));

UPDATE x SET entry = jsonb_set(entry::jsonb, '{"aliases",0,"alias_name"}'::TEXT[], to_jsonb('aliasfoo'::TEXT));
UPDATE x SET entry = jsonb_set(entry::jsonb, '{"aliases",1,"alias_name"}'::TEXT[], to_jsonb('aliasfoo2'::TEXT));
$$);

SELECT 'test verb user->label 0'
        test.expect_true('test verb user->label 0', $$
heimdal.chk('user0', 'FOO.EXAMPLE', 'USER', 'WRITE', 'FOO.EXAMPLE', 'VERB', 'testlabel0', 'FOO.EXAMPLE', 'LABEL')
$$);

SELECT 'test verb user->label 1'
        test.expect_true('test verb user->label 1', $$
heimdal.chk('user0', 'FOO.EXAMPLE', 'USER', 'READ', 'FOO.EXAMPLE', 'VERB', 'testlabel0', 'FOO.EXAMPLE', 'LABEL')
$$);

SELECT 'test verb user->label 2'
        test.expect_false('test verb user->label 2', $$
heimdal.chk('user2', 'FOO.EXAMPLE', 'USER', 'WRITE', 'FOO.EXAMPLE', 'VERB', 'testlabel0', 'FOO.EXAMPLE', 'LABEL')
$$);

SELECT 'test verb user->label 3'
        test.expect_true('test verb user->label 3', $$
heimdal.chk('user2', 'FOO.EXAMPLE', 'USER', 'READ', 'FOO.EXAMPLE', 'VERB', 'testlabel0', 'FOO.EXAMPLE', 'LABEL')
$$);

SELECT 'test verb user->label 4'
        test.expect_true('test verb user->label 4', $$
heimdal.chk('user1', 'FOO.EXAMPLE', 'USER', 'READ', 'FOO.EXAMPLE', 'VERB', 'testlabel2', 'FOO.EXAMPLE', 'LABEL')
$$);

SELECT 'test ownership user->user',
        test.expect_true('test ownership user->user', $$
heimdal.chk('user0', 'FOO.EXAMPLE', 'USER', 'user0', 'FOO.EXAMPLE', 'USER')
$$);

SELECT 'test ownership user->principal',
        test.expect_true('test ownership user->principal', $$
heimdal.chk('user0', 'FOO.EXAMPLE', 'USER', 'test0', 'FOO.EXAMPLE', 'PRINCIPAL')
$$);

SELECT 'test ownership user->principal via membership 2 levels',
        test.expect_true('test ownership user->principal via membership 2 levels', $$
heimdal.chk('user1', 'FOO.EXAMPLE', 'USER', 'test9', 'FOO.EXAMPLE', 'PRINCIPAL')
$$);

SELECT 'test ownership user->principal not owned',
        test.expect_false('test ownership user->principal not owned', $$
heimdal.chk('user0', 'FOO.EXAMPLE', 'USER', 'test9', 'FOO.EXAMPLE', 'PRINCIPAL')
$$);

SELECT 'test ownership group->principal not owned',
        test.expect_false('test ownership group->principal not owned', $$
heimdal.chk('testgroup0', 'FOO.EXAMPLE', 'GROUP', 'test9', 'FOO.EXAMPLE', 'PRINCIPAL')
$$);

SELECT 'test ownership user_not_exists->principal',
        test.expect_false('test ownership user_not_exists->principal', $$
heimdal.chk('user_not_exists', 'FOO.EXAMPLE', 'USER', 'test9', 'FOO.EXAMPLE', 'PRINCIPAL')
$$);

SELECT 'test ownership user->principal_not_exists',
        test.expect_false('test ownership user->principal_not_exists', $$
heimdal.chk('user0', 'FOO.EXAMPLE', 'USER', 'principal_not_exists', 'FOO.EXAMPLE', 'PRINCIPAL')
$$);

SELECT 'test ownership user_not_exists->principal_not_exists',
        test.expect_false('test ownership user_not_exists->principal_not_exists', $$
heimdal.chk('user_not_exists', 'FOO.EXAMPLE', 'USER', 'principal_not_exists', 'FOO.EXAMPLE', 'PRINCIPAL')
$$);

SELECT 'test hdb insert',
       test.test_insert_PKs('test hdb insert', $$
INSERT INTO hdb.hdb
    (name, realm, entry)
SELECT name, realm, entry FROM x;
$$);

SELECT 'test hdb update valid_end',
       test.check_hdb_hdb_jsonb_update('test hdb update valid_end', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"valid_end"}'::TEXT[],
                                                 to_jsonb(('2019-06-17 19:34:58.514858'::TIMESTAMP WITHOUT TIME ZONE
                                                           + '50 years'::INTERVAL)::TEXT))
$$);

SELECT 'test hdb update pw_end',
       test.check_hdb_hdb_jsonb_update('test hdb update pw_end', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"pw_end"}'::TEXT[],
                                                 to_jsonb(('2019-06-17 19:34:58.514858'::TIMESTAMP WITHOUT TIME ZONE
                                                           + '50 years'::INTERVAL)::TEXT))
$$);

SELECT 'test hdb update last_pw_change',
       test.check_hdb_hdb_jsonb_update('test hdb update last_pw_change', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"last_pw_change"}'::TEXT[],
                                                 to_jsonb(('2019-06-17 19:34:58.514858'::TIMESTAMP WITHOUT TIME ZONE)::TEXT))
$$);

SELECT 'test hdb update max_life',
       test.check_hdb_hdb_jsonb_update('test hdb update max_life', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"max_life"}'::TEXT[], to_jsonb('23 hours'::INTERVAL))
$$);

SELECT 'test hdb update max_renew',
       test.check_hdb_hdb_jsonb_update('test hdb update max_renew', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"max_renew"}'::TEXT[], to_jsonb('69 days'::INTERVAL))
$$);

SELECT 'test hdb update password',
       test.check_hdb_hdb_jsonb_update('test hdb update password', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"password"}'::TEXT[], to_jsonb('foobarbaz'::TEXT))
$$);

SELECT jsonb_set(entry::jsonb, '{"flags"}'::text[], jsonb_build_array('CLIENT','SERVER'))
FROM hdb.hdb
WHERE name = 'test4';

SELECT 'test hdb update flags',
       test.check_hdb_hdb_jsonb_update('test hdb update flags', 'test4', 'FOO.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"flags"}'::text[], jsonb_build_array('SERVER','CLIENT'))
$$);

SELECT entry
FROM hdb.hdb
WHERE name = 'test4';

SELECT 'test hdb update etypes',
       test.check_hdb_hdb_jsonb_update('test hdb update etypes', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"etypes"}'::text[],
                                                 jsonb_build_array('aes128-cts-hmac-sha1-96','aes256-cts-hmac-sha1-96',
                                                                   'aes128-cts-hmac-sha256','aes256-cts-hmac-sha512'))
$$);

SELECT 'test hdb update aliases',
       test.check_hdb_hdb_jsonb_update('test hdb update aliases', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"aliases"}'::TEXT[],
                                                 jsonb_build_array(
                                                    jsonb_build_object('alias_name','kahlui'::TEXT,
                                                                       'alias_realm','BAR.EXAMPLE'::TEXT),
                                                    jsonb_build_object('alias_name','kentobento'::TEXT,
                                                                       'alias_realm','BAR.EXAMPLE'::TEXT)))
$$);

SELECT jsonb_set(entry::jsonb, '{"password_history",0}'::TEXT[],
                                                 jsonb_build_object('mkvno',69::BIGINT,
                                                                    'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                                    'digest_alg','sha1'::TEXT,
                                                                    'digest',encode(E'\\x6626'::bytea, 'base64'),
                                                                    'set_at','1970-01-01 00:00:00'::TEXT))
FROM hdb.hdb 
WHERE name = 'test0' AND realm LIKE 'B%';

SELECT 'test hdb update password_history',
       test.check_hdb_hdb_jsonb_update('test hdb update password_history', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"password_history",0}'::TEXT[],
                                                 jsonb_build_object('mkvno',69::BIGINT,
                                                                    'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                                    'digest_alg','sha1'::TEXT,
                                                                    'digest',encode(E'\\x6626', 'base64'),
                                                                    'set_at','1970-01-01 00:00:00'::TEXT))
$$);

SELECT entry
FROM hdb.hdb
WHERE name = 'test0' AND realm LIKE 'B%';

SELECT jsonb_set(entry::jsonb, '{"password_history",1,"digest"}'::TEXT[],
                                                 to_jsonb(encode(E'\\x7777', 'base64')))
FROM hdb.hdb
WHERE name = 'test0' AND realm LIKE 'B%';

SELECT 'test hdb update password_history digest',
       test.check_hdb_hdb_jsonb_update('test hdb update password_history digest', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"password_history",1,"digest"}'::TEXT[],
                                                 to_jsonb(encode(E'\\x7777', 'base64')))
$$);

SELECT entry
FROM hdb.hdb
WHERE name = 'test0' AND realm LIKE 'B%';

SELECT jsonb_set(entry::jsonb, '{"keysets",0}'::TEXT[],
                                                 jsonb_build_array(
                                                    jsonb_build_object(
                                                           'key',encode(E'\\x2222','base64'),
                                                           'kvno',5::BIGINT,
                                                           'salt',NULL,
                                                           'set_at','1970-01-01 00:00:00'::TEXT,
                                                           'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                           'ktype','SYMMETRIC'::TEXT,
                                                           'mkvno',NULL)))
FROM hdb.hdb
WHERE name = 'test0' AND realm LIKE 'B%';

SELECT 'test hdb update keysets',
       test.check_hdb_hdb_jsonb_update('test hdb update keysets', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"keysets",0}'::TEXT[],
                                                 jsonb_build_array(
                                                    jsonb_build_object(
                                                           'key',encode(E'\\x2222','base64'),
                                                           'kvno',5::BIGINT,
                                                           'salt',NULL,
                                                           'set_at','1970-01-01 00:00:00'::TEXT,
                                                           'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                           'ktype','SYMMETRIC'::TEXT,
                                                           'mkvno',NULL)))
$$);

SELECT entry
FROM hdb.hdb
WHERE name = 'test0' AND realm LIKE 'B%';
/*
SELECT jsonb_set(entry::jsonb, '{"keys"}'::TEXT[],
                                                 jsonb_build_array(jsonb_build_object(
                                                           'key',encode(E'\\x1234','base64'),
                                                           'kvno',1::BIGINT,
                                                           'salt',NULL,
                                                           'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                           'ktype','SYMMETRIC'::TEXT,
                                                           'mkvno',NULL)))
FROM hdb.hdb
WHERE name = 'test0' AND realm LIKE 'B%';

SELECT 'test hdb update keys bad data',
       test.check_hdb_hdb_jsonb_update('test hdb update keys bad data', 'test0', 'BAR.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"keys"}'::TEXT[],
                                                 jsonb_build_array(jsonb_build_object(
                                                           'key',encode(E'\\x1234','base64'),
                                                           'kvno',1::BIGINT,
                                                           'salt',NULL,
                                                           'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                           'ktype','SYMMETRIC'::TEXT,
                                                           'mkvno',NULL)))
$$); *//* This one we actually expect to fail as the input data is kind of bad (kvno of new keys != kvno of principal) -L */
/*
SELECT entry
FROM hdb.hdb
WHERE name = 'test0' AND realm LIKE 'B%';
*/
SELECT jsonb_set(entry::jsonb, '{"keys"}'::TEXT[],
                                                 jsonb_build_array(jsonb_build_object(
                                                           'key',encode(E'\\x1234','base64'),
                                                           'kvno',3::BIGINT,
                                                           'salt',NULL,
                                                           'set_at','1970-01-01 00:00:00'::TEXT,
                                                           'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                           'ktype','SYMMETRIC'::TEXT,
                                                           'mkvno',NULL)))
FROM hdb.hdb
WHERE name = 'test3';

SELECT 'test hdb update keys',
       test.check_hdb_hdb_jsonb_update('test hdb update keys', 'test3', 'FOO.EXAMPLE', $$
                                       jsonb_set(entry::jsonb, '{"keys"}'::TEXT[],
                                                 jsonb_build_array(jsonb_build_object(
                                                           'key',encode(E'\\x1234','base64'),
                                                           'kvno',3::BIGINT,
                                                           'salt',NULL,
                                                           'set_at','1970-01-01 00:00:00'::TEXT,
                                                           'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                           'ktype','SYMMETRIC'::TEXT,
                                                           'mkvno',NULL)))
$$); /* This we want to succeed -L */

SELECT entry
FROM hdb.hdb
WHERE name = 'test3';

DELETE FROM hdb.hdb WHERE name = 'testfoo';

--SELECT * FROM hdb.hdb WHERE name LIKE 'test0%';
DROP TABLE IF EXISTS y;
CREATE TEMP TABLE y AS 
SELECT * FROM hdb.hdb WHERE name LIKE 'test0%' AND realm LIKE 'FOO%';

SELECT CASE count(*) WHEN 0 THEN 'ALL TESTS PASS' ELSE 'SOME TESTS FAIL' END
FROM test.tests
WHERE NOT pass;

/*
SELECT jsonb_set(e.entry::jsonb, '{"keys"}'::TEXT[],
                      jsonb_build_array(jsonb_build_object('key',E'\\x1234'::TEXT,
                                                           'kvno',1::BIGINT,
                                                           'salt',NULL,
                                                           'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                           'ktype','SYMMETRIC'::TEXT,
                                                           'mkvno',NULL))) FROM hdb.hdb AS e
WHERE name LIKE 'test0%';
 */
-- Use INSERT, UPDATE, DELETE on hdb views to test triggers
-- Use more SELECTs to check that updates took

SELECT set_config('hdb.test','false',true);
