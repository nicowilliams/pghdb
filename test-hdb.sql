
\set ON_ERROR_STOP 1

DROP TABLE IF EXISTS x;
DROP TABLE IF EXISTS y;

-- DELETE past test data here
DELETE FROM heimdal.entities
WHERE name like 'test%';
-- INSERT test data here
INSERT INTO heimdal.entities (name, realm, container, entity_type)
VALUES ('test0', 'FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test1', 'FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test2', 'FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test3', 'FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test4', 'FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test5', 'FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test0', 'BAR.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('testgroup0', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup1', 'FOO.EXAMPLE', 'GROUP', 'GROUP'),
       ('testgroup2', 'FOO.EXAMPLE', 'GROUP', 'GROUP');
INSERT INTO heimdal.principals (name, realm, password)
VALUES ('test0', 'FOO.EXAMPLE', 'password-00'),
       ('test1', 'FOO.EXAMPLE', 'password-01'),
       ('test2', 'FOO.EXAMPLE', 'password-02'),
       ('test3', 'FOO.EXAMPLE', 'password-03'),
       ('test4', 'FOO.EXAMPLE', 'password-04'),
       ('test5', 'FOO.EXAMPLE', 'password-05'),
       ('test0', 'BAR.EXAMPLE', 'password-06');
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
       ('test0', 'BAR.EXAMPLE', 'CLIENT'),
       ('test0', 'BAR.EXAMPLE', 'INITIAL');
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
       ('test0', 'BAR.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test0', 'BAR.EXAMPLE', 'aes256-cts-hmac-sha1-96');
INSERT INTO heimdal.members (parent_name, parent_container, parent_realm, member_name, member_container, member_realm)
VALUES ('testgroup0', 'GROUP', 'FOO.EXAMPLE', 'test0', 'PRINCIPAL', 'FOO.EXAMPLE'),
       ('testgroup0', 'GROUP', 'FOO.EXAMPLE', 'test1', 'PRINCIPAL', 'FOO.EXAMPLE'),
       ('testgroup0', 'GROUP', 'FOO.EXAMPLE', 'test2', 'PRINCIPAL', 'FOO.EXAMPLE'),
       ('testgroup0', 'GROUP', 'FOO.EXAMPLE', 'test3', 'PRINCIPAL', 'FOO.EXAMPLE'),
       ('testgroup1', 'GROUP', 'FOO.EXAMPLE', 'test1', 'PRINCIPAL', 'FOO.EXAMPLE'),
       ('testgroup2', 'GROUP', 'FOO.EXAMPLE', 'test4', 'PRINCIPAL', 'FOO.EXAMPLE'),
       ('testgroup2', 'GROUP', 'FOO.EXAMPLE', 'test5', 'PRINCIPAL', 'FOO.EXAMPLE');
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
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0006'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 2, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0106'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 3, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0116'),
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
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1006'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1106'),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 3, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x1116');
UPDATE heimdal.principals SET kvno = 3;
INSERT INTO heimdal.password_history (name, container, realm, etype, digest, digest_alg, mkvno)
VALUES ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x0005', 'sha1', 1),
       ('test0', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x0005', 'sha1', 2),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x0005', 'sha1', 1),
       ('test1', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x0005', 'sha1', 2),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x0005', 'sha1', 1),
       ('test2', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x0005', 'sha1', 2),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x0005', 'sha1', 1),
       ('test3', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96', E'\\x0005', 'sha1', 2),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x0005', 'sha1', 1),
       ('test4', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x0005', 'sha1', 2),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x0005', 'sha1', 1),
       ('test5', 'PRINCIPAL', 'FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x0005', 'sha1', 2),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x0005', 'sha1', 1),
       ('test0', 'PRINCIPAL', 'BAR.EXAMPLE', 'aes256-cts-hmac-sha1-96', E'\\x0005', 'sha1', 2);
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
       ('test0', 'BAR.EXAMPLE', 'alias0',  'BAR.EXAMPLE'),
       ('test0', 'BAR.EXAMPLE', 'alias10', 'BAR.EXAMPLE');
-- Use SELECTs here to check for incorrect results
/*
SELECT * FROM hdb.modified_info WHERE name LIKE 'test0%';
SELECT * FROM hdb.key WHERE name LIKE 'test0%';
SELECT * FROM hdb.keyset WHERE name LIKE 'test0%';
SELECT * FROM hdb.keysets WHERE name LIKE 'test0%';
SELECT * FROM hdb.aliases WHERE name LIKE 'test0%';
SELECT * FROM hdb.pwh1 WHERE name LIKE 'test0%';
SELECT * FROM hdb.pwh WHERE name LIKE 'test0%';
SELECT * FROM hdb.flags WHERE name LIKE 'test0%';
SELECT * FROM hdb.etypes WHERE name LIKE 'test0%';
 */
--SELECT * FROM hdb.hdb WHERE name LIKE 'test0%';
CREATE TEMP TABLE x AS
SELECT * FROM hdb.hdb WHERE name LIKE 'test0%' AND realm LIKE 'FOO%';

UPDATE x SET display_name = 'testfoo@BAR.EXAMPLE', name = 'testfoo', realm = 'BAR.EXAMPLE',
             entry = jsonb_set(jsonb_set(entry::jsonb, '{"name"}'::TEXT[], to_jsonb('testfoo'::TEXT))::jsonb,
                               '{"realm"}'::TEXT[], to_jsonb('BAR.EXAMPLE'::TEXT));

UPDATE x SET entry = jsonb_set(entry::jsonb, '{"aliases",0,"alias_name"}'::TEXT[], to_jsonb('aliasfoo'::TEXT));
UPDATE x SET entry = jsonb_set(entry::jsonb, '{"aliases",1,"alias_name"}'::TEXT[], to_jsonb('aliasfoo2'::TEXT));

INSERT INTO hdb.hdb
    (name, realm, entry)
SELECT name, realm, entry FROM x;

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"valid_end"}'::TEXT[], to_jsonb(current_timestamp + '50 years'::INTERVAL))
WHERE name LIKE 'test0%';

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"pw_end"}'::TEXT[], to_jsonb(current_timestamp + '50 years'::INTERVAL))
WHERE name LIKE 'test0%';

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"last_pw_change"}'::TEXT[], to_jsonb(current_timestamp - '2 years'::INTERVAL))
WHERE name LIKE 'test0%';

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"max_life"}'::TEXT[], to_jsonb('23 hours'::INTERVAL))
WHERE name LIKE 'test0%';

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"max_renew"}'::TEXT[], to_jsonb('69 days'::INTERVAL))
WHERE name LIKE 'test0%';

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"password"}'::TEXT[], to_jsonb('foobarbaz'::TEXT))
WHERE name LIKE 'test0%';

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"flags"}'::text[], jsonb_build_array('CLIENT','SERVER'))
WHERE name LIKE 'test0%';

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"etypes"}'::text[],
                                     jsonb_build_array('aes128-cts-hmac-sha1-96','aes256-cts-hmac-sha1-96',
                                                       'aes128-cts-hmac-sha256','aes256-cts-hmac-sha512'))
WHERE name LIKE 'test0%';

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"aliases"}'::TEXT[],
                      jsonb_build_array(jsonb_build_object('alias_name','kahlui'::TEXT,
                                         'alias_realm','BAR.EXAMPLE'::TEXT),jsonb_build_object('alias_name','kentobento'::TEXT,
                                         'alias_realm','BAR.EXAMPLE'::TEXT)))
WHERE name LIKE 'test0%' AND realm LIKE 'B%';

SELECT * from heimdal.password_history;
UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"password_history",0,"digest"}'::TEXT[],
                      to_jsonb(encode(E'\\xA590','base64')))
WHERE name = 'test0' and realm like 'B%';;


UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"keysets",0}'::TEXT[],
                      jsonb_build_array(jsonb_build_object('key',E'\\x2222'::TEXT,
                                                           'kvno',5::BIGINT,
                                                           'salt',NULL,
                                                           'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                           'ktype','SYMMETRIC'::TEXT,
                                                           'mkvno',NULL)))
WHERE name LIKE 'test0%';

UPDATE hdb.hdb SET entry = jsonb_set(entry::jsonb, '{"keys"}'::TEXT[],
                      jsonb_build_array(jsonb_build_object('key',E'\\x1234'::TEXT,
                                                           'kvno',1::BIGINT,
                                                           'salt',NULL,
                                                           'etype','aes128-cts-hmac-sha1-96'::TEXT,
                                                           'ktype','SYMMETRIC'::TEXT,
                                                           'mkvno',NULL)))
WHERE name LIKE 'test0%';

DELETE FROM hdb.hdb WHERE name = 'testfoo';

--SELECT * FROM hdb.hdb WHERE name LIKE 'test0%';
CREATE TEMP TABLE y AS 
SELECT * FROM hdb.hdb WHERE name LIKE 'test0%' AND realm LIKE 'FOO%';

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
