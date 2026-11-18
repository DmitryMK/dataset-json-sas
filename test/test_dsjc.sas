%* update this location to your own location;
%let project_folder=/_github/lexjansen/dataset-json-sas;
%include "&project_folder/programs/config.sas";

%*
  Test Dataset-JSON Compressed (DSJC).

  DSJC is the Dataset-NDJSON representation of Dataset-JSON, compressed
  as gzip. This test writes a small dataset to a .dsjc file and reads it
  back. The .dsjc extension is detected automatically.
*;

data work.class_orig;
  length note $100;
  set sashelp.class;
  bmi = weight * 703 / (height * height);
  birthdate = today() - ((age + 1) * 365);
  note = 'He said "Hi" \ and then left';
  format birthdate E8601DA.;
  label bmi = "Body Mass Index"
        birthdate = "Date of birth"
        note = "Free text";
run;

data work.class_base;
  set work.class_orig;
run;

%put NOTE: Writing Dataset-JSON Compressed file;
%write_datasetjson(
  dataset=work.class_orig,
  jsonpath=&project_folder/test/class.dsjc,
  usemetadata=N
);

%put NOTE: Reading Dataset-JSON Compressed file;
%read_datasetjson(
  jsonpath=&project_folder/test/class.dsjc,
  datalib=work,
  savemetadata=N
);

proc compare base=work.class_base compare=work.class_orig;
run;

/*
filename dsjc clear;
*/
