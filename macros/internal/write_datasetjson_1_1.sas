%macro write_datasetjson_1_1(
  outRef=,
  technicalMetadata=,
  tableMetadata=work.table_metadata,
  columnMetadata=work.column_metadata,
  rowdata=,
  prettyNoPretty=NOPRETTY,
  compressed=N
  );

  %local
    fileOID
    creationDateTime
    asOfDateTime
    modifiedDateTime
    datasetJSONVersion
    originator
    sourceSystem
    sourceSystemVersion
    studyOID
    metaDataVersionOID
    metaDataRef
    itemGroupOID
    records
    datasetName
    datasetLabel
    _Random
    _jsonOutRef
    _temp_ndjson
    _temp_metadata
    _target_path
    ;

  %let _Random=%sysfunc(putn(%sysevalf(%sysfunc(ranuni(0))*10000,floor),z4.));

  %if "%upcase(&compressed)" eq "Y" %then %let prettyNoPretty = NOPRETTY;

  data _null_;
    set &technicalMetadata;
    call symputx('fileOID', fileOID);
    call symputx('creationDateTime', creationDateTime);
    call symputx('modifiedDateTime', modifiedDateTime);
    call symputx('datasetJSONVersion', datasetJSONVersion);
    call symputx('originator', originator);
    call symputx('sourceSystem', sourceSystem);
    call symputx('sourceSystemVersion', sourceSystemVersion);
    call symputx('studyOID', studyOID);
    call symputx('metaDataVersionOID', metaDataVersionOID);
    call symputx('metaDataRef', metaDataRef);
  run;

  data _null_;
    set &tableMetadata;
    call symputx('itemGroupOID', oid);
    call symputx('records', records);
    call symputx('datasetName', name);
    call symputx('datasetLabel', label);
  run;

  %if "%upcase(&compressed)" eq "Y" %then %do;
    %let _temp_ndjson = %sysfunc(pathname(work))/ndjson_&_Random..ndjson;
    %let _temp_metadata = %sysfunc(pathname(work))/ndjson_&_Random..json;
    filename ndj&_Random "&_temp_ndjson" encoding='utf-8' lrecl=32767;
    filename mta&_Random "&_temp_metadata" encoding='utf-8' lrecl=32767;
    %let _jsonOutRef = mta&_Random;
  %end;
  %else %do;
    %let _jsonOutRef = &outRef;
  %end;

  PROC JSON OUT=&_jsonOutRef &prettyNoPretty NOSASTAGS SCAN TRIMBLANKS
                         NOFMTCHARACTER NOFMTDATETIME NOFMTNUMERIC;
    WRITE OPEN OBJECT;

    WRITE VALUES "datasetJSONCreationDateTime" "&creationDateTime";
    WRITE VALUES "datasetJSONVersion" "&datasetJSONVersion";
    %if %sysevalf(%superq(fileOID)=, boolean)=0 %then
      WRITE VALUES "fileOID" "&fileOID";
    ;
    %if %sysevalf(%superq(modifiedDateTime)=, boolean)=0 %then
      WRITE VALUES "dbLastModifiedDateTime" "&modifiedDateTime";
    ;
    %if %sysevalf(%superq(originator)=, boolean)=0 %then
      WRITE VALUES "originator" "&originator";
    ;
    %if %sysevalf(%superq(sourceSystem)=, boolean)=0 or %sysevalf(%superq(sourceSystemVersion)=, boolean)=0 %then %do;
      WRITE VALUES "sourceSystem";
      WRITE OPEN OBJECT;
      
      %if %sysevalf(%superq(sourceSystem)=, boolean)=0 %then
        WRITE VALUES "name" "&sourceSystem";
      ;
      %if %sysevalf(%superq(sourceSystemVersion)=, boolean)=0 %then
        WRITE VALUES "version" "&sourceSystemVersion";
      ;
      WRITE CLOSE;
    %end;
    %if %sysevalf(%superq(_studyOID)=, boolean)=0 %then
      WRITE VALUES "studyOID" "&studyOID";
    ;
    %if %sysevalf(%superq(_metaDataVersionOID)=, boolean)=0 %then
      WRITE VALUES "metaDataVersionOID" "&metaDataVersionOID";
    ;
    %if %sysevalf(%superq(metaDataRef)=, boolean)=0 %then
      WRITE VALUES "metaDataRef" "&metaDataRef";
    ;
    %if %sysevalf(%superq(itemGroupOID)=, boolean)=0 %then
      WRITE VALUES "itemGroupOID" "&itemGroupOID";
    ;  
    WRITE VALUES "records" &records;
    WRITE VALUES "name" "&datasetName";
    %if %sysevalf(%superq(datasetLabel)=, boolean)=0 %then
      WRITE VALUES "label" "%nrbquote(&datasetLabel)";
    ;
    WRITE VALUES "columns";
    %* Use macro to avoid creating null values for missing attributes;
    %* Instead do not create the attribute;
    %write_json_metadata_array(&columnMetadata);

    %if "%upcase(&compressed)" ne "Y" %then %do;
      WRITE VALUES "rows";
      WRITE OPEN ARRAY;
      EXPORT &rowData / NOKEYS FMTDATETIME;
      WRITE CLOSE;
    %end;
    WRITE CLOSE;
  RUN;

  %if "%upcase(&compressed)" eq "Y" %then %do;
    /* NDJSON: copy the metadata object (without rows) as the first line */
    data _null_;
      infile mta&_Random lrecl=32767 end=_eof;
      file ndj&_Random;
      input;
      if not missing(_infile_) then put _infile_;
    run;

    /* Append one JSON array per observation */
    %write_ndjson_rows(rowdata=&rowData, outRef=ndj&_Random)

    /* Compress the NDJSON stream as gzip into the requested output file */
    %let _target_path = %sysfunc(pathname(&outRef));
    %if %sysfunc(fileexist("&_target_path")) %then %do;
      data _null_;
        _rc = fdelete("&outRef");
        if _rc ne 0 then putlog "WAR" "NING: [&sysmacroname] Could not replace existing file &_target_path.";
      run;
    %end;

    filename zip&_Random ZIP "&_target_path" GZIP lrecl=32767;
    data _null_;
      _rc = fcopy("ndj&_Random", "zip&_Random");
      if _rc ne 0 then do;
        putlog "ERR" "OR: [&sysmacroname] Could not compress NDJSON to &_target_path.";
        putlog "ERR" "OR: [&sysmacroname] " _rc=;
        _rc2 = fdelete("&outRef");
      end;
    run;

    filename zip&_Random clear;
    filename ndj&_Random clear;
    filename mta&_Random clear;

    %if %sysfunc(fileexist("&_temp_ndjson")) %then %do;
      filename del&_Random "&_temp_ndjson";
      %put %sysfunc(fdelete(del&_Random));
      filename del&_Random clear;
    %end;
    %if %sysfunc(fileexist("&_temp_metadata")) %then %do;
      filename del&_Random "&_temp_metadata";
      %put %sysfunc(fdelete(del&_Random));
      filename del&_Random clear;
    %end;
  %end;

%mend write_datasetjson_1_1;
