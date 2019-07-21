/*
 * Recursive view for the trasitive closure expansion for group nesting,
 * and only group nesting.
 */
CREATE OR REPLACE VIEW heimdal.tc_view AS
WITH RECURSIVE groups AS (
    /* Seed with every group includes itself -- this is important */
    SELECT name AS parent_name, realm AS parent_realm, container AS parent_container,
           name AS member_name, realm AS member_realm, container AS member_container
    FROM heimdal.entities WHERE entity_type = 'GROUP'
    UNION
    /* Get the parents of all groups */
    SELECT m.parent_name, m.parent_realm, m.parent_container,
           m.member_name, m.member_realm, m.member_container
    FROM heimdal.members m JOIN groups g ON (m.member_name = g.parent_name AND m.member_realm = g.parent_realm AND m.member_container = g.parent_container)
)
SELECT * FROM groups;

/* Materialize the view -- we'll have triggers to keep it up to date */
SELECT mat_views.create_view('heimdal','tc', 'heimdal', 'tc_view');
/* Populate it (creating it doesn't do this) */
SELECT mat_views.refresh_view('heimdal','tc');
/* Look 'ma!  PG's MAT VIEWs do not allow this: */
ALTER TABLE heimdal.tc
    ADD CONSTRAINT htcpk1
	PRIMARY KEY (parent_name, parent_realm, parent_container,
                     member_name, member_realm, member_container);
/* nor this! */
CREATE INDEX tc2 ON heimdal.tc
    (member_name, member_realm, member_container,
     parent_name, parent_realm, parent_container);

/* Now a view for all the users' group memerships */
CREATE OR REPLACE VIEW heimdal.tcu AS
SELECT tc.parent_name, tc.parent_realm, tc.parent_container, e.name, e.realm, e.container
FROM heimdal.entities e
/* get direct memberships */
JOIN heimdal.members m ON (e.name = m.member_name AND e.realm = m.member_realm AND e.container = m.member_container)
/* get all remaining indirect memberships */
JOIN heimdal.tc tc ON (tc.member_name = m.parent_name AND tc.member_realm = m.parent_realm AND tc.member_container = m.parent_container)
WHERE e.entity_type = 'USER';
