#include <stdio.h>
#include <jv.h>
/* XXX Include headers from Heimdal here */


/*
 * We're going to have a function to convert from a string containing JSON
 * output from pghdb to an hdb_entry, and another to do the reverse.
 *
 * We'll have a main() function to demo this.
 */

hdb_entry *
pghdb_json2hdbr(const char *json)
{
    hdb_entry *e;
    jv je = jv_parse(json);
    jv v;

    if ((e = calloc(1, sizeof(*e))) == NULL)
        err(1, "out of memory");

    /* First, extract the name of the entity and make a Principal for it */

    /* Then kvno */
    v = jv_object_get(jv_copy(je), "kvno");
}


char *
hdb2pghdb_json(const hdb_entry *e)
{
    jv v = jv_object();
}

static void
usage(int e)
{
    FILE *f = e ? stderr : stdout;

    fprintf(f, "Usage: pghdb2json json2hdb JSON_TEXT\n"
               "       pghdb2json hdb2json BASE64-ENCODED-DER-ENCODED\n");
    exit(e);
}

int
main(int argc, const char **argv)
{
    if (argc != 3)
        usage(1);
    
    if (strcmp(argv[1], "json2hdb") == 0) {
        hdb_entry *e = pghdb_json2hdbr(argv[2]);

        if (e == NULL)
            errx(1, "could not convert");

        /*
         * XXX here encode `e' into DER and then base64-encode that, then
         * print it on stdout.
         */
    } else if (strcmp(argv[1], "hdb2json") == 0) {
        /*
         * Base64-decode argv[2], then decode the hdb_entry, then call
         * hdb2pghdb_json() with that entry.
         */
    } else
        usage(1);
}
