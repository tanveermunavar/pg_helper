CREATE OR REPLACE FUNCTION f_suggest_primary_keys( schemaz text DEFAULT 'public',
                                                   tablez text  DEFAULT NULL )
RETURNS SETOF text
AS $CODE$
DECLARE
  current_stats record;
  is_unique            boolean;
  is_primary_key       boolean;
  could_be_unique      boolean;
  could_be_primary_key boolean;
  current_constraint   char(1);
  current_alter_table  text;
BEGIN
  RAISE DEBUG 'Inspecting schema % (table %)', schemaz, tablez;

  FOR current_stats IN SELECT s.*, n.oid AS nspoid, c.oid AS reloid FROM pg_stats s
                       JOIN  pg_class c ON c.relname = s.tablename
                       JOIN  pg_namespace n ON n.oid = c.relnamespace
                       WHERE s.schemaname = schemaz
                       AND   c.relkind = 'r'
                       AND   n.nspname = s.schemaname
                       AND   ( ( s.tablename = tablez ))

  LOOP
    is_primary_key       := false;
    is_unique            := false;
    could_be_unique      := false;
    could_be_primary_key := false;
    RAISE DEBUG 'Inspecting table [%.%] (%.%) -> %', current_stats.schemaname,
                                                     current_stats.tablename,
                                                     current_stats.nspoid,
                                                     current_stats.reloid,
                                                     current_stats.attname;
     -- search if this attribute is already included into
     -- a primary key constraint
     SELECT cn.contype
     INTO   current_constraint
     FROM   pg_constraint cn
     JOIN   pg_attribute a ON a.attnum = ANY( cn.conkey )
     WHERE  cn.conrelid     = current_stats.reloid
     AND    cn.connamespace = current_stats.nspoid
     AND    a.attrelid      = current_stats.reloid
     AND    a.attname       = current_stats.attname;


     IF current_constraint = 'p' THEN
        is_primary_key := true;
     ELSE
       is_primary_key := false;
     END IF;

     IF current_constraint = 'u' THEN
        is_unique := true;
     ELSE
       is_unique := false;
     END IF;

     -- if this is already on a constraint, skip!
     IF is_primary_key OR is_unique THEN
        CONTINUE;
     END IF;

   -- check if this could be an unique attribute
   IF current_stats.n_distinct = -1 THEN
      could_be_unique := true;
   ELSE
      could_be_unique := false;
   END IF;

   -- could it be promoted as a primary key?
   IF could_be_unique AND current_stats.null_frac = 0 THEN
      could_be_primary_key := true;
   ELSE
     could_be_primary_key := false;
   END IF;

   IF could_be_primary_key THEN
      RAISE DEBUG 'Suggested PRIMARY KEY(%) on %.%', current_stats.attname,
                                                     current_stats.schemaname,
                                                     current_stats.tablename;
      current_alter_table := format( 'ALTER TABLE %I.%I ADD CONSTRAINT UNIQUE(%I)', current_stats.schemaname,
                                                                                    current_stats.tablename,
                                                                                    current_stats.attname );
   ELSE IF could_be_unique THEN
         RAISE DEBUG 'Suggested UNIQUE(%) on %.%', current_stats.attname,
                                                   current_stats.schemaname,
                                                   current_stats.tablename;
        current_alter_table := format( 'ALTER TABLE %I.%I ADD CONSTRAINT PRIMARY KEY(%I)',
                                                   current_stats.schemaname,
                                                   current_stats.tablename,
                                                   current_stats.attname );
    END IF;
  END IF;




   RETURN NEXT current_alter_table;
  END LOOP;

  RETURN;

END
$CODE$
LANGUAGE plpgsql;







--
--
--


testdb =# select * from f_suggest_primary_keys( 'respi', 'tipo_rensom' );
 DEBUG:  Inspecting schema respi (table tipo_rensom)
 DEBUG:  Inspecting table [respi.tipo_rensom] (151915.151952) -> pk
 DEBUG:  Inspecting table [respi.tipo_rensom] (151915.151952) -> id_tipo_rensom
 DEBUG:  Inspecting table [respi.tipo_rensom] (151915.151952) -> nome
 DEBUG:  Suggested PRIMARY KEY(nome) on respi.tipo_rensom
 DEBUG:  Inspecting table [respi.tipo_rensom] (151915.151952) -> descrizione
 DEBUG:  Suggested PRIMARY KEY(descrizione) on respi.tipo_rensom

                   f_suggest_primary_keys
 -------------------------------------------------------------------
 ALTER TABLE respi.tipo_rensom ADD CONSTRAINT UNIQUE(nome)
 ALTER TABLE respi.tipo_rensom ADD CONSTRAINT UNIQUE(descrizione)
