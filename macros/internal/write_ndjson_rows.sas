/**
  @file write_ndjson_rows.sas
  @brief Write the observations of a SAS dataset as NDJSON row arrays.

  @details
  Dataset-NDJSON stores the dataset metadata on the first line, followed by
  one JSON array per observation. This macro writes only the row arrays, one
  per line, and appends them to an existing NDJSON file.

  Arrays are used (not objects), as required by the Dataset-JSON NDJSON
  representation. Missing numeric values are written as null and missing
  character values as empty strings.

  Numeric variables with a date, time, or datetime format are written as
  formatted strings (for example E8601DA.), matching the representation
  used by PROC JSON for the non-compressed Dataset-JSON output.

  @param[in] rowdata= SAS dataset containing the observations
  @param[in] outRef= File reference of the NDJSON file to append to

  @author Lex Jansen

**/

%macro write_ndjson_rows(
  rowdata=,
  outRef=
  ) / des = 'Write SAS dataset observations as NDJSON row arrays';

  %local _dsid _nvars _i _col _fmt _fmtbase _fmtcat;

  %let _dsid = %sysfunc(open(&rowdata));
  %if &_dsid = 0 %then %do;
    %put ERR%str(OR): [&sysmacroname] Cannot open dataset &=rowdata..;
    %return;
  %end;

  %let _nvars = %sysfunc(attrn(&_dsid, NVARS));

  data _null_;
    set &rowdata;
    length _ndjson_line $32767 _ndjson_str $32767 _ndjson_esc $32767 _ndjson_val $32767 _ndjson_ch $1 _ndjson_len 8;
    file &outRef mod;

    _ndjson_line = '[';

    %do _i = 1 %to &_nvars;
      %let _col = %sysfunc(varname(&_dsid, &_i));

      %if "%sysfunc(strip(%sysfunc(vartype(&_dsid, &_i))))" = "C" %then %do;
        _ndjson_str = trim(&_col);
        /* Fast path: escape backslash and quote when no control characters */
        if findc(_ndjson_str, '000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F'x) > 0 then do;
          _ndjson_esc = '';
          do _ndjson_j = 1 to length(_ndjson_str);
            _ndjson_ch = substr(_ndjson_str, _ndjson_j, 1);
            if _ndjson_ch = '"' then _ndjson_esc = cats(_ndjson_esc, '\"');
            else if _ndjson_ch = '\' then _ndjson_esc = cats(_ndjson_esc, '\\');
            else if rank(_ndjson_ch) lt 32 then _ndjson_esc = cats(_ndjson_esc, '\u', put(rank(_ndjson_ch), hex4.));
            else _ndjson_esc = cats(_ndjson_esc, _ndjson_ch);
          end;
        end;
        else do;
          _ndjson_esc = tranwrd(tranwrd(_ndjson_str, '\', '\\'), '"', '\"');
        end;
        _ndjson_val = cats('"', _ndjson_esc, '"');
      %end;
      %else %do;
        %let _fmt = %sysfunc(varfmt(&_dsid, &_i));
        %let _fmtbase=;
        %let _fmtcat=;
        %if %length(&_fmt) > 0 %then %do;
          %let _fmtbase = %sysfunc(strip(%sysfunc(prxchange(s/[\d.]*$//, 1, &_fmt))));
          %if %length(&_fmtbase) > 0 %then
            %let _fmtcat = %sysfunc(strip(%sysfunc(fmtinfo(&_fmtbase, cat))));
        %end;
        %if "%upcase(&_fmtcat)" = "DATE" or
            "%upcase(&_fmtcat)" = "DATETIME" or
            "%upcase(&_fmtcat)" = "TIME" or
            "%upcase(&_fmtcat)" = "ISO 8601" or
            "%upcase(&_fmtcat)" = "ISO8601" or
            %index(%upcase(&_fmtbase), E8601) = 1 or
            %index(%upcase(&_fmtbase), B8601) = 1 %then %do;
          if missing(&_col) then _ndjson_val = 'null';
          else _ndjson_val = cats('"', strip(put(&_col, &_fmt)), '"');
        %end;
        %else %do;
          if missing(&_col) then _ndjson_val = 'null';
          else _ndjson_val = strip(put(&_col, best32.));
        %end;
      %end;

      if length(_ndjson_line) + length(_ndjson_val) + 2 > 32767 then
        putlog "WAR" "NING: [&sysmacroname] NDJSON row exceeds the maximum SAS character length and will be truncated.";

      if _ndjson_line = '[' then _ndjson_line = cats(_ndjson_line, _ndjson_val);
      else _ndjson_line = cats(_ndjson_line, ',', _ndjson_val);
    %end;

    _ndjson_line = cats(_ndjson_line, ']');
    _ndjson_len = length(_ndjson_line);
    put _ndjson_line $varying32767. _ndjson_len;
  run;

  %let _dsid = %sysfunc(close(&_dsid));

%mend write_ndjson_rows;
