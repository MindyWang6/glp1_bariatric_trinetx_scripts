/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 08_BMI_updated
| Date (update): Mar 2026
| Task Purpose :
|   1) Keep baseline BMI calculation the same as the Jan 2026 script.
|   2) Create a long table with all BMI records in the pre-op 365d window.
|   3) Create a practical patient-level 1-year post-op BMI change dataset.
|
| Inputs:
|   - ywan2026.bs_pt
|   - tx.vitals_signs
|
| Outputs:
|   - ywan2026.bmi_pre365_long
|   - ywan2026.bs_bmi_baseline365
|   - ywan2026.bs_bmi_change_pre1y
|   - ywan2026.bmi_post1y_long
|   - ywan2026.bs_bmi_change_1y
|   - qc08.bmi_counts
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname tx       "/dcs07/trinetx/data/may2025datasets/sas";
libname qc08     "/users/ywang6/home/trinetx/March2026_tx/qc/08_bmi";

/* 1-year post-op target window for BMI change */
%let BMI_1Y_LOWER = 275;
%let BMI_1Y_UPPER = 455;
%let BMI_TARGET_DAY = 365;

/*=============================================================
  STEP 1. Pull BMI rows for BS cohort only
=============================================================*/
proc sql;
  create table ywan2026.bmi_raw as
  select
    b.patient_id,
    b.bs_date format=yymmdd10.,
    v.date  as bmi_date_raw,
    v.value as bmi_value_raw
  from ywan2026.bs_pt as b
  inner join tx.vitals_signs as v
    on b.patient_id = v.patient_id
  where v.code = "39156-5"
    and not missing(v.date)
    and not missing(v.value);
quit;

/*=============================================================
  STEP 2. Parse date/value once and clean
=============================================================*/
data ywan2026.bmi_all
     qc08.bmi_bad_parse(keep=patient_id bs_date bmi_date_raw bmi_value_raw bmi_date bmi);
  set ywan2026.bmi_raw;

  length bmi_date_c bmi_value_c $40;
  format bmi_date yymmdd10. bmi 8.2;

  bmi_date_c = strip(vvalue(bmi_date_raw));
  bmi_date = inputn(bmi_date_c, 'anydtdte32.');
  if missing(bmi_date) then bmi_date = inputn(compress(bmi_date_c, '-/ '), 'yymmdd8.');

  bmi_value_c = strip(vvalue(bmi_value_raw));
  bmi = inputn(bmi_value_c, 'best32.');

  if missing(bmi_date) or missing(bmi) then output qc08.bmi_bad_parse;
  else if bmi < 10 or bmi > 150 then output qc08.bmi_bad_parse;
  else output ywan2026.bmi_all;

  drop bmi_date_c bmi_value_c;
run;

/*=============================================================
  STEP 3. Pre-op long table: all BMI records in [-365, 0]
=============================================================*/
data ywan2026.bmi_pre365_long;
  set ywan2026.bmi_all;
  if bmi_date <= bs_date and bmi_date >= (bs_date - 365);
  keep patient_id bs_date bmi_date bmi;
run;

/*=============================================================
  STEP 4. Same baseline logic as original script
=============================================================*/
proc sql;
  create table ywan2026.bmi_day as
  select
    patient_id,
    bs_date,
    bmi_date,
    mean(bmi) as bmi format=8.2
  from ywan2026.bmi_pre365_long
  group by patient_id, bs_date, bmi_date;
quit;

proc sql;
  create table ywan2026.bmi_baseline_date365 as
  select
    patient_id,
    bs_date,
    max(bmi_date) as baseline_bmi_date format=yymmdd10.
  from ywan2026.bmi_day
  group by patient_id, bs_date;
quit;

proc sql;
  create table ywan2026.bs_bmi_baseline365 as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    d.baseline_bmi_date,
    p.bmi as bmi_index format=8.2
  from ywan2026.bs_pt as a
  left join ywan2026.bmi_baseline_date365 as d
    on a.patient_id = d.patient_id
   and a.bs_date    = d.bs_date
  left join ywan2026.bmi_day as p
    on d.patient_id = p.patient_id
   and d.bs_date    = p.bs_date
   and d.baseline_bmi_date = p.bmi_date;
quit;

/*=============================================================
  STEP 4B. Pre-op 1-year BMI change
    Compare earliest BMI in [-365, 0] to baseline BMI closest to BS
=============================================================*/
proc sql;
  create table ywan2026.bmi_pre1y_first_date as
  select
    patient_id,
    bs_date,
    min(bmi_date) as first_bmi_date format=yymmdd10.
  from ywan2026.bmi_day
  group by patient_id, bs_date;
quit;

proc sql;
  create table ywan2026.bs_bmi_change_pre1y as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    f.first_bmi_date,
    p.bmi as bmi_pre1y_first format=8.2,
    a.baseline_bmi_date,
    a.bmi_index format=8.2,
    a.bmi_index - p.bmi as bmi_change_pre1y format=8.2,
    case
      when not missing(p.bmi) and p.bmi > 0 and not missing(a.bmi_index)
      then ((a.bmi_index - p.bmi) / p.bmi)
      else .
    end as bmi_pct_change_pre1y format=percent8.2
  from ywan2026.bs_bmi_baseline365 as a
  left join ywan2026.bmi_pre1y_first_date as f
    on a.patient_id = f.patient_id
   and a.bs_date = f.bs_date
  left join ywan2026.bmi_day as p
    on f.patient_id = p.patient_id
   and f.bs_date = p.bs_date
   and f.first_bmi_date = p.bmi_date;
quit;

/*=============================================================
  STEP 5. Long table for post-op BMI around 1 year
    Approach:
      - keep all BMI records in a window around 1 year after BS
      - patient-level 1y BMI = record closest to day 365
=============================================================*/
data ywan2026.bmi_post1y_long;
  set ywan2026.bmi_all;
  days_from_bs = bmi_date - bs_date;
  if &BMI_1Y_LOWER <= days_from_bs <= &BMI_1Y_UPPER;
  abs_dist_1y = abs(days_from_bs - &BMI_TARGET_DAY);
  keep patient_id bs_date bmi_date bmi days_from_bs abs_dist_1y;
run;

proc sql;
  create table ywan2026.bmi_post1y_day as
  select
    patient_id,
    bs_date,
    bmi_date,
    mean(bmi) as bmi format=8.2,
    mean(days_from_bs) as days_from_bs,
    mean(abs_dist_1y) as abs_dist_1y
  from ywan2026.bmi_post1y_long
  group by patient_id, bs_date, bmi_date;
quit;

proc sort data=ywan2026.bmi_post1y_day out=ywan2026.bmi_post1y_day_s;
  by patient_id abs_dist_1y bmi_date;
run;

data ywan2026.bmi_post1y_pick;
  set ywan2026.bmi_post1y_day_s;
  by patient_id;
  if first.patient_id;
run;

proc sql;
  create table ywan2026.bs_bmi_change_1y as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    a.baseline_bmi_date,
    a.bmi_index format=8.2,
    p.bmi_date as bmi_1y_date format=yymmdd10.,
    p.days_from_bs as bmi_1y_days_from_bs,
    p.bmi as bmi_1y format=8.2,
    p.bmi - a.bmi_index as bmi_change_1y format=8.2,
    case
      when not missing(a.bmi_index) and a.bmi_index > 0 and not missing(p.bmi)
      then ((p.bmi - a.bmi_index) / a.bmi_index)
      else .
    end as bmi_pct_change_1y format=percent8.2
  from ywan2026.bs_bmi_baseline365 as a
  left join ywan2026.bmi_post1y_pick as p
    on a.patient_id = p.patient_id
   and a.bs_date    = p.bs_date;
quit;

/*=============================================================
  STEP 6. QC
=============================================================*/
proc sql;
  create table qc08.bmi_pre_counts as
  select
    (select count(*) from ywan2026.bs_pt) as n_bs_pt,
    (select count(*) from ywan2026.bmi_raw) as n_bmi_raw,
    (select count(*) from ywan2026.bmi_all) as n_bmi_clean,
    (select count(*) from qc08.bmi_bad_parse) as n_bmi_bad_parse,
    (select count(*) from ywan2026.bmi_pre365_long) as n_bmi_pre365_rows,
    (select count(distinct patient_id) from ywan2026.bmi_pre365_long) as n_bmi_pre365_patients,
    (select count(*) from ywan2026.bs_bmi_baseline365) as n_bmi_baseline_rows,
    (select sum(not missing(bmi_index)) from ywan2026.bs_bmi_baseline365) as n_bmi_baseline_defined,
    (select sum(not missing(bmi_pre1y_first)) from ywan2026.bs_bmi_change_pre1y) as n_bmi_pre1y_defined
  from sashelp.class(obs=1);
quit;

proc sql;
  create table qc08.bmi_post1y_counts as
  select
    (select count(*) from ywan2026.bs_pt) as n_bs_pt,
    (select count(*) from ywan2026.bmi_post1y_long) as n_bmi_post1y_rows,
    (select count(distinct patient_id) from ywan2026.bmi_post1y_long) as n_bmi_post1y_patients,
    (select count(*) from ywan2026.bs_bmi_change_1y) as n_bmi_change1y_rows,
    (select sum(not missing(bmi_1y)) from ywan2026.bs_bmi_change_1y) as n_bmi_1y_defined
  from sashelp.class(obs=1);
quit;

proc means data=ywan2026.bs_bmi_baseline365 n nmiss mean std median p25 p75 min max nway;
  var bmi_index;
  output out=qc08.bmi_baseline_summary(drop=_type_ _freq_)
    n=n_bmi_index
    nmiss=nmiss_bmi_index
    mean=mean_bmi_index
    std=std_bmi_index
    median=median_bmi_index
    p25=p25_bmi_index
    p75=p75_bmi_index
    min=min_bmi_index
    max=max_bmi_index;
run;

proc means data=ywan2026.bs_bmi_change_pre1y n nmiss mean std median p25 p75 min max nway;
  var bmi_pre1y_first bmi_change_pre1y bmi_pct_change_pre1y;
  output out=qc08.bmi_pre1y_change_summary(drop=_type_ _freq_)
    n=n_bmi_pre1y n_bmi_change_pre1y n_bmi_pct_change_pre1y
    nmiss=nmiss_bmi_pre1y nmiss_bmi_change_pre1y nmiss_bmi_pct_change_pre1y
    mean=mean_bmi_pre1y mean_bmi_change_pre1y mean_bmi_pct_change_pre1y
    std=std_bmi_pre1y std_bmi_change_pre1y std_bmi_pct_change_pre1y
    median=median_bmi_pre1y median_bmi_change_pre1y median_bmi_pct_change_pre1y
    p25=p25_bmi_pre1y p25_bmi_change_pre1y p25_bmi_pct_change_pre1y
    p75=p75_bmi_pre1y p75_bmi_change_pre1y p75_bmi_pct_change_pre1y
    min=min_bmi_pre1y min_bmi_change_pre1y min_bmi_pct_change_pre1y
    max=max_bmi_pre1y max_bmi_change_pre1y max_bmi_pct_change_pre1y;
run;

proc means data=ywan2026.bs_bmi_change_1y n nmiss mean std median p25 p75 min max nway;
  var bmi_1y bmi_change_1y bmi_pct_change_1y;
  output out=qc08.bmi_post1y_change_summary(drop=_type_ _freq_)
    n=n_bmi_1y n_bmi_change_1y n_bmi_pct_change_1y
    nmiss=nmiss_bmi_1y nmiss_bmi_change_1y nmiss_bmi_pct_change_1y
    mean=mean_bmi_1y mean_bmi_change_1y mean_bmi_pct_change_1y
    std=std_bmi_1y std_bmi_change_1y std_bmi_pct_change_1y
    median=median_bmi_1y median_bmi_change_1y median_bmi_pct_change_1y
    p25=p25_bmi_1y p25_bmi_change_1y p25_bmi_pct_change_1y
    p75=p75_bmi_1y p75_bmi_change_1y p75_bmi_pct_change_1y
    min=min_bmi_1y min_bmi_change_1y min_bmi_pct_change_1y
    max=max_bmi_1y max_bmi_change_1y max_bmi_pct_change_1y;
run;
