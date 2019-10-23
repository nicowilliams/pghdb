

CREATE OR REPLACE FUNCTION
    util.denorm(src_schema TEXT, src_table TEXT, src_id_col TEXT,
                dst_schema TEXT, dst_table TEXT, dst_id_col TEXT,
                dst_col_prefix TEXT, src_cols TEXT[])
AS $$
BEGIN
    /*
     * Idea:
     *
     *  for each col in src_cols[]
     *  EXECUTE format('ALTER TABLE {dst_schema}.{dst_tbl}
     *                      ADD COLUMN {dst_col_prefix}{col} TEXT', ...);
     *
     *  EXECUTE format('CREATE TRIGGER ... AFTER UPDATE OR DELETE
     *                  ON {src_schema}.{src_tbl}...
                        -- update/delete dst_schema.dst_tbl to copy over the
                        -- denormalized columns');

     *  EXECUTE format('CREATE TRIGGER ... BEFORE INSERT
     *                  ON {dst_schema}.{dst_tbl}...
                        -- set NEW.{dst_col_prefix}{col} for every dst_cols[]
                        -- by looking that up in the source table');
     */
END; $$ LANGUAGE PlPGSQL;
