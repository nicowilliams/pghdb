
-- DELETE past test data here
DELETE FROM heimdal.entities
WHERE name like 'test%';
-- INSERT test data here
INSERT INTO heimdal.entities (name, namespace, entity_type)
VALUES ('test0@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test1@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test2@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test3@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test4@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('test5@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('testgroup0', 'GROUP', 'GROUP'),
       ('testgroup1', 'GROUP', 'GROUP'),
       ('testgroup2', 'GROUP', 'GROUP');
INSERT INTO heimdal.principals (name, password)
VALUES ('test0@FOO.EXAMPLE', 'password-00'),
       ('test1@FOO.EXAMPLE', 'password-01'),
       ('test2@FOO.EXAMPLE', 'password-02'),
       ('test3@FOO.EXAMPLE', 'password-03'),
       ('test4@FOO.EXAMPLE', 'password-04'),
       ('test5@FOO.EXAMPLE', 'password-05');
INSERT INTO heimdal.principal_flags (name, flag)
VALUES ('test0@FOO.EXAMPLE', 'CLIENT'),
       ('test1@FOO.EXAMPLE', 'CLIENT'),
       ('test2@FOO.EXAMPLE', 'CLIENT'),
       ('test3@FOO.EXAMPLE', 'CLIENT'),
       ('test4@FOO.EXAMPLE', 'CLIENT'),
       ('test5@FOO.EXAMPLE', 'CLIENT');
INSERT INTO heimdal.principal_etypes (name, etype)
VALUES ('test0@FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test1@FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test2@FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test3@FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('test4@FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('test5@FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96');
INSERT INTO heimdal.members (container_name, container_namespace, member_name, member_namespace)
VALUES ('testgroup0', 'GROUP', 'u0@FOO.EXAMPLE', 'PRINCIPAL'),
       ('testgroup0', 'GROUP', 'u1@FOO.EXAMPLE', 'PRINCIPAL'),
       ('testgroup0', 'GROUP', 'u2@FOO.EXAMPLE', 'PRINCIPAL'),
       ('testgroup0', 'GROUP', 'u3@FOO.EXAMPLE', 'PRINCIPAL'),
       ('testgroup1', 'GROUP', 'u1@FOO.EXAMPLE', 'PRINCIPAL'),
       ('testgroup2', 'GROUP', 'u4@FOO.EXAMPLE', 'PRINCIPAL'),
       ('testgroup2', 'GROUP', 'u5@FOO.EXAMPLE', 'PRINCIPAL');
INSERT INTO heimdal.keys (name, namespace, kvno, ktype, etype, key)
VALUES ('test0@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0000'),
       ('test0@FOO.EXAMPLE', 'PRINCIPAL', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0100'),
       ('test1@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0001'),
       ('test2@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0002'),
       ('test3@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0003'),
       ('test4@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0004'),
       ('test5@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0005');
UPDATE heimdal.principals SET kvno = 2
WHERE name = 'test0@FOO.EXAMPLE';
INSERT INTO heimdal.password_history (name, namespace, etype, digest, digest_alg, mkvno)
VALUES ('test5@FOO.EXAMPLE', 'PRINCIPAL', 'aes128-cts-hmac-sha1-96', E'\\x0005', 'sha1', 1);
-- Use SELECTs here to check for incorrect results
SELECT name, entry FROM hdb.hdb WHERE name LIKE 'test%';
-- Use INSERT, UPDATE, DELETE on hdb views to test triggers
-- Use more SELECTs to check that updates took
