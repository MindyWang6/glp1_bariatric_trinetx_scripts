/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 02_glp_1_updated
| Date (update): Mar 2026
| Task Purpose :
|   1) Identify GLP-1 exposure among BS cohort patients
|   2) Derive pre-BS timing indicators (before BS, 6m pre-BS, 12m pre-BS)
|   3) Keep one patient-level record using GLP-1 date closest to BS date
|
| Inputs:
|   - ywan2026.bs_user_demo_v05
|   - tx.medication_ingredient
|
| Outputs:
|   - ywan2026.bs_glp1_user_v00
|   - ywan2026.bs_glp1_flags_pt
|   - ywan2026.bs_glp1_user_v01
|   - ywan2026.bs_glp1_patient_v02
|   - ywan2026.bs_glp1_pre365_long
|   - QC tables under qc02.*
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname tx       "/dcs07/trinetx/data/may2025datasets/sas";
libname qc02     "/users/ywang6/home/trinetx/March2026_tx/qc/02_glp_1";

/* GLP-1 ingredient RxNorm codes */
%let GLP1_CODES = "1991302","1551291","475968","60548","1440051","2601723";

/*=============================================================
  STEP 1. Cohort anchor (BS patients)
=============================================================*/
proc sql;
  create table ywan2026.bs_pt_glp1 as
  select
    patient_id,
    date_dt as bs_date format=yymmdd10.
  from ywan2026.bs_user_demo_v05;
quit;

/*=============================================================
  STEP 2. Pull GLP-1 records only for cohort patients (speed-up)
=============================================================*/
proc sql;
  create table ywan2026.glp1_user_all as
  select
    b.patient_id,
    b.bs_date,
    m.unique_id,
    m.encounter_id,
    m.code,
    input(m.start_date, yymmdd10.) as start_date format=yymmdd10.
  from ywan2026.bs_pt_glp1 as b
  left join tx.medication_ingredient as m
    on b.patient_id = m.patient_id
   and m.code in (&GLP1_CODES)
   and not missing(m.start_date)
  ;
quit;

data ywan2026.glp1_user_all;
  set ywan2026.glp1_user_all;
  length molecule $20 indication $12;

  if missing(start_date) then do;
    molecule = '';
    indication = '';
  end;
  else do;
    select (code);
      when ("1991302") molecule = "Semaglutide";
      when ("1551291") molecule = "Dulaglutide";
      when ("475968")  molecule = "Liraglutide";
      when ("60548")   molecule = "Exenatide";
      when ("1440051") molecule = "Lixisenatide";
      when ("2601723") molecule = "Tirzepatide";
      otherwise         molecule = "Unknown";
    end;

    if molecule in ("Semaglutide","Dulaglutide","Tirzepatide") then indication="Obesity";
    else indication="Other";
  end;
run;

proc sort data=ywan2026.glp1_user_all nodupkey;
  by patient_id unique_id start_date;
run;

/*=============================================================
  STEP 3. Initiation date + record-level joined output
=============================================================*/
proc sql;
  create table ywan2026.glp1_user_all_v01 as
  select
    patient_id,
    min(start_date) as initiation_date format=yymmdd10.
  from ywan2026.glp1_user_all
  where not missing(start_date)
  group by patient_id;
quit;

proc sql;
  create table ywan2026.bs_glp1_user_v00 as
  select
    a.*,
    b.bs_type_combo,
    b.sex,
    b.race,
    b.ethnicity,
    b.marital_status,
    b.patient_regional_location,
    b.source_id,
    b.year_of_birth,
    b.age_at_bs,
    b.death_date,
    b.death_date_source_id,
    b.death_same_or_next_month,
    b.death_within_3m,

    g.unique_id   as glp1_unique_id,
    g.start_date  as glp1_start_date format=yymmdd10.,
    g.molecule    as glp1_molecule,
    g.indication  as glp1_indication,
    i.initiation_date

  from ywan2026.bs_pt_glp1 as a
  left join ywan2026.bs_user_demo_v05 as b
    on a.patient_id = b.patient_id
  left join ywan2026.glp1_user_all as g
    on a.patient_id = g.patient_id
  left join ywan2026.glp1_user_all_v01 as i
    on a.patient_id = i.patient_id
  ;
quit;

/*=============================================================
  STEP 4. Patient-level GLP-1 timing flags
=============================================================*/
proc sql;
  create table ywan2026.bs_glp1_flags_pt as
  select
    patient_id,
    bs_date,

    max(not missing(initiation_date) and initiation_date < bs_date) as glp1_before_bs,

    max(not missing(glp1_start_date)
        and glp1_start_date >= (bs_date - 180)
        and glp1_start_date < bs_date) as glp1_6mb,

    max(not missing(glp1_start_date)
        and glp1_start_date >= (bs_date - 365)
        and glp1_start_date < bs_date) as glp1_12mb

  from ywan2026.bs_glp1_user_v00
  group by patient_id, bs_date;
quit;

/*=============================================================
  STEP 4B. Long table: GLP-1 records within 365d before BS only
=============================================================*/
proc sql;
  create table ywan2026.bs_glp1_pre365_long as
  select
    patient_id,
    bs_date format=yymmdd10.,
    glp1_unique_id,
    glp1_start_date format=yymmdd10.,
    glp1_molecule,
    glp1_indication,
    initiation_date format=yymmdd10.
  from ywan2026.bs_glp1_user_v00
  where not missing(glp1_unique_id)
    and not missing(glp1_start_date)
    and glp1_start_date >= (bs_date - 365)
    and glp1_start_date < bs_date
  order by patient_id, glp1_start_date, glp1_unique_id;
quit;

proc sql;
  create table ywan2026.bs_glp1_user_v01 as
  select
    a.*,
    f.glp1_before_bs,
    f.glp1_6mb,
    f.glp1_12mb
  from ywan2026.bs_glp1_user_v00 as a
  left join ywan2026.bs_glp1_flags_pt as f
    on a.patient_id = f.patient_id
   and a.bs_date    = f.bs_date;
quit;

/*=============================================================
  STEP 5. Keep one record per patient (closest GLP-1 start to BS)
=============================================================*/
data ywan2026.bs_glp1_user_v01_dist;
  set ywan2026.bs_glp1_user_v01;

  if not missing(glp1_start_date) then dist_days = abs(glp1_start_date - bs_date);
  else dist_days = .;
run;

proc sort data=ywan2026.bs_glp1_user_v01_dist out=ywan2026.bs_glp1_user_v01_srt;
  by patient_id dist_days glp1_start_date;
run;

data ywan2026.bs_glp1_patient_v02;
  set ywan2026.bs_glp1_user_v01_srt;
  by patient_id;

  if first.patient_id;

  keep
    patient_id
    age_at_bs
    bs_date
    bs_type_combo
    sex race ethnicity marital_status patient_regional_location source_id
    death_date death_date_source_id death_same_or_next_month death_within_3m
    glp1_unique_id
    glp1_start_date
    glp1_molecule
    glp1_indication
    initiation_date
    glp1_before_bs
    glp1_6mb
    glp1_12mb
    dist_days;
run;

/*=============================================================
  STEP 6. QC tables (saved to local qc folder)
=============================================================*/
proc sql;
  create table qc02.cohort_counts as
  select
    count(*) as n_bs_pt,
    sum(not missing(glp1_unique_id)) as n_bs_glp1_record_rows,
    count(distinct case when not missing(glp1_unique_id) then patient_id end) as n_bs_glp1_patients
  from ywan2026.bs_glp1_user_v00;
quit;

proc freq data=ywan2026.bs_glp1_user_v00 noprint;
  tables glp1_molecule / missing out=qc02.glp1_molecule_freq;
run;

proc sql;
  create table qc02.flag_prevalence as
  select
    count(*) as n_total_bs_patients,
    sum(glp1_before_bs=1) as n_glp1_before_bs,
    sum(glp1_6mb=1) as n_glp1_6mb,
    sum(glp1_12mb=1) as n_glp1_12mb,
    calculated n_glp1_before_bs / calculated n_total_bs_patients as pct_glp1_before_bs format=percent8.2,
    calculated n_glp1_6mb / calculated n_total_bs_patients as pct_glp1_6mb format=percent8.2,
    calculated n_glp1_12mb / calculated n_total_bs_patients as pct_glp1_12mb format=percent8.2
  from ywan2026.bs_glp1_patient_v02;
quit;

proc sql;
  create table qc02.final_n_check as
  select
    (select count(*) from ywan2026.bs_pt_glp1) as n_bs_pt,
    (select count(*) from ywan2026.bs_glp1_patient_v02) as n_final_rows,
    (select count(distinct patient_id) from ywan2026.bs_glp1_patient_v02) as n_final_distinct_pt
  from sashelp.class(obs=1);
quit;
