/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 10_weight
| Date (update): Mar 2026
| Task Purpose :
|   Extract weight and height measurements for BS patients within +/- 365 days
|   of BS date, following the parsing approach used in 08_BMI_updated.sas.
|
| Inputs:
|   - ywan2026.bs_pt
|   - tx.vitals_signs
|
| Outputs:
|   - ywan2026.htwt_raw
|   - ywan2026.htwt_all
|   - ywan2026.htwt_pm365_long
|   - ywan2026.weight_pm365_long
|   - ywan2026.height_pm365_long
|   - qc10.htwt_bad_parse
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname tx       "/dcs07/trinetx/data/may2025datasets/sas";
libname qc10     "/users/ywang6/home/trinetx/March2026_tx/qc/10_weight_height";

/*=============================================================
  STEP 1. Pull weight and height rows for BS cohort only
=============================================================*/
proc sql;
  create table ywan2026.htwt_raw as
  select
    b.patient_id,
    b.bs_date format=yymmdd10.,
    v.encounter_id,
    v.code,
    case
      when v.code = "29463-7" then "weight"
      when v.code = "8302-2"  then "height"
      else "other"
    end as measure_type length=8,
    v.date  as measure_date_raw,
    v.value as measure_value_raw,
    v.units_of_measure as units_of_measure_raw
  from ywan2026.bs_pt as b
  inner join tx.vitals_signs as v
    on b.patient_id = v.patient_id
  where v.code in ("29463-7","8302-2")
    and not missing(v.date)
    and not missing(v.value);
quit;

/*=============================================================
  STEP 2. Parse date/value once and keep clean rows
=============================================================*/
data ywan2026.htwt_all
     qc10.htwt_bad_parse(keep=patient_id bs_date encounter_id code measure_type measure_date_raw measure_value_raw units_of_measure_raw);
  set ywan2026.htwt_raw;

  length measure_date_c measure_value_c $40 units_of_measure $50;
  format measure_date yymmdd10. measure_value 12.4;

  measure_date_c = strip(vvalue(measure_date_raw));
  measure_date = inputn(measure_date_c, 'anydtdte32.');
  if missing(measure_date) then measure_date = inputn(compress(measure_date_c, '-/ '), 'yymmdd8.');

  measure_value_c = strip(vvalue(measure_value_raw));
  measure_value = inputn(measure_value_c, 'best32.');
  units_of_measure = strip(vvalue(units_of_measure_raw));

  if missing(measure_date) or missing(measure_value) then output qc10.htwt_bad_parse;
  else output ywan2026.htwt_all;

  drop measure_date_c measure_value_c;
run;

/*=============================================================
  STEP 3. Keep all rows within +/- 365 days of BS date
=============================================================*/
data ywan2026.htwt_pm365_long
     ywan2026.weight_pm365_long
     ywan2026.height_pm365_long;
  set ywan2026.htwt_all;

  days_from_bs = measure_date - bs_date;

  if -365 <= days_from_bs <= 365 then do;
    output ywan2026.htwt_pm365_long;
    if measure_type = "weight" then output ywan2026.weight_pm365_long;
    else if measure_type = "height" then output ywan2026.height_pm365_long;
  end;

  format bs_date measure_date yymmdd10.;
  keep patient_id bs_date encounter_id code measure_type measure_date measure_value units_of_measure days_from_bs;
run;

/*=============================================================
  STEP 4. Basic QC
=============================================================*/
proc sql;
  create table qc10.htwt_counts as
  select
    (select count(*) from ywan2026.bs_pt) as n_bs_pt,
    (select count(*) from ywan2026.htwt_raw) as n_htwt_raw,
    (select count(distinct patient_id) from ywan2026.htwt_raw) as n_htwt_raw_patients,
    (select count(*) from ywan2026.htwt_all) as n_htwt_clean,
    (select count(distinct patient_id) from ywan2026.htwt_all) as n_htwt_clean_patients,
    (select count(*) from qc10.htwt_bad_parse) as n_htwt_bad_parse,
    (select count(*) from ywan2026.htwt_pm365_long) as n_htwt_pm365,
    (select count(distinct patient_id) from ywan2026.htwt_pm365_long) as n_htwt_pm365_patients,
    (select count(*) from ywan2026.weight_pm365_long) as n_weight_pm365,
    (select count(distinct patient_id) from ywan2026.weight_pm365_long) as n_weight_pm365_patients,
    (select count(*) from ywan2026.height_pm365_long) as n_height_pm365,
    (select count(distinct patient_id) from ywan2026.height_pm365_long) as n_height_pm365_patients,
    (select sum(missing(encounter_id)) from ywan2026.htwt_all) as n_clean_missing_encounter_id,
    (select sum(missing(encounter_id)) from ywan2026.htwt_pm365_long) as n_pm365_missing_encounter_id,
    (select sum(missing(units_of_measure)) from ywan2026.htwt_all) as n_clean_missing_units,
    (select sum(missing(units_of_measure)) from ywan2026.htwt_pm365_long) as n_pm365_missing_units
  from sashelp.class(obs=1);
quit;

proc sql;
  create table qc10.htwt_by_type as
  select
    measure_type,
    count(*) as n_rows,
    count(distinct patient_id) as n_patients,
    sum(missing(encounter_id)) as n_missing_encounter_id,
    sum(missing(units_of_measure)) as n_missing_units,
    min(days_from_bs) as min_days_from_bs,
    max(days_from_bs) as max_days_from_bs
  from ywan2026.htwt_pm365_long
  group by measure_type;
quit;

proc freq data=ywan2026.htwt_pm365_long noprint;
  tables measure_type*units_of_measure / out=qc10.htwt_units_freq;
run;

proc means data=ywan2026.weight_pm365_long n nmiss mean std median p25 p75 min max nway;
  var measure_value days_from_bs;
  output out=qc10.weight_pm365_summary(drop=_type_ _freq_)
    n=n_weight_value n_days_from_bs
    nmiss=nmiss_weight_value nmiss_days_from_bs
    mean=mean_weight_value mean_days_from_bs
    std=std_weight_value std_days_from_bs
    median=median_weight_value median_days_from_bs
    p25=p25_weight_value p25_days_from_bs
    p75=p75_weight_value p75_days_from_bs
    min=min_weight_value min_days_from_bs
    max=max_weight_value max_days_from_bs;
run;

proc means data=ywan2026.height_pm365_long n nmiss mean std median p25 p75 min max nway;
  var measure_value days_from_bs;
  output out=qc10.height_pm365_summary(drop=_type_ _freq_)
    n=n_height_value n_days_from_bs
    nmiss=nmiss_height_value nmiss_days_from_bs
    mean=mean_height_value mean_days_from_bs
    std=std_height_value std_days_from_bs
    median=median_height_value median_days_from_bs
    p25=p25_height_value p25_days_from_bs
    p75=p75_height_value p75_days_from_bs
    min=min_height_value min_days_from_bs
    max=max_height_value max_days_from_bs;
run;
