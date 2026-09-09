/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 04_comorbidity_elixhause_updated
| Date (update): Mar 2026
| Task purpose :
|   1) Identify ICD-10-CM diagnosis codes in the 365 days before BS date.
|   2) Map diagnoses to Elixhauser categories using AHRQ $COMFMT.
|   3) Create patient-level Elixhauser flags and counts.
|
| Inputs:
|   - ywan2026.bs_glp1_patient_v02
|   - tx.diagnosis
|   - elixfmt.$COMFMT
|
| Outputs:
|   - ywan2026.bs_pt
|   - ywan2026.dx_bs_raw
|   - ywan2026.dx_bs_pre365
|   - ywan2026.dx_bs_pre365_icd10
|   - ywan2026.dx_bs_pre365_elix
|   - ywan2026.elix_flags_pre365_allpt
|   - ywan2026.elix_counts_wide
|   - qc04.dx_counts
|   - qc04.elix_flag_counts
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname tx       "/dcs07/trinetx/data/may2025datasets/sas";
libname elixfmt  "/users/ywang6/home/trinetx/elixhauser/fmtlib";
libname qc04     "/users/ywang6/home/trinetx/March2026_tx/qc/04_comorbidity_elixhauser";
options fmtsearch=(elixfmt);

/*=============================================================
  STEP 1. Cohort anchor
=============================================================*/
proc sql;
  create table ywan2026.bs_pt as
  select patient_id, bs_date format=yymmdd10.
  from ywan2026.bs_glp1_patient_v02;
quit;

/*=============================================================
  STEP 2. Pull diagnosis rows for cohort only, then parse once
=============================================================*/
proc sql;
  create table ywan2026.dx_bs_raw as
  select
    b.patient_id,
    b.bs_date format=yymmdd10.,
    d.encounter_id,
    d.code_system,
    d.code,
    d.principal_diagnosis_indicator,
    d.admitting_diagnosis,
    d.reason_for_visit,
    d.source_id,
    d.date as dx_date_raw
  from ywan2026.bs_pt as b
  inner join tx.diagnosis as d
    on b.patient_id = d.patient_id
  where not missing(d.date);
quit;

data ywan2026.dx_bs_all
     qc04.dx_bad_date(keep=patient_id bs_date encounter_id code_system code dx_date_raw dx_date);
  set ywan2026.dx_bs_raw;

  length dx_date_c $40;
  format dx_date yymmdd10.;

  dx_date_c = strip(vvalue(dx_date_raw));
  dx_date = input(dx_date_c, anydtdte32.);
  if missing(dx_date) then dx_date = input(compress(dx_date_c, '-/ '), yymmdd8.);

  if missing(dx_date) then output qc04.dx_bad_date;
  else output ywan2026.dx_bs_all;

  drop dx_date_c;
run;

/*=============================================================
  STEP 3. Restrict to pre-op 365d window and ICD-10-CM
=============================================================*/
data ywan2026.dx_bs_pre365;
  set ywan2026.dx_bs_all;
  if dx_date >= (bs_date - 365) and dx_date < bs_date;
run;

data ywan2026.dx_bs_pre365_icd10;
  set ywan2026.dx_bs_pre365;
  if strip(upcase(code_system)) ne "ICD-10-CM" then delete;
  if missing(code) then delete;
  dx_nodot = compress(upcase(code), '.');
  if missing(dx_nodot) then delete;
run;

/*=============================================================
  STEP 4. Elixhauser mapping
=============================================================*/
data ywan2026.dx_bs_pre365_elix;
  set ywan2026.dx_bs_pre365_icd10;
  length elix_grp $32;
  elix_grp = put(dx_nodot, $COMFMT.);
  if missing(elix_grp) then delete;
  if elix_grp = dx_nodot then delete;
run;

/*=============================================================
  STEP 5. Patient-level binary flags
    ELIX_  = any mapped diagnosis in pre-op 365d
    ELIX2_ = >=2 distinct diagnosis dates in pre-op 365d
=============================================================*/
data ywan2026.dx_bs_pre365_elix_nb;
  set ywan2026.dx_bs_pre365_elix(keep=patient_id elix_grp);
  flag = 1;
run;

proc sort data=ywan2026.dx_bs_pre365_elix_nb nodupkey;
  by patient_id elix_grp;
run;

proc transpose data=ywan2026.dx_bs_pre365_elix_nb
               out=ywan2026.elix_flags_pre365_wide(drop=_name_)
               prefix=ELIX_;
  by patient_id;
  id elix_grp;
  var flag;
run;

data ywan2026.elix_flags_pre365;
  set ywan2026.elix_flags_pre365_wide;
  array x _numeric_;
  do over x;
    if missing(x) then x = 0;
  end;
run;

proc sql;
  create table ywan2026.elix_days_long as
  select
    patient_id,
    elix_grp,
    count(distinct dx_date) as n_dx_days
  from ywan2026.dx_bs_pre365_elix
  group by patient_id, elix_grp;
quit;

data ywan2026.elix_days_ge2;
  set ywan2026.elix_days_long;
  if n_dx_days >= 2;
  flag2 = 1;
  keep patient_id elix_grp flag2;
run;

proc transpose data=ywan2026.elix_days_ge2
               out=ywan2026.elix_flags2_pre365_wide(drop=_name_)
               prefix=ELIX2_;
  by patient_id;
  id elix_grp;
  var flag2;
run;

data ywan2026.elix_flags2_pre365;
  set ywan2026.elix_flags2_pre365_wide;
  array x _numeric_;
  do over x;
    if missing(x) then x = 0;
  end;
run;

proc sort data=ywan2026.bs_pt;
  by patient_id;
run;

proc sort data=ywan2026.elix_flags_pre365;
  by patient_id;
run;

proc sort data=ywan2026.elix_flags2_pre365;
  by patient_id;
run;

data ywan2026.elix_flags_pre365_allpt;
  merge
    ywan2026.bs_pt(in=in_bs keep=patient_id)
    ywan2026.elix_flags_pre365
    ywan2026.elix_flags2_pre365;
  by patient_id;
  if in_bs;
run;

data ywan2026.elix_flags_pre365_allpt;
  set ywan2026.elix_flags_pre365_allpt;
  array x _numeric_;
  do over x;
    if missing(x) then x = 0;
  end;
run;

/*=============================================================
  STEP 6. Patient-level category counts
=============================================================*/
proc sql;
  create table ywan2026.elix_counts_long as
  select
    patient_id,
    elix_grp,
    count(*) as n_dx
  from ywan2026.dx_bs_pre365_elix
  group by patient_id, elix_grp;
quit;

proc transpose data=ywan2026.elix_counts_long
               out=ywan2026.elix_counts_wide(drop=_name_)
               prefix=ELIXN_;
  by patient_id;
  id elix_grp;
  var n_dx;
run;

data ywan2026.elix_counts_wide;
  set ywan2026.elix_counts_wide;
  array x _numeric_;
  do over x;
    if missing(x) then x = 0;
  end;
run;

/*=============================================================
  STEP 7. QC tables
=============================================================*/
proc sql;
  create table qc04.dx_counts as
  select
    (select count(*) from ywan2026.bs_pt) as n_bs_pt,
    (select count(*) from ywan2026.dx_bs_raw) as n_dx_raw,
    (select count(*) from ywan2026.dx_bs_all) as n_dx_parsed,
    (select count(*) from qc04.dx_bad_date) as n_dx_bad_date,
    (select count(*) from ywan2026.dx_bs_pre365) as n_dx_pre365,
    (select count(*) from ywan2026.dx_bs_pre365_icd10) as n_dx_pre365_icd10,
    (select count(*) from ywan2026.dx_bs_pre365_elix) as n_dx_pre365_elix,
    (select count(distinct patient_id) from ywan2026.dx_bs_pre365_elix) as n_pt_pre365_elix
  from sashelp.class(obs=1);
quit;

proc means data=ywan2026.elix_flags_pre365_allpt noprint;
  var ELIX_:;
  output out=qc04._elix_any_sum(drop=_type_ _freq_) sum=;
run;

proc transpose data=qc04._elix_any_sum
               out=qc04.elix_flag_counts_any(rename=(col1=n_patients));
run;

data qc04.elix_flag_counts_any;
  set qc04.elix_flag_counts_any;
  length elix_grp $50;
  if substr(_name_, 1, 6) = "ELIX2_" then delete;
  elix_grp = substr(_name_, 6);
  keep elix_grp n_patients;
run;

proc means data=ywan2026.elix_flags_pre365_allpt noprint;
  var ELIX2_:;
  output out=qc04._elix_ge2_sum(drop=_type_ _freq_) sum=;
run;

proc transpose data=qc04._elix_ge2_sum
               out=qc04.elix_flag_counts_ge2days(rename=(col1=n_patients));
run;

data qc04.elix_flag_counts_ge2days;
  set qc04.elix_flag_counts_ge2days;
  length elix_grp $50;
  elix_grp = substr(_name_, 7);
  keep elix_grp n_patients;
run;
