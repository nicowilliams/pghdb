An Experiment in Normalizing the Heimdal HDB
============================================

The flat HDB/KDB principal representation in Heimdal and MIT Kerberos
are deeply unsatisfying for these and other reasons:

 - any interesting queries require full table scans

 - no mass administration capabilities

 - difficult to evolve (i.e., requires lots of code)

 - iprop pain; no multi-mastering

 - representation is too poor, requiring external systems and
   synchronization:

    - krb5\_admin
    - Wallet
    - Samba

Ultimately it all comes down to the HDB/KDB using fully denormalized
representations of what is actually complex, relational data.  This
screams for an RDBMS.

What Is This
============

The idea here is to normalize the HDB schema and use PostgreSQL +
PostgREST while keeping backwards compatibility with the existing HDB
for KDC performance reasons.

Backwards-compatibility entails denormalizing views and triggers on them so
that we can have a bridge from the past into the future.

Current plan:

 - Derive a highly normalized PG SQL schema from the `hdb_entry` type from
   lib/hdb/hdb.asn1, call this schema "heimdal".

 - Add to "heimdal" schema for representing group memberships and other
   entitlements.

 - Create a schema called "pgt" to hold VIEWs and functions for
   exporting via PostgREST for administration via a RESTful API.

 - Use PostgreSQL's logical replication functionality to replace iprop

 - Build a static, AJAXy BUI on top of the PostgREST/pgt REST API.

 - Create schemas to map between the "heimdal" schema and external
   schemas:

    - "hdb"

      Produce and consume a JSON representation of normalized "heimdal"
      data such that the JSON has roughly the same "shape" as the
      hdb_entry type from lib/hdb/hdb.asn1.

    - "kdb"

      Produce and consume a JSON representation of normalized "heimdal"
      data such that the JSON has roughly the same "shape" as the
      MIT Kerberos KDC KDB entry dump format.

    - "krb5\_admin"

      Produce and consume a JSON representation of normalized "heimdal"
      data such that the JSON has roughly the same "shape" as the
      krb5_admin SQLite3 schema.

    - "ldap"

      Produce and consume a JSON representation of normalized "heimdal"
      data such that the JSON has roughly the same "shape" as various
      LDAP schemas used for Kerberos principal representation.

 - Use VIEW materialization / history extensions to generate incremental
   updates for all the "hdb", "kdb", "krb5\_admin", "ldap", and any other
   schema-mapping schematas.

 - Create PG-\>external system sync tools that use incremental updates
   from PG to external systems via schema-mapping schematas:

    - HDB

      Use this so the Heimdal KDCs can continue to use the (inevitably
      faster) BerkeleyDB HDB backend.

      This will require writing some C code to LISTEN for incremental
      updates, SELECT them (all with libfe, from PG), parse the JSON,
      construct equivalent HDB entries and store them via libhdb.

      The code to map JSON->hdb_entry should be generated, naturally.

      Perhaps we could write that code generator in jq.

    - etc.

 - Keep kadmin working: create kadm5 or libhdb backend

   We don't want to add an explicit dependency on PG client libraries.
   Instead we could use a plugin system.  Or use IPC to read/write via
   an external agent which itself has no dependencies on Heimdal (except
   via PG client libraries depending on GSS from Heimdal).

 - Keep krb5\_admin working: change it to use PostgreSQL directly, using
   the "krb5\_admin" schema-mapping schema's VIEWs.


PG-Heimdal LTE: Long-term Evolution
===================================

 - Become AD-like, which means, really:

 - become UName\*It 3.0.

    - develop an extension for doing table inheritance correctly

      Among other things this will include alternative FK support so
      that one can properly reference rows from some table and its
      derivatives, even if we choose to use VIEWs to represent "virtual
      classes".  (This is the "attribute domain" part of UName\*It.)

    - develop an extension for UName\*It-style namespace tables

   The current heimdal.entities table conflates both of the above in an
   entirely manual way and a bit simplistically.  These two extensions
   will address that and more.

 - multi-master support

   A normalized schema makes conflict resolution much simpler.  We could
   have a directed graph of N masters doing replication of the "heimdal"
   schema at each master to "heimdal-\<master-name\>" at each peer, and
   use triggers to do merging and conflict resolution into the "heimdal"
   schema's tables.  An "origin" column can be used to prevent loops.

   For most items, conflict resolution is trivial: define a series of
   deterministic criteria for winner selection and tie breaks, and pick
   the winner.  For versioned long-term symmetric keys just accept all
   distinct keys and pick one to be the one to use for encrypting
   tickets at the KDC, and for decrypting try all the keys that match
   the `{kvno, enctype}` until one succeeds or all fail.

   In practice, too, conflicts will be very infrequent.

Status
======

At this time (2019-05-17) there is just this `README` and `hdb.sql`,
with a fairly-fully-fledged schema design and some partial attempt at an
"hdb" schema with VIEWs for mapping to HDB.

Much work remains to be done.  I'll be asking for @lucianwill's help on
this.
