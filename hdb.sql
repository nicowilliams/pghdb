-- SET client_min_messages TO 'debug';

\unset ON_ERROR_STOP

CREATE EXTENSION IF NOT EXISTS pgcrypto;
/*
 * Data tables go in the schema "heimdal".
 *
 * XXX If we want to do something like AD's global catalog, we could have a
 * separate schema to hold that.  For group memberships in that scheme we would
 * indeed need two-column foreign keys or else single-column with the realm
 * included in the value.  This argues for preparing to have multiple realms in
 * one DB, even if in actuality we wouldn't usually do that.
 *
 * XXX Rethink namespacing.  Perhaps implement something akin to UName*It
 * container rules.
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
CREATE SCHEMA IF NOT EXISTS hdb;
/*
 * Views and functions for PostgREST APIs go in the schema "pgt".
 */
CREATE SCHEMA IF NOT EXISTS pgt;

CREATE OR REPLACE FUNCTION heimdal.split_name(name TEXT)
RETURNS TEXT[]
LANGUAGE SQL AS $$
    SELECT CASE WHEN name !~ '' THEN ARRAY[name,'']
                WHEN name ~ '^[@]' THEN ARRAY['', substring(name FROM 2)]
                WHEN name ~ '[@]' THEN  ARRAY[trim(TRAILING '@' FROM substring(name FROM '^.*[@]')),
                           substring(substring(name FROM '[@].*$') FROM 2)]
                ELSE ARRAY[name,'']
           END;
$$ IMMUTABLE;

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
CREATE TYPE heimdal.containers AS ENUM (
    /*
     * So, what we're going for here is that we want to be able to support
     * distinct containers for several things for backwards compatibility
     * reasons.  But we could, in a better world, have just one container, and
     * then get rid of this ENUM type and all uses of it.
     *
     * XXX For now use only 'PRINCIPAL' -Nico
     */
    'PRINCIPAL', 'USER', 'GROUP', 'ACL', 'HOST', 'ROLE', 'LABEL', 'VERB'
);
CREATE TYPE heimdal.entity_types AS ENUM (
    /*
     * This is different from containers only because the latter are about
     * uniqueness, while this is about what kind of thing something is.
     *
     * If each kind of thing had a distinct container, then we'd not need this
     * ENUM type at all either.
     *
     * What we really want is to lose this ENUM, and for namespacing we should
     * build an extension that implements UName*It-style container rules.
     *
     * XXX For now use only 'USER'.
     */
    'PRINCIPAL', 'USER', 'ROLE', 'GROUP', 'CLUSTER', 'ACL', 'LABEL', 'VERB'
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
 * All non-principal entities and all principals will share a container via
 * trigger-driven double-entry in this table.  Among other things this allows
 * us to have an entity type in here.
 */
CREATE TABLE IF NOT EXISTS heimdal.policies (
    name                TEXT,
    /* XXX Add policy content */
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hpolpk   PRIMARY KEY (name)
);

INSERT INTO heimdal.policies (name)
VALUES ('default')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS heimdal.entities (
    display_name        TEXT,
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers,
    entity_type         heimdal.entity_types NOT NULL,
    id                  BIGINT DEFAULT (nextval('heimdal.ids')),
    policy              TEXT,
    owner_name          TEXT,
    owner_container     heimdal.containers,
    owner_realm         TEXT,
    owner_entity_type   heimdal.entity_types,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hepk     PRIMARY KEY (name, realm, container),
    CONSTRAINT hepk2    UNIQUE (id),
                        /* hepk3 is just for denormalzation of entity_type via FKs */
    CONSTRAINT heofk    FOREIGN KEY (owner_name, owner_realm, owner_container)
                        REFERENCES heimdal.entities (name, realm, container),
    CONSTRAINT hefkp    FOREIGN KEY (policy)
                        REFERENCES heimdal.policies (name)
                        ON DELETE SET NULL
                        ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS heimdal.entity_labels (
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers,
    label_name          TEXT,
    label_realm         TEXT,
    label_container     heimdal.containers
                        DEFAULT ('LABEL')
                        CHECK (label_container = 'LABEL'),
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT helpk    PRIMARY KEY (name, realm, container,
                                     label_name, label_realm, label_container),
    CONSTRAINT helefk   FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hellfk   FOREIGN KEY (label_name, label_realm, label_container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS heimdal.principals (
    display_name        TEXT,
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers
                        DEFAULT ('PRINCIPAL')
                        CHECK (container = 'PRINCIPAL'),
    name_type           heimdal.kerberos_name_type
                        DEFAULT ('UNKNOWN'),
    /* flags and etypes are stored separately */
    kvno                BIGINT DEFAULT (1),
    pw_life             INTERVAL DEFAULT ('90 days'::interval),
    pw_end              TIMESTAMP WITHOUT TIME ZONE
                        DEFAULT (current_timestamp + '90 days'::interval),
    last_pw_change      TIMESTAMP WITHOUT TIME ZONE
                        DEFAULT ('1970-01-01T00:00:00Z'::timestamp without time zone),
    max_life            INTERVAL DEFAULT ('10 hours'::interval),
    max_renew           INTERVAL DEFAUlT ('7 days'::interval),
    password            TEXT, /* very much optional, mostly unused XXX make binary, encrypted */
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hppk     PRIMARY KEY (name, realm, container),
    CONSTRAINT hpfka    FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS heimdal.principal_etypes(
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers
                        DEFAULT ('PRINCIPAL')
                        CHECK (container = 'PRINCIPAL'),
    etype               heimdal.enc_type NOT NULL,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hpepk    PRIMARY KEY (name, realm, container, etype),
    CONSTRAINT hpefk    FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

/*
 * Let's have some consistency here. If enc_type and digest_type are both types contained in tables enc_typeS and digest_typeS
 * then the table principal_flags should contain the type principal_flag, NOT princ_flags. -L
 */

CREATE TABLE IF NOT EXISTS heimdal.principal_flags(
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers
                        DEFAULT ('PRINCIPAL')
                        CHECK (container = 'PRINCIPAL'),
    flag                heimdal.princ_flags NOT NULL,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hpfpk    PRIMARY KEY (name, realm, container, flag),
    CONSTRAINT hpffk    FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS heimdal.members (
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers,
    member_name         TEXT,
    member_realm        TEXT,
    member_container    heimdal.containers,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hmpk     PRIMARY KEY (name, realm, container, member_name, member_realm, member_container),
    CONSTRAINT hmfkp    FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hmfkm    FOREIGN KEY (member_name, member_realm, member_container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

CREATE TYPE heimdal.salt AS (
    salttype            BIGINT,
    value               BYTEA,
    opaque              BYTEA
);

CREATE TABLE IF NOT EXISTS heimdal.keys (
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers
                        DEFAULT ('PRINCIPAL')
                        CHECK (container = 'PRINCIPAL'),
    kvno                BIGINT,
    ktype               heimdal.key_type,
    etype               heimdal.enc_type, /* varies according to heimdal.key_type */
    key                 BYTEA,
    salt                heimdal.salt,
    mkvno               BIGINT,
    /* keys can be disabled separately from enc_types */
    enabled             BOOLEAN DEFAULT (TRUE),
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hkpk     PRIMARY KEY (name, realm, container, ktype, etype, kvno, key),
    CONSTRAINT hkfk1    FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hkfk2    FOREIGN KEY (ktype,etype)
                        REFERENCES heimdal.enc_types (ktype,etype)
                        ON DELETE RESTRICT
                        ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS heimdal.aliases (
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers
                        DEFAULT ('PRINCIPAL')
                        CHECK (container = 'PRINCIPAL'),
    alias_name          TEXT,
    alias_realm         TEXT,
    alias_container     heimdal.containers
                        DEFAULT ('PRINCIPAL')
                        CHECK (container = 'PRINCIPAL'),
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hapk1    PRIMARY KEY (name, realm, container, alias_name, alias_realm, alias_container),
    CONSTRAINT hafk1    FOREIGN KEY (alias_name, alias_realm, alias_container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hafk2    FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS heimdal.password_history (
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers
                        DEFAULT ('PRINCIPAL')
                        CHECK (container = 'PRINCIPAL'),
    etype               heimdal.enc_type,
    /* XXX Should be MAC, not digest */
    digest_alg          heimdal.digest_type, /* why not just dtype like table digest_types? -L */
    digest              BYTEA,
    mkvno               BIGINT,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hphpk    PRIMARY KEY (name, realm, container, etype, digest_alg, mkvno),
    CONSTRAINT hpfk     FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hkfk2    FOREIGN KEY (digest_alg)
                        REFERENCES heimdal.digest_types (dtype)
                        ON DELETE RESTRICT
                        ON UPDATE CASCADE
);

CREATE TYPE heimdal.pkix_name AS (
    display             TEXT,   /* display form of name */
    name_type           heimdal.pkix_name_type,
    name                BYTEA
);
CREATE TABLE IF NOT EXISTS heimdal.pkinit_cert_names (
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers
                        DEFAULT ('PRINCIPAL')
                        CHECK (container = 'PRINCIPAL'),
    subject             heimdal.pkix_name,
    issuer              heimdal.pkix_name,
    serial              BYTEA,
    anchor              heimdal.pkix_name,
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hpcnpk   PRIMARY KEY (name, realm, container, subject, issuer, serial),
    CONSTRAINT hpcfk    FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS heimdal.roles2verbs (
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers
                        DEFAULT ('ROLE')
                        CHECK (container = 'ROLE'),
    verb_name           TEXT,
    verb_realm          TEXT,
    verb_container      heimdal.containers
                        DEFAULT ('VERB')
                        CHECK (verb_container = 'VERB'),
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hrpk    PRIMARY KEY (name, realm, container, verb_name, verb_realm, verb_container),
    CONSTRAINT hrfkr   FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hrfkv   FOREIGN KEY (verb_name, verb_realm, verb_container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS heimdal.grants (
    name                TEXT,
    realm               TEXT,
    container           heimdal.containers
                        CHECK (container = 'GROUP' OR container = 'USER'),
    label_name          TEXT,
    label_realm         TEXT,
    label_container     heimdal.containers
                        DEFAULT ('LABEL')
                        CHECK (label_container = 'LABEL'),
    role_name           TEXT,
    role_realm          TEXT,
    role_container      heimdal.containers
                        DEFAULT ('ROLE')
                        CHECK (role_container = 'ROLE'),
    LIKE heimdal.common INCLUDING ALL,
    CONSTRAINT hgpk    PRIMARY KEY (name, realm, container,
                                    label_name, label_realm, label_container,
                                    role_name, role_realm, role_container),
    CONSTRAINT hgfks   FOREIGN KEY (name, realm, container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hgfkl   FOREIGN KEY (label_name, label_realm, label_container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE,
    CONSTRAINT hgfkr   FOREIGN KEY (role_name, role_realm, role_container)
                        REFERENCES heimdal.entities (name, realm, container)
                        ON DELETE CASCADE
                        ON UPDATE CASCADE
);

CREATE OR REPLACE VIEW heimdal.tc_view AS
WITH RECURSIVE groups AS (
    /* Seed with every group includes itself -- this is important */
    SELECT name AS name, realm AS realm, container AS container,
           name AS member_name, realm AS member_realm, container AS member_container
    FROM heimdal.entities WHERE entity_type = 'GROUP'
    UNION
    /* Get the parents of all groups */
    SELECT m.name, m.realm, m.container,
           g.member_name, g.member_realm, g.member_container
    FROM heimdal.members m JOIN groups g ON (m.member_name = g.name AND m.member_realm = g.realm AND m.member_container = g.container)
)
SELECT * FROM groups;

/* Materialize the view -- we'll have triggers to keep it up to date */
SELECT mat_views.create_view('heimdal','tc', 'heimdal', 'tc_view');
/* Populate it (creating it doesn't do this) */
SELECT mat_views.refresh_view('heimdal','tc');
/* Look 'ma!  PG's MAT VIEWs do not allow this: */
ALTER TABLE heimdal.tc
    ADD CONSTRAINT htcpk1
        PRIMARY KEY (name, realm, container,
                     member_name, member_realm, member_container);
/* nor this! */
CREATE INDEX tc2 ON heimdal.tc
    (member_name, member_realm, member_container,
     name, realm, container);

/* Now a view for all the users' group memerships */
CREATE OR REPLACE VIEW heimdal.tcu_view AS
SELECT tc.name AS name, tc.realm AS realm,
       tc.container AS container, e.name AS member_name,
       e.realm AS member_realm, e.container AS member_container
FROM heimdal.entities e
/* get direct memberships */
JOIN heimdal.members m ON (e.name = m.member_name AND e.realm = m.member_realm AND e.container = m.member_container)
/* get all remaining indirect memberships */
JOIN heimdal.tc tc ON (tc.member_name = m.name AND tc.member_realm = m.realm AND tc.member_container = m.container)
WHERE e.entity_type = 'USER'
UNION
SELECT e.name, e.realm, e.container, e.name, e.realm, e.container
FROM heimdal.entities e
WHERE e.entity_type = 'USER';

SELECT mat_views.create_view('heimdal','tcu','heimdal','tcu_view');

SELECT mat_views.refresh_view('heimdal','tcu');

ALTER TABLE heimdal.tcu
    ADD CONSTRAINT htcupk1
        PRIMARY KEY (name, realm, container,
                     member_name, member_realm, member_container);

CREATE INDEX tcu2 ON heimdal.tcu
    (member_name, member_realm, member_container,
     name, realm, container);

CREATE OR REPLACE VIEW heimdal.grants2direct_grantees AS
SELECT g.name AS name, g.realm AS realm,
       g.container AS container, g.label_name AS label_name,
       g.label_realm AS label_realm, g.label_container AS label_container,
       rv.verb_name AS verb_name, rv.verb_realm AS verb_realm,
       rv.verb_container AS verb_container
FROM heimdal.roles2verbs rv
JOIN heimdal.grants g ON rv.name = g.role_name AND
                         rv.realm = g.role_realm AND
                         rv.container = g.role_container;

SELECT mat_views.create_view('heimdal','g2dg','heimdal','grants2direct_grantees');

SELECT mat_views.refresh_view('heimdal','g2dg');

ALTER TABLE heimdal.g2dg
    ADD CONSTRAINT hgdgpk1
        PRIMARY KEY (label_name, label_realm, label_container,
                     name, realm, container,
                     verb_name, verb_realm, verb_container);

CREATE INDEX g2dg2 ON heimdal.g2dg
    (name, realm, container,
     label_name, label_realm, label_container,
     verb_name, verb_realm, verb_container);



/*
 * HDB VIEWs and INSTEAD OF triggers for interfacing libhdb to HDBs hosted on
 * PG with the above schema.
 *
 * Many of these VIEWs and associated TRIGGERs could be auto-generated from the
 * schema.  We might need to enrich the schema with JSON-encoded COMMENTary.
 */

CREATE OR REPLACE VIEW hdb.modified_info AS
SELECT name AS name, realm AS realm, container AS container,
       modified_by AS modified_by, modified_at AS modified_at
FROM heimdal.principals;

CREATE OR REPLACE VIEW hdb.key AS
SELECT
    k.name AS name, k.realm AS realm, k.kvno AS kvno,
    jsonb_build_object('ktype',k.ktype::text,
                       'etype',k.etype::text,
                       'set_at',
                            CASE coalesce(current_setting('hdb.test',true), 'false')
                            WHEN 'true' THEN k.created_at::text
                            ELSE '1970-01-01 00:00:00'::timestamp without time zone::text END,
                       'kvno',k.kvno::bigint,
                       'mkvno',k.mkvno::bigint,
                       'salt',k.salt::text,
                       'key',encode(k.key, 'base64')) AS key
FROM heimdal.keys k
WHERE k.enabled AND k.valid_start <= current_timestamp AND
      k.valid_end > current_timestamp;

CREATE OR REPLACE VIEW hdb.keyset AS
SELECT ks.name AS name, ks.realm AS realm, ks.kvno AS kvno, jsonb_agg(ks.key ORDER BY ks.key) AS keys
FROM hdb.key ks
GROUP BY ks.name, ks.realm, ks.kvno;

CREATE OR REPLACE VIEW hdb.keysets AS
SELECT ks.name AS name, ks.realm AS realm, 'keysets' AS extname,
       jsonb_agg(ks.keys ORDER BY ks.keys) AS ext
FROM hdb.keyset ks
WHERE NOT EXISTS (SELECT 1 FROM heimdal.principals p WHERE p.name = ks.name AND p.realm = ks.realm AND p.kvno = ks.kvno)
GROUP BY ks.name, ks.realm;

CREATE OR REPLACE VIEW hdb.aliases AS
SELECT a.name AS name, a.realm AS realm, 'aliases' AS extname,
       jsonb_agg(jsonb_build_object('alias_name',a.alias_name,
                                    'alias_realm',a.alias_realm) ORDER BY a.alias_name, a.alias_realm) AS ext
FROM heimdal.aliases a
WHERE container = 'PRINCIPAL'
GROUP BY a.name, a.realm;

CREATE OR REPLACE VIEW hdb.pwh1 AS
SELECT p.name AS name, p.realm AS realm,
       jsonb_build_object('mkvno',p.mkvno,
                          'etype',p.etype::text,
                          'digest_alg',p.digest_alg::text,
                          'digest',encode(p.digest, 'base64'),
                          'set_at',
                            CASE coalesce(current_setting('hdb.test',true), 'false')
                            WHEN 'true' THEN p.created_at::text
                            ELSE '1970-01-01 00:00:00'::timestamp without time zone::text END
                          ) AS old_password
FROM heimdal.password_history p;

CREATE OR REPLACE VIEW hdb.pwh AS
SELECT p1.name AS name, p1.realm AS realm, 'password_history' AS extname,
       jsonb_agg(p1.old_password ORDER BY p1.old_password) AS ext
FROM hdb.pwh1 p1
GROUP BY p1.name, p1.realm;

/*
 * XXX Finish, add all remaining hdb entry extensions here:
 *
 *  - PKINIT cert hashes
 *  - PKINIT cert names
 *  - PKINIT certs
 *  - S4U constrained delegation ACLs
 */

CREATE OR REPLACE VIEW hdb.flags AS
SELECT p.name AS name, p.realm AS realm, jsonb_agg(p.flag::text ORDER BY p.flag) AS flags
FROM heimdal.principal_flags p
WHERE valid_end > current_timestamp
GROUP BY p.name, p.realm;

CREATE OR REPLACE VIEW hdb.etypes AS
SELECT p.name AS name, p.realm AS realm, jsonb_agg(p.etype::text ORDER BY p.etype) AS etypes
FROM heimdal.principal_etypes p
WHERE valid_end > current_timestamp
GROUP BY p.name, p.realm;

CREATE OR REPLACE VIEW hdb.hdb AS
/* Principals */
SELECT e.display_name AS display_name, e.name AS name, e.realm AS realm,
       jsonb_build_object(
            'name',e.name,
            'realm',e.realm,
            'kvno',p.kvno,
            'keys',keys.keys,
            'name_type',p.name_type,
            'created_by',e.created_by,
            'created_at',e.created_at::text,
            'modified_by',modinfo.modified_by,
            'modified_at',modinfo.modified_at::text,
            'password',p.password::text,
            'valid_start',p.valid_start::text,
            'valid_end',p.valid_end::text,
            'pw_life',p.pw_life::text,
            'pw_end',p.pw_end::text,
            'last_pw_change',p.last_pw_change::text,
            'max_life',coalesce(p.max_life::text,''),
            'max_renew',coalesce(p.max_renew::text,''),
            'flags',coalesce(flags.flags,'[]'::jsonb),
            'etypes',coalesce(etypes.etypes,jsonb_build_array()),
            'aliases',a.ext,
            'keysets',keysets.ext,
            'password_history',pwh.ext) AS entry
FROM heimdal.entities e
JOIN hdb.modified_info modinfo USING (name, realm, container)
JOIN heimdal.principals p USING (name, realm, container)
JOIN hdb.flags flags USING (name, realm)
LEFT JOIN hdb.aliases a USING (name, realm)
LEFT JOIN hdb.keysets keysets USING (name, realm)
LEFT JOIN hdb.pwh pwh USING (name, realm)
LEFT JOIN hdb.etypes etypes ON e.name = etypes.name AND e.realm = etypes.realm
LEFT JOIN hdb.keyset keys ON p.name = keys.name AND p.realm = keys.realm AND p.kvno = keys.kvno
WHERE e.container = 'PRINCIPAL' AND
      p.valid_start <= current_timestamp AND p.valid_end > current_timestamp
UNION ALL
/* Aliases */
SELECT a.alias_name || '@' || a.alias_realm AS display_name,
       a.alias_name AS name, a.alias_realm AS realm,
       jsonb_build_object(
            'name',a.alias_name,
            'realm',a.alias_realm,
            'canon_name',p.name,
            'canon_realm',p.realm, /* Return to this -L */
            'created_by',a.created_by,
            'created_at',a.created_at::text,
            'modified_by',a.modified_by,
            'modified_at',a.modified_at::text) AS entry
FROM heimdal.aliases a
JOIN heimdal.principals p ON a.name = p.name AND a.realm = p.realm AND
                             a.container = p.container
WHERE a.container = 'PRINCIPAL' AND
      a.valid_start <= current_timestamp AND a.valid_end > current_timestamp AND
      p.valid_start <= current_timestamp AND p.valid_end > current_timestamp;

/* Create check function -L */

CREATE OR REPLACE FUNCTION heimdal.chk(
        _name TEXT, _realm TEXT, _container heimdal.containers,
        _object_name TEXT, _object_realm TEXT, _object_container heimdal.containers)
RETURNS BOOLEAN AS $$
    SELECT count(*) <> 0
    FROM (
            SELECT name, realm, container
            FROM heimdal.tcu
            WHERE member_name = _name AND member_realm = _realm AND
                  member_container = _container
        INTERSECT
            SELECT owner_name, owner_realm, owner_container
            FROM heimdal.entities
            WHERE name = _object_name AND realm = _object_realm AND
                  container = _object_container
    ) q;
; $$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION heimdal.chk(
        _name TEXT, _realm TEXT, _container heimdal.containers,
        _verb_name TEXT, _verb_realm TEXT, _verb_container heimdal.containers,
        _label_name TEXT, _label_realm TEXT, _label_container heimdal.containers)
RETURNS BOOLEAN AS $$
    SELECT count(*) <> 0
    FROM (
            SELECT name, realm, container
            FROM heimdal.tcu
            WHERE member_name = _name AND member_realm = _realm AND
                  member_container = _container
        INTERSECT
            SELECT name, realm, container
            FROM heimdal.g2dg
            WHERE label_name = _label_name AND label_realm = _label_realm AND
                  label_container = _label_container AND
                  verb_name = _verb_name AND verb_realm = _verb_realm AND
                  verb_container = _verb_container
    ) q;
; $$ LANGUAGE SQL;

/* Create triggers on heimdal inserts -L */

/* XXX This function is kinda sloppy and should be redone -L */
/* Reverse cascade from non-entities to entities */
CREATE OR REPLACE FUNCTION heimdal.trigger_on_entities_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.entity_type = 'GROUP' THEN
        INSERT INTO heimdal.tc (name, realm, container,
                                member_name, member_realm, member_container)
        SELECT NEW.name, NEW.realm, NEW.container,
               NEW.name, NEW.realm, NEW.container;
    END IF;
    IF TG_TABLE_NAME = 'entities' THEN
        NEW.display_name :=
            CASE NEW.entity_type
            WHEN 'PRINCIPAL' THEN NEW.name || '@' || NEW.realm
            ELSE lower(NEW.entity_type::TEXT) || ': ' || NEW.name || '@' || lower(NEW.realm)
            END;
    END IF;
    IF TG_OP = 'UPDATE' AND TG_WHEN = 'AFTER' THEN
        UPDATE heimdal.principals SET display_name = NULL WHERE name = NEW.name AND realm = NEW.realm;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER before_on_heimdal_entities_set_display_name
BEFORE INSERT OR UPDATE
ON heimdal.entities
FOR EACH ROW
EXECUTE FUNCTION heimdal.trigger_on_entities_func();

CREATE TRIGGER after_on_heimdal_entities_set_display_name
AFTER UPDATE
ON heimdal.entities
FOR EACH ROW
EXECUTE FUNCTION heimdal.trigger_on_entities_func();

CREATE OR REPLACE FUNCTION heimdal.trigger_on_principals_func()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO heimdal.entities
        (name, realm, container, entity_type)
    SELECT NEW.name, NEW.realm, 'PRINCIPAL', 'PRINCIPAL'
    ON CONFLICT DO NOTHING;

    NEW.display_name := (
        SELECT e.display_name FROM heimdal.entities e WHERE e.name = NEW.name AND
                                                            e.realm = NEW.realm AND
                                                            e.container = 'PRINCIPAL');
    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER before_on_heimdal_principals_set_display_name
BEFORE INSERT
ON heimdal.principals
FOR EACH ROW
EXECUTE FUNCTION heimdal.trigger_on_principals_func();

CREATE OR REPLACE FUNCTION heimdal.trigger_on_members_func()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'UPDATE' THEN
        RETURN NULL; /* XXX Raise instead */
    END IF;

    /* DELETE GOES HERE */
    IF TG_OP = 'DELETE' THEN
        WITH RECURSIVE parents AS (
            SELECT OLD.name AS name, OLD.realm AS realm,
                   OLD.container AS container
            UNION
            SELECT m.name, m.realm, m.container
            FROM heimdal.members m
            JOIN parents p ON m.member_name = p.name AND
                              m.member_realm = p.realm AND
                              m.member_container = p.container
        ), rmembers AS (
            SELECT OLD.member_name AS name, OLD.member_realm AS realm,
                   OLD.member_container AS container
            UNION
            SELECT m.member_name, m.member_realm, m.member_container
            FROM heimdal.members m
            JOIN rmembers mem ON m.name = mem.name AND
                                 m.realm = mem.realm AND
                                 m.container = mem.container
        ), exceptions AS (
            SELECT mem.name AS member_name,
                   mem.realm AS member_realm,
                   mem.container AS member_container,
                   mem.name AS name,
                   mem.realm AS realm,
                   mem.container AS container
            FROM rmembers mem
            UNION
            SELECT exc.member_name,
                   exc.member_realm,
                   exc.member_container,
                   m.name,
                   m.realm,
                   m.container
            FROM heimdal.members m
            JOIN exceptions exc ON m.member_name = exc.name AND
                                   m.member_realm = exc.realm AND
                                   m.member_container = exc.container
        ), deletions AS (
            SELECT p.name AS name,
                   p.realm AS realm,
                   p.container AS container,
                   m.name AS member_name,
                   m.realm AS member_realm,
                   m.container AS member_container
            FROM
            parents p
            CROSS JOIN
            rmembers m
            EXCEPT
            SELECT exc.name,
                   exc.realm,
                   exc.container,
                   exc.member_name,
                   exc.member_realm,
                   exc.member_container
            FROM exceptions exc
        )

        DELETE FROM heimdal.tc AS tc
        USING deletions d
        WHERE tc.name = d.name AND
              tc.realm = d.realm AND
              tc.container = d.container AND
              tc.member_name = d.member_name AND
              tc.member_realm = d.member_realm AND
              tc.member_container = d.member_container;

        PERFORM mat_views.set_needs_refresh('heimdal','tcu');

        RETURN OLD;
    END IF;

    IF NOT EXISTS
        (SELECT 1 FROM heimdal.entities e
         WHERE e.name = NEW.name AND e.realm = NEW.realm AND
               e.container = NEW.container AND e.entity_type = 'GROUP') OR
       NOT EXISTS
        (SELECT 1 FROM heimdal.entities e
         WHERE e.name = NEW.member_name AND e.realm = NEW.member_realm AND
               e.container = NEW.member_container AND
               (e.entity_type = 'GROUP' OR e.entity_type = 'USER')) THEN
        RETURN NULL; /* XXX Raise instead */
    END IF;

    WITH RECURSIVE parents AS (
        SELECT NEW.name AS name, NEW.realm AS realm, NEW.container AS container
        UNION
        SELECT m.name, m.realm, m.container
        FROM heimdal.members m
        JOIN parents p ON (m.member_name = p.name AND
                           m.member_realm = p.realm AND
                           m.member_container = p.container)
    ), rmembers AS (
        SELECT NEW.member_name AS name, NEW.member_realm AS realm,
               NEW.member_container AS container
        UNION
        SELECT m.member_name, m.member_realm, m.member_container
        FROM heimdal.members m
        JOIN rmembers mem ON (m.name = mem.name AND
                             m.realm = mem.realm AND
                             m.container = mem.container)
    )
    INSERT INTO heimdal.tc (name, realm, container,
                            member_name, member_realm, member_container)
    SELECT p.name, p.realm, p.container,
           m.name, m.realm, m.container
    FROM
    parents p /* All related parents */
    CROSS JOIN
    rmembers m /* All related members */
    JOIN heimdal.entities e ON (m.name = e.name AND
                                m.realm = e.realm AND
                                m.container = e.container)
    WHERE e.entity_type = 'GROUP'
    ON CONFLICT DO NOTHING;

    PERFORM mat_views.set_needs_refresh('heimdal','tcu');

    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER trigger_on_heimdal_members_transitive_closure_before
BEFORE UPDATE
ON heimdal.members
FOR EACH ROW
EXECUTE FUNCTION heimdal.trigger_on_members_func();

CREATE TRIGGER trigger_on_heimdal_members_transitive_closure_after
AFTER INSERT OR DELETE
ON heimdal.members
FOR EACH ROW
EXECUTE FUNCTION heimdal.trigger_on_members_func();

CREATE OR REPLACE FUNCTION heimdal.trigger_on_grants_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN

        WITH deletions AS (
                SELECT OLD.label_name AS label_name, OLD.label_realm AS label_realm,
                       OLD.label_container AS label_container, rv.verb_name AS verb_name,
                       rv.verb_realm AS verb_realm, rv.verb_container AS verb_container,
                       OLD.name AS name, OLD.realm AS realm,
                       OLD.container AS container
                FROM
                heimdal.roles2verbs rv
            EXCEPT
                SELECT gt.label_name, gt.label_realm, gt.label_container,
                       rv.verb_name, rv.verb_realm, rv.verb_container,
                       gt.name, gt.realm, gt.container
                FROM
                heimdal.grants gt
                JOIN
                heimdal.roles2verbs rv
                ON rv.name = gt.role_name AND rv.realm = gt.role_realm AND
                   rv.container = gt.role_container
                WHERE gt.label_name = OLD.label_name AND gt.label_realm = OLD.label_realm AND
                      gt.label_container = OLD.label_container AND gt.name = OLD.name AND
                      gt.realm = OLD.realm AND gt.container = OLD.container
        )
        DELETE FROM heimdal.g2dg g2dg
        USING deletions d
        WHERE g2dg.label_name = d.label_name AND g2dg.label_realm = d.label_realm AND
              g2dg.label_container = d.label_container AND g2dg.verb_name = d.verb_name AND
              g2dg.verb_realm = d.verb_realm AND g2dg.verb_container = d.verb_container AND
              g2dg.name = d.name AND g2dg.realm = d.realm AND
              g2dg.container = d.container;

        RETURN OLD;
    END IF;

    IF NOT EXISTS
        (SELECT 1 FROM heimdal.entities e
         WHERE e.name = NEW.label_name AND e.realm = NEW.label_realm AND
               e.container = NEW.label_container AND e.entity_type = 'LABEL') OR
       NOT EXISTS
        (SELECT 1 FROM heimdal.entities e
         WHERE e.name = NEW.role_name AND e.realm = NEW.role_realm AND
               e.container = NEW.role_container AND e.entity_type = 'ROLE') OR
       NOT EXISTS
        (SELECT 1 FROM heimdal.entities e
         WHERE e.name = NEW.name AND e.realm = NEW.realm AND
               e.container = NEW.container AND
               (e.entity_type = 'GROUP' OR e.entity_type = 'USER')) THEN
        RETURN NULL; /* XXX Raise instead */
    END IF;

    INSERT INTO heimdal.g2dg /* XXX name of view */ (label_name, label_realm, label_container,
                                                     verb_name, verb_realm, verb_container,
                                                     name, realm, container)
    SELECT NEW.label_name, NEW.label_realm, NEW.label_container,
           rv.verb_name, rv.verb_realm, rv.verb_container,
           NEW.name, NEW.realm, NEW.container
    FROM
    heimdal.roles2verbs rv
    WHERE rv.name = NEW.role_name AND
          rv.realm = NEW.role_realm AND rv.container = NEW.role_container
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER trigger_on_heimdal_grants
AFTER INSERT OR DELETE
ON heimdal.grants
FOR EACH ROW
EXECUTE FUNCTION heimdal.trigger_on_grants_func();

CREATE OR REPLACE FUNCTION heimdal.trigger_on_aliases_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM heimdal.entities AS e
        WHERE e.name = OLD.alias_name AND e.container = 'PRINCIPAL' AND e.realm = OLD.alias_realm;
        RETURN OLD;
    END IF;

    IF NEW.container <> 'PRINCIPAL' OR NEW.alias_container <> 'PRINCIPAL' THEN
        RETURN NULL; /* XXX Raise instead */
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF OLD.name <> NEW.name OR OLD.realm <> NEW.realm THEN
            UPDATE heimdal.entities SET name = NEW.name, realm = NEW.realm
            WHERE name = OLD.name AND realm = OLD.realm AND container = 'PRINCIPAL';
        END IF;
        IF OLD.alias_name <> NEW.alias_name OR OLD.alias_realm <> NEW.alias_realm THEN
            /*
             * Here we work around the FK ON UPDATE action on heimdal.aliases
             * by simply creating a new entity before the OLD->NEW update, and
             * then deleting the old one after the update.
             *
             * FIXME This has alias swap considerations that we'll leave for
             * another day.
             */
             UPDATE heimdal.entities SET name = NEW.alias_name, realm = NEW.alias_realm
             WHERE name = OLD.alias_name AND realm = OLD.alias_realm AND container = 'PRINCIPAL';
        END IF;
        RETURN NEW;
    END IF;

    INSERT INTO heimdal.entities (name, container, realm, entity_type)
    SELECT NEW.alias_name, 'PRINCIPAL', NEW.alias_realm, 'PRINCIPAL';
    INSERT INTO heimdal.principals (name, container, realm)
    SELECT NEW.alias_name, 'PRINCIPAL', NEW.alias_realm;
    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER before_on_heimdal_aliases
BEFORE INSERT OR UPDATE
ON heimdal.aliases
FOR EACH ROW
EXECUTE FUNCTION heimdal.trigger_on_aliases_func();

CREATE TRIGGER after_on_heimdal_aliases
AFTER DELETE
ON heimdal.aliases
FOR EACH ROW
EXECUTE FUNCTION heimdal.trigger_on_aliases_func();

/* XXX Add INSTEAD OF triggers on HDB views */

CREATE OR REPLACE FUNCTION hdb.instead_of_on_keyset_func()
RETURNS TRIGGER AS $$
DECLARE
    fields JSONB;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        /* XXXX This is dead code because we never update this view */
        WITH deletions AS (
            SELECT kvno AS kvno, key AS key, ktype AS ktype, etype AS etype
            FROM heimdal.keys k
            WHERE k.name = NEW.name AND k.realm = NEW.realm AND k.container = 'PRINCIPAL'
            EXCEPT
            SELECT (q.js->>'kvno'::text)::bigint,
                   decode(q.js->>'key', 'base64')::bytea,
                   (q.js->>'ktype'::text)::heimdal.key_type,
                   (q.js->>'etype'::text)::heimdal.enc_type
            FROM (SELECT jsonb_array_elements(NEW.keys)) q(js))
        DELETE FROM heimdal.keys AS k
        USING deletions d
        WHERE k.name = NEW.name AND k.realm = NEW.realm AND k.container = 'PRINCIPAL' AND
              k.kvno = d.kvno AND k.key = d.key AND k.ktype = d.ktype AND k.etype = d.etype;
    END IF;
    INSERT INTO heimdal.keys
        (name, container, realm, kvno, ktype, etype, key, salt, mkvno)
    SELECT NEW.name, 'PRINCIPAL', NEW.realm,
           (k->>'kvno'::text)::bigint,
           (k->>'ktype'::text)::heimdal.key_type,
           (k->>'etype'::text)::heimdal.enc_type,
           decode(k->>'key', 'base64')::bytea,
           (k->>'salt'::text)::heimdal.salt, (k->>'mkvno'::text)::bigint
    FROM jsonb_array_elements(NEW.keys) k
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER instead_of_on_hdb_keyset
INSTEAD OF INSERT OR UPDATE
ON hdb.keyset
FOR EACH ROW
EXECUTE FUNCTION hdb.instead_of_on_keyset_func();

/* XXX Think about trigger firing order vs FK cascading order */
CREATE OR REPLACE FUNCTION hdb.instead_of_on_aliases_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        /* Delete aliases that existed but don't appear in 'ext' -- they're getting dropped*/
        /* XXX call this deletions, do the select EXCEPT select thing we do for pwh */
        WITH new_aliases AS (
            -- New aliases
            SELECT (q.js->>'alias_name') AS alias_name,
                   (q.js->>'alias_realm') AS alias_realm FROM jsonb_array_elements(NEW.ext) q(js))
        DELETE FROM heimdal.aliases AS a
        USING new_aliases AS n
        WHERE a.name = NEW.name AND a.realm = NEW.realm /* XXX this assumes this trigger runs after cascades */ AND
              a.container = 'PRINCIPAL' AND
              -- Delete existing aliases that are not in the new alias list
              NOT EXISTS (SELECT 1 FROM new_aliases n WHERE n.alias_name = a.alias_name AND n.alias_realm = a.alias_realm);
    END IF;

    /* Insert any [new] aliases that aren't repeats, on conflict do nothing fails due to trigger_on_aliases_func() */
    WITH new_aliases AS (
             -- New aliases
        SELECT NEW.name AS name, NEW.realm AS realm,
               (q.js->>'alias_name') AS alias_name,
               (q.js->>'alias_realm') AS alias_realm FROM jsonb_array_elements(NEW.ext) q(js))
    INSERT INTO heimdal.aliases
        (name, container, realm, alias_name, alias_container, alias_realm)
    SELECT NEW.name, 'PRINCIPAL', NEW.realm,
           n.alias_name, 'PRINCIPAL', n.alias_realm
    FROM new_aliases n
    LEFT OUTER JOIN heimdal.aliases USING (name, realm, alias_name, alias_realm);
    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER instead_of_on_hdb_aliases
INSTEAD OF INSERT OR UPDATE
ON hdb.aliases
FOR EACH ROW
EXECUTE FUNCTION hdb.instead_of_on_aliases_func();

CREATE OR REPLACE FUNCTION hdb.instead_of_on_keysets_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        /* Delete keysets that existed but don't appear in 'ext' -- they're getting dropped*/
        WITH new_keysets AS (
            SELECT (q.js->>'kvno'::text)::bigint AS kvno,
                   decode(q.js->>'key', 'base64')::bytea AS key,
                   (q.js->>'ktype'::text)::heimdal.key_type AS ktype,
                   (q.js->>'etype'::text)::heimdal.enc_type AS etype
            FROM (SELECT jsonb_array_elements(q.js)
                  FROM (SELECT jsonb_array_elements(NEW.ext)) q(js)) q(js))
        DELETE FROM heimdal.keys AS k
        WHERE k.name = NEW.name AND k.realm = NEW.realm AND k.container = 'PRINCIPAL' AND
              NOT EXISTS (SELECT 1 FROM new_keysets n
                          WHERE n.name = k.name   AND n.realm = k.realm AND
                                n.kvno = k.kvno   AND n.key = k.key AND
                                n.ktype = k.ktype AND n.etype = k.etype);
    END IF;

    /* Insert any [new] entries */
    INSERT INTO heimdal.keys
        (name, container, realm, kvno, ktype, etype, key, salt, mkvno)
    SELECT NEW.name, 'PRINCIPAL', NEW.realm,
        (e.entry->>'kvno'::text)::bigint, (e.entry->>'ktype'::text)::heimdal.key_type,
        (e.entry->>'etype'::text)::heimdal.enc_type, decode(e.entry->>'key', 'base64')::bytea,
        (e.entry->>'salt'::text)::heimdal.salt, (e.entry->>'mkvno'::text)::bigint
    FROM (SELECT jsonb_array_elements(e) FROM jsonb_array_elements(NEW.ext) e(e)) AS e(entry)
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END; $$ LANGUAGE PLPGSQL;

CREATE TRIGGER instead_of_on_hdb_keysets
INSTEAD OF INSERT OR UPDATE
ON hdb.keysets
FOR EACH ROW
EXECUTE FUNCTION hdb.instead_of_on_keysets_func();

CREATE OR REPLACE FUNCTION hdb.instead_of_on_pwh_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        /* Delete aliases that existed but don't appear in 'ext' -- they're getting dropped*/
        WITH deletions AS (
                /* Old entries... */
                SELECT (p.js->>'digest_alg'::text)::heimdal.digest_type AS digest_alg,
                       (p.js->>'digest') AS digest,
                       (p.js->>'etype'::text)::heimdal.enc_type AS etype,
                       (p.js->>'mkvno'::text)::bigint AS mkvno
                FROM (SELECT jsonb_array_elements(ext)
                      FROM hdb.pwh p
                      WHERE p.name = NEW.name AND p.realm = NEW.realm) p(js)
            EXCEPT
                /* minus new entries == entries to delete */
                SELECT (p.js->>'digest_alg'::text)::heimdal.digest_type AS digest_alg,
                       (p.js->>'digest') AS digest,
                       (p.js->>'etype'::text)::heimdal.enc_type AS etype,
                       (p.js->>'mkvno'::text)::bigint AS mkvno
                FROM jsonb_array_elements(NEW.ext) p(js))
        DELETE FROM heimdal.password_history AS p
        USING deletions AS d
        WHERE p.name = NEW.name AND p.realm = NEW.realm /* XXX this assumes this trigger runs after cascades */ AND
              p.container = 'PRINCIPAL' AND
              p.mkvno = d.mkvno AND
              p.digest_alg = d.digest_alg AND
              p.digest = decode(d.digest,'base64')::bytea;
    END IF;

    /* Insert any [new] entries */
    WITH additions AS (
            SELECT (q.js->>'digest_alg'::text)::heimdal.digest_type AS digest_alg,
                   (q.js->>'digest') AS digest,
                   (q.js->>'etype'::text)::heimdal.enc_type AS etype,
                   (q.js->>'mkvno'::text)::bigint AS mkvno
            FROM jsonb_array_elements(NEW.ext) q(js)
        EXCEPT
            SELECT (p.js->>'digest_alg'::text)::heimdal.digest_type AS digest_alg,
                   (p.js->>'digest') AS digest,
                   (p.js->>'etype'::text)::heimdal.enc_type AS etype,
                   (p.js->>'mkvno'::text)::bigint AS mkvno
            FROM (SELECT jsonb_array_elements(ext)
                  FROM hdb.pwh p
                  WHERE p.name = NEW.name AND p.realm = NEW.realm) p(js))
    INSERT INTO heimdal.password_history (name, container, realm, etype, digest_alg, digest, mkvno, created_at)
    SELECT NEW.name, 'PRINCIPAL', NEW.realm, a.etype, a.digest_alg,
           decode(a.digest, 'base64')::bytea, a.mkvno, coalesce(p.created_at, current_timestamp)
    FROM additions a
    LEFT JOIN heimdal.password_history p ON p.name = NEW.name AND p.realm = NEW.realm
    ON CONFLICT DO NOTHING;
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
    r      RECORD;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.display_name IS NULL THEN /* Return here -L */
            OLD.display_name := ((OLD.entry)->>'name'::TEXT) || '@' || ((OLD.entry)->>'realm'::TEXT);
        END IF;
        IF OLD.display_name IS NULL THEN
            RETURN OLD; /* XXX Raise instead */
        END IF;

        DELETE FROM heimdal.entities e where e.display_name = OLD.display_name;

        RETURN OLD;
    END IF;

    IF (NEW.entry) IS NULL OR (NEW.entry)->'name' IS NULL THEN /* Return here -L */
        RETURN NEW; /* XXX Raise instead */
    END IF;
    NEW.display_name := ((NEW.entry)->>'name'::TEXT) || '@' || ((NEW.entry)->>'realm'::TEXT);

    IF TG_OP = 'INSERT' THEN
        /* Add the principal's base entity */
        INSERT INTO heimdal.entities
            (name, container, realm, entity_type, policy)
        SELECT (NEW.entry)->>'name',  'PRINCIPAL',
               (NEW.entry)->>'realm', 'PRINCIPAL',
                (NEW.entry)->'policy';

        /* Add the principal */
        INSERT INTO heimdal.principals
            (name, container, realm, kvno, pw_life, pw_end,
             max_life, max_renew, password)
        SELECT (NEW.entry)->>'name', 'PRINCIPAL', (NEW.entry)->>'realm', ((NEW.entry)->'kvno')::text::bigint,
               ((NEW.entry)->>'pw_life'::text)::interval, ((NEW.entry)->>'pw_end'::text)::timestamp without time zone,
               coalesce(((NEW.entry)->>'max_life'::text)::interval), coalesce(((NEW.entry)->>'max_renew'::text)::interval),
               (NEW.entry)->>'password';

        /* Add its normalized flags */
        INSERT INTO heimdal.principal_flags
            (name, container, realm, flag)
        SELECT (NEW.entry)->>'name', 'PRINCIPAL', (NEW.entry)->>'realm', (flag::text)::heimdal.princ_flags
        FROM jsonb_array_elements_text((NEW.entry)->'flags') f(flag);

        /* Add its enc_types */
        INSERT INTO heimdal.principal_etypes
            (name, container, realm, etype)
        SELECT (NEW.entry)->>'name', 'PRINCIPAL', (NEW.entry)->>'realm', (etype::text)::heimdal.enc_type
        FROM jsonb_array_elements_text((NEW.entry)->'etypes') e(etype);

        /* Insert current keyset indirectly via INSTEAD OF INSERT TRIGGER on hdb.keyset */
        INSERT INTO hdb.keyset (name, realm, keys)
        SELECT (NEW.entry)->>'name', (NEW.entry)->>'realm', (NEW.entry)->'keys';

        /* Insert extensions directly via INSTEAD OF INSERT TRIGGERS on hdb views */
        INSERT INTO hdb.keysets (name, realm, ext)
        SELECT (NEW.entry)->>'name', (NEW.entry)->>'realm', (NEW.entry)->'keysets';

        INSERT INTO hdb.aliases (name, realm, ext)
        SELECT (NEW.entry)->>'name', (NEW.entry)->>'realm', (NEW.entry)->'aliases';

        INSERT INTO hdb.pwh (name, realm, ext)
        SELECT (NEW.entry)->>'name', (NEW.entry)->>'realm', (NEW.entry)->'password_history';
        RETURN NEW;
    END IF;

    /* UPDATE a principal or alias */

    /* Update extensions indirectly via INSTEAD OF UPDATE TRIGGER on hdb.exts */

    /* Get the list of fields to update */
    fields := NEW.entry->'kadm5_fields';

    IF OLD.name IS NULL THEN
        OLD.name := NEW.name; /* Return here -L */
    END IF;

    /* First update everything starting with the name */
    IF OLD.name <> NEW.name OR OLD.realm <> NEW.realm THEN
        UPDATE heimdal.entities
        SET name = NEW.name, realm = NEW.realm
        WHERE name = OLD.name AND realm = OLD.realm AND container = 'PRINCIPAL';
    END IF;
    IF (fields IS NULL OR fields->'kvno' IS NOT NULL) AND
       OLD.entry->>'kvno' <> NEW.entry->>'kvno' THEN
        UPDATE heimdal.principals
        SET kvno = (NEW.entry->>'kvno')::bigint
        WHERE name = NEW.name AND realm = NEW.realm AND container = 'PRINCIPAL';
    END IF;
    IF (fields IS NULL OR fields->'principal_expire_time' IS NOT NULL) AND
       OLD.entry->>'valid_end' <> NEW.entry->>'valid_end' THEN
        UPDATE heimdal.principals
        SET valid_end = (NEW.entry->>'valid_end')::timestamp without time zone
        WHERE name = NEW.name AND realm = NEW.realm AND container = 'PRINCIPAL';
    END IF;
    IF (fields IS NULL OR fields->'pw_expiration' IS NOT NULL) AND
       OLD.entry->>'pw_end' <> NEW.entry->>'pw_end' THEN
        UPDATE heimdal.principals
        SET pw_end = (NEW.entry->>'pw_end')::timestamp without time zone
        WHERE name = NEW.name AND realm = NEW.realm AND container = 'PRINCIPAL';
    END IF;
    IF (fields IS NULL OR fields->'last_pwd_change' IS NOT NULL) AND
        OLD.entry->>'last_pw_change' <> NEW.entry->>'last_pw_change' THEN
        UPDATE heimdal.principals
        SET last_pw_change = (NEW.entry->>'last_pw_change')::timestamp without time zone
        WHERE name = NEW.name AND realm = NEW.realm AND container = 'PRINCIPAL';
    END IF;
    IF (fields IS NULL OR fields->'max_life' IS NOT NULL) AND
       OLD.entry->>'max_life' <> NEW.entry->>'max_life' THEN
        UPDATE heimdal.principals
        SET max_life = (NEW.entry->>'max_life')::interval
        WHERE name = NEW.name AND realm = NEW.realm AND container = 'PRINCIPAL';
    END IF;
    IF (fields IS NULL OR fields->'max_renew' IS NOT NULL) AND
       OLD.entry->>'max_renew' <> NEW.entry->>'max_renew' THEN
        UPDATE heimdal.principals
        SET max_renew = (NEW.entry->>'max_renew')::interval
        WHERE name = NEW.name AND realm = NEW.realm AND container = 'PRINCIPAL';
    END IF;
    IF (fields IS NULL OR fields->'attributes' IS NOT NULL) AND
       OLD.entry->>'flags' <> NEW.entry->>'flags' THEN
        WITH new_flags AS (
            SELECT NEW.name AS name, NEW.realm AS realm, f.flag::heimdal.princ_flags AS flag
            FROM jsonb_array_elements_text(NEW.entry->'flags') f(flag))

        DELETE FROM heimdal.principal_flags AS pf
        WHERE pf.name = NEW.name AND pf.realm = NEW.realm AND container = 'PRINCIPAL' AND
              NOT EXISTS (SELECT 1 FROM new_flags n WHERE n.name = pf.name AND n.realm = pf.realm AND n.flag = pf.flag);

        INSERT INTO heimdal.principal_flags
            (name, container, realm, flag)
        SELECT NEW.name, 'PRINCIPAL', NEW.realm, (jsonb_array_elements_text(NEW.entry->'flags'))::heimdal.princ_flags
        ON CONFLICT DO NOTHING;
    END IF;
    IF (fields IS NULL OR fields->'password' IS NOT NULL) AND
       OLD.entry->>'password' <> NEW.entry->>'password' THEN
        UPDATE heimdal.principals
        SET password = (NEW.entry)->>'password'
        WHERE name = (NEW.entry)->>'name' AND realm = (NEW.entry)->>'realm' AND (NEW.entry)->>'password' IS NOT NULL;
    END IF;
    IF (fields IS NULL OR fields->'etypes' IS NOT NULL) AND
       OLD.entry->>'etypes' <> NEW.entry->>'etypes' THEN
        /* XXX FIXME */
        WITH new_etypes AS (
            SELECT NEW.name AS name, NEW.realm AS realm, e.etype::heimdal.enc_type AS etype
            FROM jsonb_array_elements_text(NEW.entry->'etypes') e(etype))

        DELETE FROM heimdal.principal_etypes AS pe
        WHERE pe.name = NEW.name AND pe.realm = NEW.realm AND container = 'PRINCIPAL' AND
              NOT EXISTS (SELECT 1 FROM new_etypes n WHERE n.name = pe.name AND n.realm = pe.realm AND n.etype = pe.etype);

        INSERT INTO heimdal.principal_etypes
            (name, container, realm, etype)
        SELECT NEW.name, 'PRINCIPAL', NEW.realm, (jsonb_array_elements_text(NEW.entry->'etypes'))::heimdal.enc_type
        ON CONFLICT DO NOTHING;
    END IF;

    IF (fields IS NULL OR fields->'aliases' IS NOT NULL) AND
        OLD.entry->'aliases' <> NEW.entry->'aliases' THEN
        UPDATE hdb.aliases
        SET ext = NEW.entry->'aliases'
        WHERE name = (NEW.entry)->>'name' AND realm = (NEW.entry)->>'realm';
    END IF;

    IF (fields IS NULL OR fields->'password_history' IS NOT NULL) AND
        OLD.entry->'password_history' <> NEW.entry->'password_history' THEN
        UPDATE hdb.pwh
        SET ext = NEW.entry->'password_history'
        WHERE name = (NEW.entry)->>'name' AND realm = (NEW.entry)->>'realm';
    END IF;

    /* Update the keys for the principal.  This is a doozy */
    IF ((fields IS NULL OR fields->'keydata' IS NOT NULL) AND
       OLD.entry->>'keys' <> NEW.entry->>'keys') OR
       ((fields IS NULL OR fields->'keysets' IS NOT NULL) AND
       OLD.entry->>'keysets' <> NEW.entry->>'keysets') THEN
        /* First delete keys that we're dropping in this update */
        WITH new_keys AS (
            /*
             * We don't care whether a key appears in NEW.entry->>'keys' or in
             * the keysets extension.
             */
            SELECT NEW.name AS name, NEW.realm AS realm,
                   (q.js->>'kvno'::text)::bigint AS kvno,
                   decode(q.js->>'key', 'base64')::bytea AS key,
                   (q.js->>'ktype'::text)::heimdal.key_type AS ktype,
                   (q.js->>'etype'::text)::heimdal.enc_type AS etype
            FROM (SELECT jsonb_array_elements((NEW.entry)->'keys')) q(js)
            UNION
            SELECT NEW.name AS name, NEW.realm AS realm,
                   (q.js->>'kvno'::text)::bigint AS kvno,
                   decode(q.js->>'key', 'base64')::bytea AS key,
                   (q.js->>'ktype'::text)::heimdal.key_type AS ktype,
                   (q.js->>'etype'::text)::heimdal.enc_type AS etype
            FROM (SELECT jsonb_array_elements(q.js)
                  FROM (SELECT jsonb_array_elements(NEW.entry->'keysets')) q(js)) q(js))
        DELETE FROM heimdal.keys AS k
        WHERE k.name = NEW.name AND k.realm = NEW.realm AND container = 'PRINCIPAL' AND
              NOT EXISTS (SELECT 1 FROM new_keys n
                          WHERE n.name = k.name   AND n.realm = k.realm AND
                                n.kvno = k.kvno   AND n.key = k.key AND
                                n.ktype = k.ktype AND n.etype = k.etype);

        /*
         * Insert any new keys that didn't already exist (see the
         * ON CONFLICT clause).
         *
         * Again, we don't care whether a key appears as NEW.entry->'keys' or
         * the keysets extension.
         */
        INSERT INTO heimdal.keys (name, container, realm, kvno, ktype, etype, salt, mkvno, key)
        SELECT NEW.name, 'PRINCIPAL'::heimdal.containers, NEW.realm,
               (q.js->>'kvno'::text)::bigint,
               (q.js->>'ktype'::text)::heimdal.key_type,
               (q.js->>'etype'::text)::heimdal.enc_type,
               (q.js->>'salt'::text)::heimdal.salt,
               (q.js->>'mkvno'::text)::bigint,
               decode(q.js->>'key', 'base64')::bytea
        FROM (SELECT jsonb_array_elements((NEW.entry)->'keys')) q(js)
        UNION ALL
        SELECT NEW.name, 'PRINCIPAL'::heimdal.containers, NEW.realm,
               (q.js->>'kvno'::text)::bigint,
               (q.js->>'ktype'::text)::heimdal.key_type,
               (q.js->>'etype'::text)::heimdal.enc_type,
               (q.js->>'salt'::text)::heimdal.salt,
               (q.js->>'mkvno'::text)::bigint,
               decode(q.js->>'key', 'base64')::bytea
        FROM (SELECT jsonb_array_elements(q.js)
              FROM (SELECT jsonb_array_elements(NEW.entry->'keysets')) q(js)) q(js)
        ON CONFLICT DO NOTHING;

        /*
         * However!  We do want to leave the updated principal's current kvno
         * consistent with the new keys.
         */

        /*
         * If the principal was left with no keys, that's probably bad, so
         * we'll reject.
         *
         * If the previous current kvno no longer refers to any existing keys,
         * but the principal does have keys, then we'll fix its current kvno.
         */
        IF NOT EXISTS (
                SELECT 1
                FROM heimdal.keys k
                WHERE k.name = NEW.name AND k.realm = NEW.realm AND k.container = 'PRINCIPAL') THEN
            RAISE EXCEPTION 'Cannot update a principal and leave it with no keys (%@%)', NEW.name, NEW.realm;
        END IF;

        /*
         * If the previous current kvno no longer refers to any existing keys,
         * but the principal does have keys, then we'll fix its current
         * kvno by taking the kvno of the NEW.entry->'keys', or else the kvno
         * of the most recent key for the principal in heimdal.keys.
         */
        IF NOT EXISTS (
                SELECT 1
                FROM heimdal.keys k
                WHERE k.name = NEW.name AND k.realm = NEW.realm AND k.container = 'PRINCIPAL' AND
                      k.kvno = (NEW.entry->>'kvno')::bigint) THEN
            UPDATE heimdal.principals p
            SET kvno = (
                SELECT kvno
                FROM (
                    /* Prefer the kvno from NEW.entry->'keys'! (see ORDER BY) */
                    SELECT 1 AS o, ((NEW.entry->'keys')#>>'{keys,0,kvno}')::bigint AS kvno
                    WHERE (NEW.entry->'keys')#>'{keys,0,kvno}' IS NOT NULL
                    UNION ALL
                    /* Fallback on highest kvno from newest keys (see ORDER BY) */
                    SELECT 0, kvno
                    FROM (SELECT kvno AS kvno
                          FROM heimdal.keys k
                          WHERE k.name = NEW.name AND k.realm = NEW.realm AND k.container = 'PRINCIPAL'
                          ORDER BY modified_at DESC, kvno DESC LIMIT 1) q
                    ORDER BY 1 DESC LIMIT 1) q)
            WHERE p.name = NEW.name AND p.realm = NEW.realm AND p.container = 'PRINCIPAL';
        END IF;
    END IF;

    /* XXX Implement updating of all remaining extensions, namely the PKINIT ACLs */
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER instead_of_on_hdb
INSTEAD OF INSERT OR UPDATE OR DELETE
ON hdb.hdb
FOR EACH ROW
EXECUTE FUNCTION hdb.instead_of_on_hdb_func();
