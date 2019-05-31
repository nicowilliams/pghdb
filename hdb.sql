CREATE EXTENSION IF NOT EXISTS pgcrypto;
/*
 * Data tables go in the schema "heimdal".
 *
 * One database is required per-realm, as each database supports only one
 * realm.
 *
 * XXX Or, we could add a realm field to every relevant table, making their
 * primary keys multi-column keys, and memberships tables would have to have
 * multi-column references.  This would allow us to have one PG DB for all
 * realms that share a PG server (if desired).
 *
 * XXX If we want to do something like AD's global catalog, we could have a
 * separate schema to hold that.  For group memberships in that scheme we would
 * indeed need two-column foreign keys or else single-column with the realm
 * included in the value.  This argues for preparing to have multiple realms in
 * one DB, even if in actuality we wouldn't usually do that.
 *
 * XXX Rethink namespacing.  Perhaps implement something akin to UName*It
 * namespace rules.
 */
CREATE SCHEMA IF NOT EXISTS heimdal;
/*
 * Views for libhdb support go in the schema "hdb".
 *
 * These will permit generation of HDB entries as JSON which can then be
 * transcoded to the hdb_entry ASN.1 type using DER.
 *
 * These will also map INSERT/UPDATE/DELETE operations on the main hdb view
 * into corresponding INSERT/UPDATE/DELETE operations on heimdal tables.
 */
DROP SCHEMA IF EXISTS hdb CASCADE;
CREATE SCHEMA IF NOT EXISTS hdb;
/*
 * Views and functions for PostgREST APIs go in the schema "pgt".
 */
DROP SCHEMA IF EXISTS pgt;
CREATE SCHEMA IF NOT EXISTS pgt;

/* XXX Add allowed-to-delegate-to (not implemented in Heimdal anyways) */

CREATE SEQUENCE IF NOT EXISTS heimdal.ids;
CREATE TYPE heimdal.enc_type AS ENUM (
    'aes128-cts-hmac-sha1-96',
    'aes256-cts-hmac-sha1-96',
    'aes128-cts-hmac-sha256',
    'aes256-cts-hmac-sha512'
    /* non-standard enc_type names will also be included here */
    /* XXX populate moar */
);
CREATE TYPE heimdal.digest_type AS ENUM (
    'sha1',
    'sha256',
    'sha512'
    /* XXX add moar */
);
CREATE TYPE heimdal.key_type AS ENUM (
    'SYMMETRIC',    /* usable with SPAKE2 */
    'MAC',
    'SPAKE2',       /* symmetric reply key usable only with SPAKE2; enc_type will be enc_type */
    'SPAKE2+',      /* asymmetric verifier for SPAKE2+; enc_type will be enc_type */
    'PUBLIC',       /* public key; enc_type will be pubkey alg name and params */
    'PRIVATE',      /* private key to a public key cryptosystem; ditto */
    'PASSWORD'      /* enc_type will be codeset name (e.g., 'UTF-8') */,
    'CERT',         /* enc_type will be 'OPAQUE' */
    'CERT-HASH'     /* enc_type will be digest name; enc_type will be digest alg */
);
CREATE TYPE heimdal.namespaces AS ENUM (
    /*
     * So, what we're going for here is that we want to be able to support
     * distinct namespaces for several things for backwards compatibility
     * reasons.  But we could, in a better world, have just one namespace, and
     * then get rid of this ENUM type and all uses of it.
     *
     * XXX For now use only 'PRINCIPAL' -Nico
     */
    'PRINCIPAL', 'ROLE', 'GROUP', 'ACL', 'HOST'
);
CREATE TYPE heimdal.entity_types AS ENUM (
    /*
     * This is different from namespaces only because the latter are about
     * uniqueness, while this is about what kind of thing something is.
     *
     * If each kind of thing had a distinct namespace, then we'd not need this
     * ENUM type at all either.
     *
     * What we really want is to lose this ENUM, and for namespacing we should
     * build an extension that implements UName*It-style namespace rules.
     *
     * XXX For now use only 'USER'.
     */
    'UNKNOWN-PRINCIPAL-TYPE', 'USER', 'ROLE', 'GROUP', 'CLUSTER', 'ACL'
);
CREATE TYPE heimdal.princ_flags AS ENUM (
    'INITIAL', 'FORWARDABLE', 'PROXIABLE', 'RENEWABLE', 'POSTDATE', 'SERVER',
    'CLIENT', 'INVALID', 'REQUIRE-PREAUTH', 'CHANGE-PW', 'REQUIRE-HWAUTH',
    'OK-AS-DELEGATE', 'USER-TO-USER', 'IMMUTABLE', 'TRUSTED-FOR-DELEGATION',
    'ALLOW-KERBEROS4', 'ALLOW-DIGEST', 'LOCKED-OUT', 'REQUIRE-PWCHANGE',
    'DO-NOT-STORE'
);
CREATE TYPE heimdal.kerberos_name_type AS ENUM (
    -- Principal name-types.
    'UNKNOWN', 'USER', 'HOST-BASED-SERVICE', 'DOMAIN-BASED-SERVICE'
);
CREATE TYPE heimdal.pkix_name_type AS ENUM (
    'General', 'RFC822-SAN', 'PKINIT-SAN'
);
CREATE TABLE IF NOT EXISTS heimdal.common (
    valid_start         TIMESTAMP WITHOUT TIME ZONE DEFAULT (current_timestamp),
    valid_end           TIMESTAMP WITHOUT TIME ZONE DEFAULT (current_timestamp + '100 years'::interval),
    created_by          TEXT DEFAULT (current_user),
    created_at          TIMESTAMP WITHOUT TIME ZONE DEFAULT (current_timestamp),
    modified_by         TEXT DEFAULT (current_user),
    modified_at         TIMESTAMP WITHOUT TIME ZONE DEFAULT (current_timestamp),
    /* XXX Use an origin name or something better than IP:port */
    origin_addr         INET DEFAULT (inet_server_addr()),
    origin_port         INTEGER DEFAULT (inet_server_port()),
    origin_txid         BIGINT DEFAULT (txid_current())
);
/* Which enctypes are enabled or disabled globally */
CREATE TABLE IF NOT EXISTS heimdal.enc_types (
    ktype               heimdal.key_type,
    etype               heimdal.enc_type,
    enabled             BOOLEAN DEFAULT (TRUE),
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hecpk    PRIMARY KEY (ktype, etype)
);
INSERT INTO heimdal.enc_types (ktype, etype)
VALUES ('SYMMETRIC','aes128-cts-hmac-sha1-96'),
       ('SYMMETRIC','aes256-cts-hmac-sha1-96'),
       ('SYMMETRIC','aes128-cts-hmac-sha256'),
       ('SYMMETRIC','aes256-cts-hmac-sha512')
       /* XXX populate moar */
ON CONFLICT DO NOTHING;
/* Which digestypes are enabled or disabled globally */
CREATE TABLE IF NOT EXISTS heimdal.digest_types (
    ktype               heimdal.key_type,
    dtype               heimdal.digest_type,
    enabled             BOOLEAN DEFAULT (TRUE),
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hdtpk    PRIMARY KEY (ktype, dtype),
    CONSTRAINT hdtpk2   UNIQUE (dtype)
);


/* Duplicate inserts -L */
/* Remedied with digest types -L */

INSERT INTO heimdal.digest_types (ktype, dtype)
VALUES ('SYMMETRIC','sha1'),
       ('SYMMETRIC','sha256'),
       ('SYMMETRIC','sha512')
       /* XXX populate moar */
ON CONFLICT DO NOTHING;


/*
 * All non-principal entities and all principals will share a namespace via
 * trigger-driven double-entry in this table.  Among other things this allows
 * us to have an entity type in here.
 */
CREATE TABLE IF NOT EXISTS heimdal.policies (
    name                TEXT,
    /* XXX Add policy content */
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hpolpk   PRIMARY KEY (name)
);

/* Experimental inserts -L */

INSERT INTO heimdal.policies (name)
VALUES ('default')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS heimdal.entities (
    name                TEXT,
    namespace           heimdal.namespaces,
    entity_type         heimdal.entity_types NOT NULL,
    name_type            heimdal.kerberos_name_type
                        DEFAULT ('UNKNOWN'),
    canon_name          TEXT,
    canon_namespace     heimdal.namespaces,
    id                  BIGINT DEFAULT (nextval('heimdal.ids')),
    policy              TEXT,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hepk     PRIMARY KEY (name, namespace),
    CONSTRAINT hepk2    UNIQUE (id),
    CONSTRAINT hefkp    FOREIGN KEY (policy)
                        REFERENCES heimdal.policies (name)
                        ON DELETE CASCADE /* XXX SET NULL or block */
                        ON UPDATE CASCADE,
    CONSTRAINT hefkc    FOREIGN KEY (canon_name, canon_namespace)
                        REFERENCES heimdal.entities (name, namespace)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

/* Experimental inserts -L */

INSERT INTO heimdal.entities (name, namespace, entity_type)
VALUES ('u0@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u1@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u2@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u3@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u4@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u5@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u6@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u7@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u8@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u9@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u10@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u11@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u12@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u13@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u14@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('u15@FOO.EXAMPLE', 'PRINCIPAL', 'USER'),
       ('g0', 'GROUP', 'GROUP'),
       ('g1', 'GROUP', 'GROUP'),
       ('g2', 'GROUP', 'GROUP'),
       ('g3', 'GROUP', 'GROUP'),
       ('g4', 'GROUP', 'GROUP')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS heimdal.principal_data (
    name                TEXT,
    namespace           heimdal.namespaces
                        DEFAULT ('PRINCIPAL')
                        CHECK (namespace = 'PRINCIPAL'),
    /* flags and etypes are stored separately */
    kvno                BIGINT DEFAULT (1),
    pw_life             INTERVAL DEFAULT ('90 days'::interval),
    pw_end              TIMESTAMP WITHOUT TIME ZONE
                        DEFAULT (current_timestamp + '90 days'::interval),
    last_pw_change      TIMESTAMP WITHOUT TIME ZONE,
    max_life            INTERVAL DEFAULT ('10 hours'::interval),
    max_renew           INTERVAL DEFAUlT ('7 days'::interval),
    password            TEXT, /* very much optional, mostly unused XXX make binary, encrypted */
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hppk     PRIMARY KEY (name, namespace), /* Is namespace really necessary here if namespace is guaranteed to be 'PRINCIPAL'? -L */
    CONSTRAINT hpfka    FOREIGN KEY (name, namespace)
                        REFERENCES heimdal.entities (name, namespace)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

/* Experimental insets -L */

INSERT INTO heimdal.principal_data (name, password)
VALUES ('u0@FOO.EXAMPLE', 'password-00'),
       ('u1@FOO.EXAMPLE', 'password-01'),
       ('u2@FOO.EXAMPLE', 'password-02'),
       ('u3@FOO.EXAMPLE', 'password-03'),
       ('u4@FOO.EXAMPLE', 'password-04'),
       ('u5@FOO.EXAMPLE', 'password-05'),
       ('u6@FOO.EXAMPLE', 'password-06'),
       ('u7@FOO.EXAMPLE', 'password-07'),
       ('u8@FOO.EXAMPLE', 'password-08'),
       ('u9@FOO.EXAMPLE', 'password-09'),
       ('u10@FOO.EXAMPLE', 'password-09'),
       ('u11@FOO.EXAMPLE', 'password-10'),
       ('u12@FOO.EXAMPLE', 'password-11'),
       ('u13@FOO.EXAMPLE', 'password-12'),
       ('u14@FOO.EXAMPLE', 'password-13'),
       ('u15@FOO.EXAMPLE', 'password-14')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS heimdal.principal_etypes(
    name                TEXT,
    namespace           heimdal.namespaces
                        DEFAULT ('PRINCIPAL')
                        CHECK (namespace = 'PRINCIPAL'),
    etype               heimdal.enc_type NOT NULL,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hpepk    PRIMARY KEY (name, namespace, etype), /* Again, is namespace necessary? -L */
    CONSTRAINT hpefk    FOREIGN KEY (name, namespace)
                        REFERENCES heimdal.entities (name, namespace)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

/* Experimental insets -L */

INSERT INTO heimdal.principal_etypes (name, etype)
VALUES ('u0@FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('u1@FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('u2@FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('u3@FOO.EXAMPLE', 'aes128-cts-hmac-sha1-96'),
       ('u4@FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('u5@FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('u6@FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('u7@FOO.EXAMPLE', 'aes256-cts-hmac-sha1-96'),
       ('u8@FOO.EXAMPLE', 'aes128-cts-hmac-sha256'),
       ('u9@FOO.EXAMPLE', 'aes128-cts-hmac-sha256'),
       ('u10@FOO.EXAMPLE', 'aes128-cts-hmac-sha256'),
       ('u11@FOO.EXAMPLE', 'aes128-cts-hmac-sha256'),
       ('u12@FOO.EXAMPLE', 'aes256-cts-hmac-sha512'),
       ('u13@FOO.EXAMPLE', 'aes256-cts-hmac-sha512'),
       ('u14@FOO.EXAMPLE', 'aes256-cts-hmac-sha512'),
       ('u15@FOO.EXAMPLE', 'aes256-cts-hmac-sha512')
ON CONFLICT DO NOTHING;

/*
 * Let's have some consistency here. If enc_type and digest_type are both types contained in tables enc_typeS and digest_typeS
 * then the table principal_flags should contain the type principal_flag, NOT princ_flags. -L
 */

CREATE TABLE IF NOT EXISTS heimdal.principal_flags(
    name                TEXT,
    namespace           heimdal.namespaces
                        DEFAULT ('PRINCIPAL')
                        CHECK (namespace = 'PRINCIPAL'),
    flag                heimdal.princ_flags NOT NULL,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hpfpk    PRIMARY KEY (name, namespace, flag),
    CONSTRAINT hpffk    FOREIGN KEY (name, namespace)
                        REFERENCES heimdal.entities (name, namespace)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

/* Experimental insets -L */

INSERT INTO heimdal.principal_flags (name, flag)
VALUES ('u0@FOO.EXAMPLE', 'CLIENT'),
       ('u1@FOO.EXAMPLE', 'CLIENT'),
       ('u2@FOO.EXAMPLE', 'CLIENT'),
       ('u3@FOO.EXAMPLE', 'CLIENT'),
       ('u4@FOO.EXAMPLE', 'CLIENT'),
       ('u5@FOO.EXAMPLE', 'CLIENT'),
       ('u6@FOO.EXAMPLE', 'CLIENT'),
       ('u7@FOO.EXAMPLE', 'CLIENT'),
       ('u8@FOO.EXAMPLE', 'CLIENT'),
       ('u9@FOO.EXAMPLE', 'CLIENT'),
       ('u10@FOO.EXAMPLE', 'CLIENT'),
       ('u11@FOO.EXAMPLE', 'CLIENT'),
       ('u12@FOO.EXAMPLE', 'CLIENT'),
       ('u13@FOO.EXAMPLE', 'CLIENT'),
       ('u14@FOO.EXAMPLE', 'CLIENT'),
       ('u15@FOO.EXAMPLE', 'CLIENT')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS heimdal.members (
    container_name      TEXT,
    container_namespace heimdal.namespaces,
    member_name         TEXT,
    member_namespace    heimdal.namespaces,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hmpk     PRIMARY KEY (container_name, container_namespace, member_name, member_namespace),
    CONSTRAINT hmfkc    FOREIGN KEY (container_name, container_namespace)
                        REFERENCES heimdal.entities (name, namespace)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hmfkm    FOREIGN KEY (member_name, member_namespace)
                        REFERENCES heimdal.entities (name, namespace)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

/* Experimental inserts -L */

INSERT INTO heimdal.members (container_name, container_namespace, member_name, member_namespace)
VALUES ('g0', 'GROUP', 'u0@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g0', 'GROUP', 'u1@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g0', 'GROUP', 'u2@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g0', 'GROUP', 'u3@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g1', 'GROUP', 'u1@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g1', 'GROUP', 'u6@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g1', 'GROUP', 'u7@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g1', 'GROUP', 'u8@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g2', 'GROUP', 'u4@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g2', 'GROUP', 'u5@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g2', 'GROUP', 'u9@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g3', 'GROUP', 'u11@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g3', 'GROUP', 'u12@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g4', 'GROUP', 'u14@FOO.EXAMPLE', 'PRINCIPAL'),
       ('g4', 'GROUP', 'u15@FOO.EXAMPLE', 'PRINCIPAL')
ON CONFLICT DO NOTHING;

CREATE TYPE heimdal.salt AS (
    salttype            BIGINT,
    value               BYTEA,
    opaque              BYTEA
);
CREATE TABLE IF NOT EXISTS heimdal.keys (
    name                TEXT,
    namespace           heimdal.namespaces,
    kvno                BIGINT,
    ktype               heimdal.key_type,
    etype               heimdal.enc_type, /* varies according to heimdal.key_type */
    key                 BYTEA,
    salt                heimdal.salt,
    mkvno               BIGINT,
    /* keys can be disabled separately from enc_types */
    enabled             BOOLEAN DEFAULT (TRUE),
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hkpk     PRIMARY KEY (name, namespace, ktype, etype, kvno, enabled),
    /* You can have two rows in keys that are identical except with enabled true in one and false in another? I'm not sure that's intentional. -L */
    CONSTRAINT hkfk1    FOREIGN KEY (name, namespace)
                        REFERENCES heimdal.entities (name, namespace)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hkfk2    FOREIGN KEY (ktype,etype)
                        REFERENCES heimdal.enc_types (ktype,etype)
                        ON DELETE RESTRICT
                        ON UPDATE CASCADE
);

/* Experimental insets -L */

INSERT INTO heimdal.keys (name, namespace, kvno, ktype, etype, key)
VALUES ('u0@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0000'),
       ('u0@FOO.EXAMPLE', 'PRINCIPAL', 2, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0100'),
       ('u1@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0001'),
       ('u2@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0002'),
       ('u3@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha1-96', E'\\x0003'),
       ('u4@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0004'),
       ('u5@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0005'),
       ('u6@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0006'),
       ('u7@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha1-96', E'\\x0007'),
       ('u8@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha256', E'\\x0008'),
       ('u9@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha256', E'\\x0009'),
       ('u10@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha256', E'\\x0010'),
       ('u11@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes128-cts-hmac-sha256', E'\\x0011'),
       ('u12@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha512', E'\\x0012'),
       ('u13@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha512', E'\\x0013'),
       ('u14@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha512', E'\\x0014'),
       ('u15@FOO.EXAMPLE', 'PRINCIPAL', 1, 'SYMMETRIC', 'aes256-cts-hmac-sha512', E'\\x0015')
ON CONFLICT DO NOTHING;

UPDATE heimdal.principal_data SET kvno = 2
WHERE name = 'u0@FOO.EXAMPLE';

CREATE TABLE IF NOT EXISTS heimdal.password_history (
    name                TEXT,
    namespace           heimdal.namespaces
                        DEFAULT ('PRINCIPAL')
                        CHECK (namespace = 'PRINCIPAL'),
    etype               heimdal.enc_type,
    /* XXX Should be MAC, not digest */
    digest_alg          heimdal.digest_type, /* why not just dtype like table digest_types? -L */
    digest              BYTEA,
    kvno                BIGINT,
    mkvno               BIGINT,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hphpk    PRIMARY KEY (name, namespace, etype, digest_alg, kvno),
    CONSTRAINT hpfk     FOREIGN KEY (name, namespace)
                        REFERENCES heimdal.entities (name, namespace)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hkfk2    FOREIGN KEY (digest_alg)
                        REFERENCES heimdal.digest_types (dtype)
                        ON DELETE RESTRICT
                        ON UPDATE CASCADE
);
CREATE TYPE heimdal.pkix_name AS (
    display             TEXT,   /* display form of name */
    name_type            heimdal.pkix_name_type,
    name                BYTEA
);
CREATE TABLE IF NOT EXISTS heimdal.pkinit_cert_names (
    name                TEXT,
    namespace           heimdal.namespaces
                        DEFAULT ('PRINCIPAL')
                        CHECK (namespace = 'PRINCIPAL'),
    subject             heimdal.pkix_name,
    issuer              heimdal.pkix_name,
    serial              BYTEA,
    anchor              heimdal.pkix_name,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hpcnpk   PRIMARY KEY (name, namespace, subject, issuer, serial),
    CONSTRAINT hpcfk    FOREIGN KEY (name, namespace)
                        REFERENCES heimdal.entities (name, namespace)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

/*
 * HDB VIEWs and INSTEAD OF triggers for interfacing libhdb to HDBs hosted on
 * PG with the above schema.
 *
 * Many of these VIEWs and associated TRIGGERs could be auto-generated from the
 * schema.  We might need to enrich the schema with JSON-encoded COMMENTary.
 */

CREATE OR REPLACE VIEW hdb.modified_info_raw AS
SELECT name AS name, namespace AS namespace,
       modified_by AS modified_by, modified_at AS modified_at
FROM heimdal.entities
UNION ALL
SELECT name, namespace, modified_by, modified_at
FROM heimdal.principal_data
UNION ALL
SELECT name, namespace, modified_by, modified_at
FROM heimdal.principal_flags
UNION ALL
SELECT name, namespace, modified_by, modified_at
FROM heimdal.principal_etypes
UNION ALL
SELECT name, namespace, modified_by, modified_at
FROM heimdal.keys
UNION ALL
SELECT name, namespace, modified_by, modified_at
FROM heimdal.pkinit_cert_names;

CREATE OR REPLACE VIEW hdb.modified_info_max AS
SELECT name AS name, namespace AS namespace, max(modified_at) AS modified_at
FROM hdb.modified_info_raw
GROUP BY name, namespace;

CREATE OR REPLACE VIEW hdb.modified_info AS
SELECT m.name AS name, m.namespace AS namespace,
       max(r.modified_by) AS modified_by, m.modified_at AS modified_at
FROM hdb.modified_info_raw r
JOIN hdb.modified_info_max m USING(name, namespace, modified_at)
GROUP BY m.name, m.namespace, m.modified_at ;
/* This makes no sense to me.
 * How can you max aggregate a text?
 Even if you can, how is it useful when you only have one row for every name-namespace pair? -L
 */

CREATE OR REPLACE VIEW hdb.key AS
SELECT
    k.name AS name, k.kvno AS kvno,
    jsonb_build_object('ktype',k.ktype::text,
                       'etype',k.etype::text,
                       'kvno',k.kvno::bigint,
                       'mkvno',k.mkvno::bigint,
                       'salt',k.salt::text,
                       'key',k.key::text) AS key
FROM heimdal.keys k
WHERE k.enabled AND k.valid_start <= current_timestamp AND
      k.valid_end > current_timestamp;

CREATE OR REPLACE VIEW hdb.keyset AS
SELECT k.name AS name, k.kvno AS kvno, jsonb_agg(ks.key) AS keys
FROM heimdal.keys k
JOIN hdb.key ks USING (name, kvno)
GROUP BY k.name, k.kvno;

CREATE OR REPLACE VIEW hdb.keysets AS
SELECT ks.name AS name, 'keysets' AS extname,
       jsonb_agg(ks.keys) AS ext
FROM hdb.keyset ks
WHERE NOT EXISTS (SELECT 1 FROM heimdal.principal_data p WHERE p.name = ks.name AND p.kvno = ks.kvno)
GROUP BY ks.name;

CREATE OR REPLACE VIEW hdb.aliases AS
SELECT e.canon_name AS name, 'aliases' AS extname, jsonb_agg(e.name) AS ext
FROM heimdal.entities e
WHERE namespace = 'PRINCIPAL' AND e.canon_name IS NOT NULL
GROUP BY e.canon_name;

CREATE OR REPLACE VIEW hdb.pwh1 AS
SELECT p.name AS name,
       jsonb_build_object('kvno',p.kvno,
                          'mkvno',p.mkvno,
                          'etype',p.etype::text,
                          'digest_alg',p.digest_alg::text,
                          'digest',encode(p.digest, 'base64')) AS old_password
FROM heimdal.password_history p;

CREATE OR REPLACE VIEW hdb.pwh AS
SELECT p1.name AS name, 'password_history' AS extname,
       jsonb_agg(p1.old_password) AS ext
FROM hdb.pwh1 p1
GROUP BY p1.name;

CREATE OR REPLACE VIEW hdb.exts_raw AS
SELECT name AS name, extname AS extname, ext AS ext
FROM hdb.keysets
UNION ALL
SELECT name, extname, ext
FROM hdb.aliases
UNION ALL
SELECT name, extname, ext
FROM hdb.pwh
UNION ALL
SELECT name, 'null', jsonb_build_object()
FROM heimdal.principal_data;

CREATE OR REPLACE VIEW hdb.exts AS
SELECT name AS name,
       jsonb_agg(json_build_object('exttype',extname,
                                  'ext',ext)) AS exts
FROM hdb.exts_raw
GROUP BY name;
/*
 * XXX Finish, add all remaining hdb entry extensions here:
 *
 *  - PKINIT cert hashes
 *  - PKINIT cert names
 *  - PKINIT certs
 *  - S4U constrained delegation ACLs
 */
;

CREATE OR REPLACE VIEW hdb.flags AS
SELECT p.name AS name, jsonb_agg(p.flag::text) AS flags
FROM heimdal.principal_flags p
WHERE valid_end > current_timestamp
GROUP BY p.name;

CREATE OR REPLACE VIEW hdb.etypes AS
SELECT p.name AS name, jsonb_agg(p.etype::text) AS etypes
FROM heimdal.principal_etypes p
WHERE valid_end > current_timestamp
GROUP BY p.name;

CREATE OR REPLACE VIEW hdb.hdb AS
SELECT e.name AS name,
       json_build_object(
            'name',e.name,
            'canon-name',e.canon_name,
            'kvno',p.kvno,
            'keys',keys.keys,
            'name-type',e.name_type,
            'created-by',e.created_by,
            'created-at',e.created_at::text,
            'modified-by',modinfo.modified_by,
            'modified-at',modinfo.modified_at::text,
            'valid-start',p.valid_start::text,
            'valid-end',p.valid_end::text,
            'pw-life',p.pw_life::text,
            'pw-end',p.pw_end::text,
            'last-pw-change',p.last_pw_change::text,
            'max-life',coalesce(p.max_life::text,''),
            'max-renew',coalesce(p.max_renew::text,''),
            'flags',coalesce(flags.flags,'[]'::jsonb),
            'etypes',coalesce(etypes.etypes,jsonb_build_array()),
            'extensions',coalesce(exts.exts,'[]'::jsonb)) AS entry
FROM heimdal.entities e
JOIN hdb.modified_info modinfo USING (name, namespace)
JOIN heimdal.principal_data p USING (name, namespace)
JOIN hdb.flags flags USING (name)
JOIN hdb.exts exts USING (name)
LEFT JOIN hdb.etypes etypes ON e.name = etypes.name
LEFT JOIN hdb.keyset keys ON p.name = keys.name AND p.kvno = keys.kvno
WHERE e.namespace = 'PRINCIPAL' AND
      p.valid_start <= current_timestamp AND p.valid_end > current_timestamp
UNION ALL
SELECT e.name AS name,
       json_build_object(
            'name',a.name,
            'canon_name',a.canon_name,
            'created-by',a.created_by,
            'created-at',a.created_at::text,
            'modified-by',a.modified_by,
            'modified-at',a.modified_at::text) AS entry
FROM heimdal.entities a
JOIN heimdal.entities e ON a.canon_name = e.canon_name AND
                           a.canon_namespace = e.canon_namespace
WHERE a.namespace = 'PRINCIPAL' AND
      a.valid_start <= current_timestamp AND a.valid_end > current_timestamp AND
      e.valid_start <= current_timestamp AND e.valid_end > current_timestamp;

/* XXX Add INSTEAD OF triggers on HDB views */

CREATE OR REPLACE FUNCTION hdb.instead_of_on_keyset_func()
RETURNS TRIGGER AS $$
DECLARE
    fields JSONB;
BEGIN
    INSERT INTO heimdal.keys
        (name, namespace, kvno, ktype, etype, key, salt, mkvno)
    SELECT NEW.name, 'PRINCIPAL', (k->>'kvno'::text)::bigint, (k->>'ktype'::text)::heimdal.key_type,
                                (k->>'etype'::text)::heimdal.enc_type, (k->>'key'::text)::bytea,
                                (k->>'salt'::text)::heimdal.salt, (k->>'mkvno'::text)::bigint
    FROM jsonb_array_elements(NEW.keys) k;
    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER instead_of_on_hdb_keyset
INSTEAD OF INSERT
ON hdb.keyset
FOR EACH ROW
EXECUTE FUNCTION hdb.instead_of_on_keyset_func();

CREATE OR REPLACE FUNCTION hdb.instead_of_on_exts_func()
RETURNS TRIGGER AS $$
DECLARE
    fields JSONB;
BEGIN
    /* Same pattern for all extensions */

    INSERT INTO hdb.aliases
        (name, ext)
    SELECT NEW.name, e->'ext'
    FROM jsonb_array_elements(NEW.exts) e
    WHERE (e->>'exttype'::text) = 'aliases';

    INSERT INTO hdb.keysets
        (name, ext)
    SELECT NEW.name, e->'ext'
    FROM jsonb_array_elements(NEW.exts) e
    WHERE (e->>'exttype'::text) = 'keysets';

    INSERT INTO hdb.pwh
        (name, ext)
    SELECT NEW.name, e->'ext'
    FROM jsonb_array_elements(NEW.exts) e
    WHERE (e->>'exttype'::text) = 'password_history';

    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER instead_of_on_hdb_exts
INSTEAD OF INSERT
ON hdb.exts
FOR EACH ROW
EXECUTE FUNCTION hdb.instead_of_on_exts_func();

CREATE OR REPLACE FUNCTION hdb.instead_of_on_aliases_func()
RETURNS TRIGGER AS $$
DECLARE
    fields JSONB;
BEGIN
    IF NEW.extname <> 'aliases' OR OLD.extname <> 'aliases' THEN
        RETURN NULL; /* XXX Raise instead! */
    END IF;

    IF TG_OP = 'UPDATE' THEN
        /* Delete aliases that existed but don't appear in 'ext' -- they're getting dropped*/
        WITH aliases AS (
            -- New aliases
            SELECT a.alias AS alias FROM jsonb_array_elements_text(NEW.ext) a(alias))
        DELETE FROM heimdal.entities AS e
        WHERE canon_name = NEW.name AND namespace = 'PRINCIPAL' AND
              -- Delete existing aliases that are not in the new alias list
              NOT EXISTS (SELECT 1 FROM aliases a WHERE a.alias = e.name);
    END IF;

    /* Insert any [new] aliases */
    INSERT INTO heimdal.entities
        (name, namespace, canon_name, canon_namespace,
         entity_type, name_type, valid_start, valid_end)
    SELECT a.name, 'PRINCIPAL', NEW.name, 'PRINCIPAL',
           p.entity_type, p.name_type, p.valid_start, p.valid_end
    FROM jsonb_array_elements_text(NEW.ext) AS a(name)
    CROSS JOIN (
        /* Get the columns of the canonical name that we have to copy */
        SELECT entity_type, name_type, valid_start, valid_end
        FROM heimdal.entities
        WHERE name = NEW.name AND namespace = 'PRINCIPAL') p
    WHERE NOT EXISTS (
        /* But don't re-add aliases that already exist for this principal */
        SELECT 1
        FROM heimdal.entities e
        WHERE e.name = a.name AND namespace = 'PRINCIPAL' AND
              e.canon_name = NEW.name AND e.canon_namespace = 'PRINCIPAL');
    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER instead_of_on_hdb_aliases
INSTEAD OF INSERT OR UPDATE
ON hdb.aliases
FOR EACH ROW
EXECUTE FUNCTION hdb.instead_of_on_aliases_func();

CREATE OR REPLACE FUNCTION hdb.instead_of_on_pwh_func()
RETURNS TRIGGER AS $$
DECLARE
    fields JSONB;
BEGIN
    IF NEW.extname <> 'password_history' OR OLD.extname <> 'password_history' THEN
        RETURN NULL; /* XXX Raise instead! */
    END IF;

    IF TG_OP = 'UPDATE' THEN
        /* Delete pwh entries that existed but don't appear in 'ext' -- they're getting dropped*/
        WITH pwh_entries AS (
            -- New pwh entries
            SELECT p.entry AS entry FROM jsonb_array_elements_text(NEW.ext) p(entry))
        DELETE FROM heimdal.password_history AS p
        WHERE name = NEW.name AND namespace = 'PRINCIPAL' AND
              -- Delete existing aliases that are not in the new alias list
              NOT EXISTS (
                    SELECT 1
                    FROM pwh_entries e
                    WHERE e.name = p.name AND p.canon_name = 'PRINCIPAL' AND
                          decode(e.entry->>'digest'::text, 'base64') = p.digest);
    END IF;

    /* Insert any [new] password history entries */
    INSERT INTO heimdal.password_history
        (name, namespace, etype, digest_alg, digest, kvno, mkvno)
    SELECT a.name, 'PRINCIPAL', (e.entry)->'etype'::text::heimdal.enc_type,
           (e.entry)->'digest_alg'::text::heimdal.digest_type,
           decode(e.entry->>'digest'::text, 'base64'),
           (e.entry)->'kvno'::bigint,
           (e.entry)->'mkvno'::bigint
    FROM jsonb_array_elements(NEW.ext) AS e(entry)
    WHERE NOT EXISTS (
        /* But don't re-add password history entries that already exist for this principal */
        SELECT 1
        FROM heimdal.password_history e
        WHERE e.name = a.name AND namespace = 'PRINCIPAL' AND
              decode((NEW.entry)->>'digest'::text, 'base64') = e.digest);
    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER instead_of_on_hdb_pwh
INSTEAD OF INSERT OR UPDATE
ON hdb.pwh
FOR EACH ROW
EXECUTE FUNCTION hdb.instead_of_on_pwh_func();

CREATE OR REPLACE FUNCTION hdb.instead_of_on_hdb_func()
RETURNS TRIGGER AS $$
DECLARE
    fields JSONB;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.name IS NULL THEN
            OLD.name = (OLD.entry)->'name';
        END IF;
        IF OLD.name IS NULL THEN
            RETURN OLD; /* XXX Raise instead */
        END IF;
        DELETE FROM heimdal.entities AS e
        WHERE e.namespace = 'PRINCIPAL' AND
              e.name = OLD.name AND
              ((e.canon_name IS NULL AND
                EXISTS (SELECT 1
                        FROM heimdal.principal_data d
                        WHERE d.name = OLD.name)) OR
               (e.canon_name IS NOT NULL AND
                EXISTS (SELECT 1
                        FROM heimdal.principal_data d
                        WHERE d.name = e.canon_name)));
        RETURN OLD;
    END IF;

    IF (NEW.entry) IS NULL OR (NEW.entry)->'name' IS NULL THEN
        RETURN NEW; /* XXX Raise instead */
    END IF;
    NEW.name := (NEW.entry)->'name';

    IF TG_OP = 'INSERT' THEN
        /* Add the principal's base entity */
        INSERT INTO heimdal.entities
            (name, namespace, entity_type, name_type, policy)
        SELECT (NEW.entry)->>'name', 'PRINCIPAL', 'UNKNOWN-PRINCIPAL-TYPE',
               ((NEW.entry)->>'name-type'::text)::heimdal.kerberos_name_type, (NEW.entry)->'policy';

        /* Add the principal */
        INSERT INTO heimdal.principal_data
            (name, namespace, kvno, pw_life, pw_end, max_life,
             max_renew, password)
        SELECT (NEW.entry)->>'name', 'PRINCIPAL', ((NEW.entry)->'kvno')::text::bigint,
               ((NEW.entry)->>'pw-life'::text)::interval, ((NEW.entry)->>'pw-end'::text)::timestamp without time zone,
               coalesce(((NEW.entry)->>'max-life'::text)::interval), coalesce(((NEW.entry)->>'max-renew'::text)::interval),
               (NEW.entry)->>'password';

        /* Add its normalized flags */
        INSERT INTO heimdal.principal_flags
            (name, namespace, flag)
        SELECT (NEW.entry)->>'name', 'PRINCIPAL', (flag::text)::heimdal.princ_flags
        FROM json_array_elements_text((NEW.entry)->'flags') f(flag);

        /* Insert current keyset indirectly via INSTEAD OF INSERT TRIGGER on hdb.keyset */
        INSERT INTO hdb.keyset (name, keys)
        SELECT (NEW.entry)->>'name', (NEW.entry)->'keys';

        /* Insert extensions indirectly via INSTEAD OF INSERT TRIGGER on hdb.exts */
        INSERT INTO hdb.exts (name, exts)
        SELECT (NEW.entry)->>'name', (NEW.entry)->'extensions';
        RETURN NEW;
    END IF;

    /* UPDATE a principal or alias */

    /* Update extensions indirectly via INSTEAD OF UPDATE TRIGGER on hdb.exts */

    /* Get the list of fields to update */
    fields := coalesce((NEW.entry)->'kadm5_fields',
                       '{"name":true,
                         "principal_expire_time":true,
                         "pw_expiration":true,
                         "last_pwd_change":true,
                         "max_life":true,
                         "max_rlife":true,
                         "mod_time":true,
                         "mod_name":true,
                         "attributes":true,
                         "etypes":true,
                         "s4uacl":true,
                         "acl":true,
                         "kvno":true,
                         "mkvno":true,
                         "last_success":true,
                         "last_failed":true,
                         "fail_auth_count":true,
                         "policy":true,
                         "keys":true,
                         "password":true,
                         "pkinit":true,
                         "aliases":true
                        }'::json);
    IF OLD.name IS NULL THEN
        OLD.name := NEW.name;
    END IF;

    IF fields->'name' IS NULL AND
       (OLD.entry)->'canon_name' IS NOT NULL AND
       (NEW.entry)->'canon_name' IS NOT NULL THEN
        /* Update (move) an alias */
        IF OLD.name != NEW.name THEN
            RETURN NEW; /* Nothing to do.  XXX Raise instead? */
        END IF;
        UPDATE heimdal.entities
        SET canon_name = (NEW.entry)->'canon_name'
        WHERE name = NEW.name AND canon_name = (OLD.entry)->'canon_name';
        RETURN NEW; /* Nothing else to do */
    END IF;

    IF fields->'name' IS NULL AND
       ((OLD.entry)->'canon_name' IS NOT NULL OR
        (NEW.entry)->'canon_name' IS NOT NULL) THEN
        /*
         * Can't change a principal to an alias or an alias to a principal.
         * Delete then re-create.
         *
         * XXX We could do the delete and re-create here.
         */
        RETURN NEW; /* XXX Raise instead */
    END IF;

    /* Update a principal */

    /* First update everything but the name */
    IF fields->'principal_expire_time' IS NOT NULL THEN
        UPDATE heimdal.principal_data
        SET valid_end = (NEW.entry)->'valid-end'::timestamp without time zone
        WHERE name = OLD.name;
    END IF;
    IF fields->'pw_expiration' IS NOT NULL THEN
        UPDATE heimdal.principal_data
        SET valid_end = (NEW.entry)->'pw-end'::timestamp without time zone
        WHERE name = OLD.name AND namespace = 'PRINCIPAL';
    END IF;
    IF fields->'last_pwd_change' IS NOT NULL THEN
        UPDATE heimdal.principal_data
        SET last_pw_change = (NEW.entry)->'last-pw-change'::timestamp without time zone
        WHERE name = OLD.name AND namespace = 'PRINCIPAL';
    END IF;
    IF fields->'max_life' IS NOT NULL THEN
        UPDATE heimdal.principal_data
        SET last_pw_change = (NEW.entry)->'max-life'::interval
        WHERE name = OLD.name AND namespace = 'PRINCIPAL';
    END IF;
    IF fields->'max_renew' IS NOT NULL THEN
        UPDATE heimdal.principal_data
        SET last_pw_change = (NEW.entry)->'max-renew'::interval
        WHERE name = OLD.name AND namespace = 'PRINCIPAL';
    END IF;
    IF fields->'attributes' IS NOT NULL THEN
        DELETE FROM heimdal.principal_flags AS pf
        WHERE pf.name = OLD.name AND namespace = 'PRINCIPAL' AND
              (NEW.entry)@>(json_build_array(pf.flag));
        INSERT INTO heimdal.principal_flags
            (name, namespace, flag)
        SELECT OLD.name, 'PRINCIPAL', jsonb_array_elements((NEW.entry)->'flags');
    END IF;
    IF fields->'etypes' IS NOT NULL THEN
        DELETE FROM heimdal.principal_etypes AS pe
        WHERE pe.name = OLD.name AND namespace = 'PRINCIPAL' AND
              (NEW.entry)@>(json_build_array(pe.etype));
        INSERT INTO heimdal.principal_etype
            (name, namespace, etype)
        SELECT OLD.name, 'PRINCIPAL', jsonb_array_elements((NEW.entry)->'etypes');
    END IF;
    IF fields->'keydata' IS NOT NULL THEN
        /* XXX Delete old keys too! */
        /*
         * hdb.key's INSTEAD OF INSERT trigger will not update key values when
         * the primary key matches.
         */
        INSERT INTO hdb.key (namme, kvno, key)
        SELECT OLD.name, (q.js)->'kvno', (q.js)->'key'
        FROM (SELECT jsonb_array_elements((NEW.entry)->'keys')) q(js)
        UNION ALL
        SELECT OLD.name, (q.js)->'kvno', (q.js)->'key'
        FROM (SELECT jsonb_array_elements((q.js)->'keys')
              FROM (SELECT jsonb_array_elements((q.js)->keys)
                    FROM (SELECT jsonb_array_elements((NEW.entry)->'extensions')
                          WHERE (NEW.entry)->'exttype' = 'keysets') q(js)) q(js)) q(js)
        ON CONFLICT DO NOTHING;
    END IF;
    IF coalesce(fields->'password', FALSE) THEN
        /* XXX Delete old password history too! */
        /*
         * hdb.key's INSTEAD OF INSERT trigger will not update key values when
         * the primary key matches.
         */
        UPDATE heimdal.principal
        SET kvno = coalesce((NEW.entry)->'kvno', kvno + 1),
            password = (NEW.entry)->'password'
        WHERE name = (OLD.entry)->'name' AND (q.js)->'password' IS NOT NULL;
        INSERT INTO heimdal.password_history
            (name, namespate, kvno, mkvno, etype, digest_alg, digest)
        SELECT OLD.name, 'PRINCIPAL', (q.js)->'kvno', (q.js)->'mkvno',
               (q.js)->'etype', (q.js)->'digest_alg', (q.js)->digest
        FROM (SELECT jsonb_array_elements(q.js)
              FROM (SELECT jsonb_array_elements((NEW.entry)->'extensions')) q(js)) q(js)
        ON CONFLICT DO NOTHING;
    END IF;
    /* XXX Implement updating of all remaining extensions */
    /* Rename */
    IF coalesce(fields->'name', FALSE) AND
        OLD.name IS NOT NULL AND NEW.name IS NOT NULL AND
        (NEW.entry)->'name' IS NOT NULL AND
        OLD.name != NEW.name AND NEW.name = (NEW.entry)->'name' THEN
        UPDATE heimdal.entities
        SET name = NEW.name
        WHERE name = OLD.name;
    END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER instead_of_on_hdb
INSTEAD OF INSERT OR UPDATE OR DELETE
ON hdb.hdb
FOR EACH ROW
EXECUTE FUNCTION hdb.instead_of_on_hdb_func();
