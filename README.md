CSV, Ascii table, XLSX to JSON converter written in perl.

Features
--------

 * Autodetect of CSV, Ascii table, XLSX formats
 * Join data from other file (joining is done by matching values in first columns of each file)
 * Auto group data
   * Creates table that uses unique values from second column as column names of result table
   * Usefull if you need to convert data from mysql "group by" query into plain table
 * Can specify separator for CSV
 * Write joined data to original file and format

TODO
----

 * Fix BOM while reading file
 * More input formats: JSON, XML
 * More output formats: Jira, XML
 * Fix various problems when data includes separators in "table" format
 * More user friendly error/warning reporting
