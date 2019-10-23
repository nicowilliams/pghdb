/*
 * This file will contain:
 *
 *  - RLS rules
 * and/or
 *  - triggers
 *
 * and possibly
 *
 *  - a separate schema and views
 *
 * such that users that have access to this DB, either directly via psql, or
 * indirectly via an HTTP/REST server, can be authorized according to our
 * authorization system.  I.e., someone who owns a group or otherwise has admin
 * rights to it, could add a member to it, remove a member from it, and so on.
 */

DO $$
BEGIN
EXECUTE string_agg(q.code::TEXT, '')
FROM (SELECT format($q$
                CREATE OR REPLACE VIEW pgt.%1$I AS
                SELECT %2$s
                FROM heimdal.%1$I t
                JOIN LATERAL (SELECT TRUE WHERE FALSE -- XXX Replace FALSE with t.visible, if we add that column to common
                              UNION ALL
                              SELECT heimdal.chk((heimdal.split_name(current_user))[1], (heimdal.split_name(current_user))[2], 'USER',
                                                 t.name, t.realm, t.container)
                              UNION ALL
                              SELECT TRUE
                              FROM heimdal.entity_labels l
                              WHERE t.name = l.name AND
                                    t.realm = l.realm AND
                                    t.container = l.container AND
                                    heimdal.chk((heimdal.split_name(current_user))[1], (heimdal.split_name(current_user))[2], 'USER',
                                                'SEE', 'HEIMDAL_VERB', 'VERB',
                                                l.label_name, l.label_realm, l.label_container)
                              LIMIT 1) v
                ON TRUE;
            $q$,
                    t.table_name,
                    string_agg('t.' || c.column_name::TEXT, ', '  ORDER BY c.ordinal_position))
      FROM information_schema.tables t
      NATURAL
      JOIN information_schema.columns c
      WHERE t.table_schema = 'heimdal' AND t.table_name <> 'common' AND
            t.table_type = 'BASE TABLE' AND t.table_name NOT LIKE 'tc%' AND
            t.table_name NOT LIKE 'g2dg%' AND t.table_name <> 'digest_types' AND
            t.table_name <> 'enc_types' AND t.table_name <> 'policies'
      GROUP BY t.table_name
      ORDER BY t.table_name) q(code);

EXECUTE string_agg(q.code::TEXT, '')
FROM (SELECT format($q$
                CREATE OR REPLACE VIEW pgt.%1$I AS
                SELECT %2$s
                FROM heimdal.%1$I;
            $q$,
                    t.table_name,
                    string_agg(c.column_name::TEXT, ', '  ORDER BY c.ordinal_position))
      FROM information_schema.tables t
      NATURAL
      JOIN information_schema.columns c
      WHERE t.table_schema = 'heimdal' AND
                (t.table_name = 'digest_types' OR
                 t.table_name = 'enc_types' OR
                 t.table_name = 'policies')
      GROUP BY t.table_name
      ORDER BY t.table_name) q(code);

END; $$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION pgt.gen_instead_of_trigger(_schema text, _table text, _iverb_name text, _dverb_name text, _verb_realm text)
RETURNS VOID AS $$
BEGIN
    EXECUTE format($q$
        CREATE OR REPLACE FUNCTION pgt.%2$I()
        RETURNS TRIGGER AS $b$
        DECLARE
            permit BOOLEAN := TRUE;
        BEGIN
            /* First check the NEW row if we have one */
            IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
                IF NOT (heimdal.chk((heimdal.split_name(current_user))[1], (heimdal.split_name(current_user))[2], 'USER',
                                    NEW.name, NEW.realm, NEW.container) OR
                       (SELECT TRUE
                        FROM heimdal.entity_labels l
                        WHERE NEW.name = l.name AND
                              NEW.realm = l.realm AND
                              NEW.container = l.container AND
                              heimdal.chk((heimdal.split_name(current_user))[1], (heimdal.split_name(current_user))[2], 'USER',
                                          %9$L, %11$L, 'VERB',
                                          l.label_name, l.label_realm, l.label_container)
                        LIMIT 1)) THEN
                    permit := FALSE;
                END IF;
            END IF;

            /* Next check the OLD row if we have one */
            IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
                IF NOT (heimdal.chk((heimdal.split_name(current_user))[1], (heimdal.split_name(current_user))[2], 'USER',
                                    OLD.name, OLD.realm, OLD.container) OR
                       (SELECT TRUE
                        FROM heimdal.entity_labels l
                        WHERE OLD.name = l.name AND
                              OLD.realm = l.realm AND
                              OLD.container = l.container AND
                              heimdal.chk((heimdal.split_name(current_user))[1], (heimdal.split_name(current_user))[2], 'USER',
                                          %10$L, %11$L, 'VERB',
                                          l.label_name, l.label_realm, l.label_container)
                        LIMIT 1)) THEN
                    RAISE NOTICE 'WTF';
                    permit := FALSE;
                END IF;
            END IF;

            IF TG_OP = 'INSERT' THEN
                IF permit THEN
                    RAISE NOTICE 'INSERTING things';
                    INSERT INTO %1$I.%4$I (%5$s)
                    SELECT %6$s;
                ELSE
                    RAISE NOTICE 'NOT INSERTING things';
                END IF;
                RETURN NEW;
            ELSIF TG_OP = 'UPDATE' THEN
                IF permit THEN
                    RAISE NOTICE 'UPDATING things';
                    UPDATE %1$I.%4$I
                    SET %7$s;
                ELSE
                    RAISE NOTICE 'NOT UPDATING things';
                END IF;
                RETURN NEW;
            ELSIF TG_OP = 'DELETE' THEN
                IF permit THEN
                    RAISE NOTICE 'DELETING things';
                    DELETE FROM %1$I.%4$I
                    WHERE %8$s;
                ELSE
                    RAISE NOTICE 'NOT DELETING things';
                END IF;
                RETURN OLD;
            ELSE /* TRUNCATE -- do nothing */
                RETURN null;
            END IF;
        END; $b$ LANGUAGE PLPGSQL;

        CREATE TRIGGER %3$I
        INSTEAD OF INSERT OR UPDATE OR DELETE
        ON pgt.%4$I
        FOR EACH ROW
        EXECUTE FUNCTION pgt.%2$I();
        $q$,
        /* %1$I schema name */      _schema,
        /* %2$I function name */    _table || '_iud_security_func',
        /* %3$I function name */    _table || '_iud_security_trigger',
        /* %4$I table name */       _table,
        /* insert into (%5$s) */    string_agg(c.column_name::TEXT, ', '  ORDER BY c.ordinal_position),
        /* insert into select %6$s */string_agg(format('coalesce(NEW.%1$I, %2$s)',
                                                    c.column_name::text, coalesce(c.column_default::text, 'null')),
                                                ', ' ORDER BY c.ordinal_position),
        /* %7$s update list */      string_agg(c.column_name::text || ' = NEW.' || c.column_name::text, ', '),
        /* %8$s delete list */      string_agg(
                                        format('((%1$I IS NULL AND OLD.%1$I IS NULL) OR
                                                (%1$I IS NOT NULL AND OLD.%1$I IS NOT NULL AND %1$I = OLD.%1$I))',
                                               c.column_name::text),
                                        ' AND '
                                    ),
        /* %9$l iverb_name */       _iverb_name,
        /* %10$l dverb_name */      _dverb_name,
        /* %11$l verb_realm */      _verb_realm
        )
    FROM information_schema.columns c
    WHERE c.table_schema = _schema AND c.table_name = _table;
    RAISE NOTICE 'CREATED TRIGGER FOR %.%', _schema, _table;
END; $$ LANGUAGE PLPGSQL;
