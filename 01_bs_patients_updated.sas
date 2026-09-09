/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 01_bs_patients_updated
| Date (update): Mar 2026
| Task Purpose :
|   Build final BS cohort with faster I/O and cleaner debug/QC.
|
| Inputs:
|   - tx.procedure
|   - tx.patient
|
| Key outputs:
|   - ywan2026.bs_user_all_v01      (all BS records on first BS date)
|   - ywan2026.bs_type_combo        (one row/patient with first-day BS type combo)
|   - ywan2026.bs_user_demo_v05     (final eligible cohort)
|   - qc01.bs_exclusion_deletes     (sequential deletion counts only)
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname tx       "/dcs07/trinetx/data/may2025datasets/sas";
libname qc01     "/users/ywang6/home/trinetx/March2026_tx/qc/01_bs_patients";

/* Region labels can differ by data release. Adjust this macro once if needed. */
%let US_REGION_KEEP = "Midwest","Northeast","South","West";

/*=============================================================
  STEP 1. Extract BS procedures using original working logic
=============================================================*/
data ywan2026.bs_all_v00;
  set tx.procedure(keep=patient_id date code);
  length bs_type $8;

  if code in ("43644","43645","43846","43847","43633",
              "43.7","44.39","44.38",
              "0D16479","0D1647A","0D164J9","0D164JA",
              "0D164K9","0D164KA","0D164Z9","0D164ZA","0D164ZB",
              "0D160ZB","0D16078","0DB60ZZ") then bs_type="rygb";
  else if code in ("43842","43843","43775","44.68","44.69",
                   "43.82","43.89","0DQ60ZZ","0DB64ZZ","0DB64Z3") then bs_type="sg";
  else if code in ("43770","S2082","44.95","0DV64CZ") then bs_type="agb";
  else if code in ("43659") then bs_type="sadi_s";
  else if code in ("43845","45.91","45.51","43.89","0D190Z9","0DB60ZZ","0DB80ZZ") then bs_type="bpd";
  else if code in ("43842","44.68","0DV64CZ") then bs_type="vbg";
  else delete;
run;

data ywan2026.bs_all_v00_dt
     qc01.bs_all_bad_date(keep=patient_id code date date_dt);
  set ywan2026.bs_all_v00;
  format date_dt yymmdd10.;

  date_dt = input(strip(vvalue(date)), anydtdte32.);
  if missing(date_dt) then date_dt = input(compress(strip(vvalue(date)), '-/ '), yymmdd8.);

  if missing(date_dt) then output qc01.bs_all_bad_date;
  else output ywan2026.bs_all_v00_dt;
run;

proc sort data=ywan2026.bs_all_v00_dt nodupkey;
  by patient_id date_dt bs_type;
run;

/*=============================================================
  STEP 2. First BS date and first-day records
=============================================================*/
proc sql;
  create table ywan2026.bs_first_date as
  select patient_id,
         min(date_dt) as first_bs_date format=yymmdd10.
  from ywan2026.bs_all_v00_dt
  group by patient_id;
quit;

proc sql;
  create table ywan2026.bs_user_all_v01 as
  select a.patient_id,
         a.date_dt,
         a.bs_type
  from ywan2026.bs_all_v00_dt as a
  inner join ywan2026.bs_first_date as b
    on a.patient_id=b.patient_id
   and a.date_dt=b.first_bs_date;
quit;

/*=============================================================
  STEP 3. Combine same-day BS types to one combo per patient
=============================================================*/
proc sort data=ywan2026.bs_user_all_v01 nodupkey out=ywan2026.bs_user_all_v01_ud;
  by patient_id date_dt bs_type;
run;

data ywan2026.bs_type_combo;
  length bs_type_combo $200;
  set ywan2026.bs_user_all_v01_ud;
  by patient_id date_dt;
  retain bs_type_combo;

  if first.date_dt then bs_type_combo=bs_type;
  else bs_type_combo=catx('+', bs_type_combo, bs_type);

  if last.date_dt then output;
  keep patient_id date_dt bs_type_combo;
run;

/*=============================================================
  STEP 4. Merge demographics + all exclusions in one data step
=============================================================*/
proc sql;
  create table ywan2026.bs_user_demo_raw as
  select
    a.patient_id,
    a.date_dt,
    a.bs_type_combo,
    b.sex,
    b.race,
    b.ethnicity,
    b.marital_status,
    b.year_of_birth,
    b.month_year_death,
    b.death_date_source_id,
    b.patient_regional_location,
    b.source_id
  from ywan2026.bs_type_combo as a
  left join tx.patient as b
    on a.patient_id=b.patient_id;
quit;

/* QC before exclusions: inspect actual region labels in this release */
proc freq data=ywan2026.bs_user_demo_raw noprint;
  tables patient_regional_location / missing out=qc01.region_before_exclusion_freq;
run;

data ywan2026.bs_user_demo_with_flags
     ywan2026.bs_user_demo_v05;
  set ywan2026.bs_user_demo_raw;

  length exclusion_reason $40;
  length death_year death_month 8;
  length death_same_or_next_month 8 death_within_3m 8;
  format bs_month death_month_date yymmn6.;
  format death_date yymmdd10.;

  /* robust YOB parse */
  if vtype(year_of_birth)='C' then year_of_birth_num=input(strip(year_of_birth), 4.);
  else year_of_birth_num=year_of_birth;

  age_at_bs = year(date_dt) - year_of_birth_num;
  if missing(year_of_birth_num) then age_at_bs=.;

  death_date=.;
  if not missing(month_year_death) and lengthn(strip(month_year_death))>=6 then do;
    death_year  = input(substr(strip(month_year_death), 1, 4), 4.);
    death_month = input(substr(strip(month_year_death), 5, 2), 2.);
    if 1 <= death_month <= 12 then do;
      death_date = mdy(death_month, 15, death_year);
      death_month_date = mdy(death_month, 1, death_year);
    end;
  end;

  bs_month = intnx('month', date_dt, 0, 'b');
  bs_m1    = intnx('month', bs_month, 1, 'b');
  bs_m2    = intnx('month', bs_month, 2, 'b');
  death_same_or_next_month = 0;
  death_within_3m = 0;
  if not missing(death_month_date) then do;
    if death_month_date = bs_month or death_month_date = bs_m1 then death_same_or_next_month = 1;
    if death_month_date >= bs_month and death_month_date <= bs_m2 then death_within_3m = 1;
  end;

  exclusion_reason='';
  if date_dt < '01JAN2016'd then exclusion_reason='pre_2016_index';
  else if age_at_bs < 18 or missing(age_at_bs) then exclusion_reason='age_lt18_or_missing';
  else if missing(sex) then exclusion_reason='missing_sex';
  else if patient_regional_location not in (&US_REGION_KEEP) then exclusion_reason='non_us_or_missing_region';

  year_of_birth = year_of_birth_num;
  drop year_of_birth_num bs_m1 bs_m2;

  output ywan2026.bs_user_demo_with_flags;
  if missing(exclusion_reason) then output ywan2026.bs_user_demo_v05;
run;

/*=============================================================
  STEP 5. QC: sequential deletion counts only
=============================================================*/
proc sql;
  create table qc01.bs_exclusion_deletes as
  select "input_total" as step length=40, count(*) as n
  from ywan2026.bs_user_demo_with_flags

  union all
  select "deleted_pre_2016_index" as step, count(*) as n
  from ywan2026.bs_user_demo_with_flags
  where exclusion_reason = "pre_2016_index"

  union all
  select "deleted_age_lt18_or_missing" as step, count(*) as n
  from ywan2026.bs_user_demo_with_flags
  where exclusion_reason = "age_lt18_or_missing"

  union all
  select "deleted_missing_sex" as step, count(*) as n
  from ywan2026.bs_user_demo_with_flags
  where exclusion_reason = "missing_sex"

  union all
  select "deleted_non_us_or_missing_region" as step, count(*) as n
  from ywan2026.bs_user_demo_with_flags
  where exclusion_reason = "non_us_or_missing_region"

  union all
  select "final_included" as step, count(*) as n
  from ywan2026.bs_user_demo_with_flags
  where missing(exclusion_reason)
  ;
quit;
