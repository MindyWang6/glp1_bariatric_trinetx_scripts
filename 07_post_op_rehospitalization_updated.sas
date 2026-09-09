/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 07_post_op_rehospitalization_updated
| Date (update): Mar 2026
| Task Purpose :
|   1) Identify rehospitalization within 30d and 90d after BS using encounter data.
|   2) Create patient-level 30d and 90d flags.
|
| Inputs:
|   - ywan2026.bs_pt
|   - tx.procedure
|   - tx.encounter
|
| Outputs:
|   - ywan2026.bs_pte
|   - ywan2026.bs_pt_enc
|   - ywan2026.rehos30_long
|   - ywan2026.rehos90_long
|   - ywan2026.rehos_flags30_dx
|   - ywan2026.rehos_flags90_dx
|   - ywan2026.rehos_flags_allpt
|   - qc07.rehos_counts
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname tx       "/dcs07/trinetx/data/may2025datasets/sas";
libname qc07     "/users/ywang6/home/trinetx/March2026_tx/qc/07_post_op_rehospitalization";

/*=============================================================
  STEP 1. Match BS date to procedure encounter_id
=============================================================*/
proc sql;
  create table ywan2026.bs_pte_raw as
  select
    b.patient_id,
    b.bs_date format=yymmdd10.,
    p.encounter_id,
    p.date as proc_date_raw
  from ywan2026.bs_pt as b
  inner join tx.procedure as p
    on b.patient_id = p.patient_id
  where not missing(p.encounter_id)
    and not missing(p.date);
quit;

data ywan2026.bs_pte;
  set ywan2026.bs_pte_raw;
  length proc_date_c $40;
  format proc_date yymmdd10.;
  proc_date_c = strip(vvalue(proc_date_raw));
  proc_date = input(proc_date_c, anydtdte32.);
  if missing(proc_date) then proc_date = input(compress(proc_date_c, '-/ '), yymmdd8.);
  if proc_date = bs_date;
  keep patient_id bs_date encounter_id;
run;

/*=============================================================
  STEP 2. Pull encounter rows once and parse dates once
=============================================================*/
proc sql;
  create table ywan2026.bs_enc_raw as
  select
    b.patient_id,
    b.bs_date format=yymmdd10.,
    e.encounter_id,
    e.type length=12,
    e.start_date as enc_start_raw,
    e.end_date as enc_end_raw
  from ywan2026.bs_pt as b
  left join tx.encounter as e
    on b.patient_id = e.patient_id;
quit;

data ywan2026.bs_enc_all
     qc07.enc_bad_date(keep=patient_id bs_date encounter_id type enc_start_raw enc_end_raw enc_start enc_end);
  set ywan2026.bs_enc_raw;
  length enc_start_c enc_end_c $40;
  format enc_start enc_end yymmdd10.;

  enc_start_c = strip(vvalue(enc_start_raw));
  enc_end_c = strip(vvalue(enc_end_raw));

  enc_start = input(enc_start_c, anydtdte32.);
  if missing(enc_start) then enc_start = input(compress(enc_start_c, '-/ '), yymmdd8.);

  enc_end = input(enc_end_c, anydtdte32.);
  if missing(enc_end) then enc_end = input(compress(enc_end_c, '-/ '), yymmdd8.);

  if missing(enc_start) and not missing(enc_start_raw) then output qc07.enc_bad_date;
  else output ywan2026.bs_enc_all;

  drop enc_start_c enc_end_c;
run;

data ywan2026.bs_enc_all15;
  set ywan2026.bs_enc_all;
  if not missing(enc_start) and enc_start >= '01JAN2015'd;
run;

data ywan2026.bs_enc_post90;
  set ywan2026.bs_enc_all15;
  if not missing(enc_start) and enc_start >= bs_date and enc_start <= (bs_date + 90);
run;

/*=============================================================
  STEP 3. Choose index encounter spanning BS date
=============================================================*/
data ywan2026.bs_enc_candidates;
  set ywan2026.bs_enc_all15;
  if missing(enc_start) or missing(bs_date) then delete;

  if enc_start <= bs_date and ((not missing(enc_end) and bs_date <= enc_end) or missing(enc_end)) then do;
    days_before_bs = bs_date - enc_start;
    if not missing(enc_end) then days_after_bs = enc_end - bs_date;
    else days_after_bs = .;

    if upcase(type) = "IMP" then type_rank = 1;
    else if upcase(type) = "EMER" then type_rank = 2;
    else type_rank = 9;
    output;
  end;
run;

proc sort data=ywan2026.bs_enc_candidates out=ywan2026.bs_enc_candidates_s;
  by patient_id bs_date type_rank days_before_bs days_after_bs;
run;

data ywan2026.bs_enc_index;
  set ywan2026.bs_enc_candidates_s;
  by patient_id bs_date;
  if first.bs_date;
run;

proc sql;
  create table ywan2026.bs_pt_enc as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    b.encounter_id,
    b.type,
    b.enc_start format=yymmdd10.,
    b.enc_end format=yymmdd10.,
    b.days_before_bs,
    b.days_after_bs
  from ywan2026.bs_pt as a
  left join ywan2026.bs_enc_index as b
    on a.patient_id = b.patient_id
   and a.bs_date = b.bs_date;
quit;

/*=============================================================
  STEP 4. 30d and 90d rehospitalization eligibility + long tables
=============================================================*/
data ywan2026.bs_pt_enc_elig30 ywan2026.bs_pt_enc_elig90;
  set ywan2026.bs_pt_enc;

  rehos30_eligible = 0;
  rehos90_eligible = 0;
  if not missing(enc_end) and not missing(bs_date) then do;
    if enc_end >= bs_date and enc_end <= (bs_date + 30) then rehos30_eligible = 1;
    if enc_end >= bs_date and enc_end <= (bs_date + 90) then rehos90_eligible = 1;
  end;

  output ywan2026.bs_pt_enc_elig30;
  output ywan2026.bs_pt_enc_elig90;
run;

proc sql;
  create table ywan2026.rehos30_long as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    a.encounter_id as index_encounter_id,
    a.enc_end format=yymmdd10.,
    e.encounter_id as rehos_encounter_id,
    e.type as rehos_type length=12,
    e.enc_start format=yymmdd10.,
    e.enc_end format=yymmdd10.,
    (e.enc_start - a.enc_end) as days_from_discharge
  from ywan2026.bs_pt_enc_elig30 as a
  inner join ywan2026.bs_enc_post90 as e
    on a.patient_id = e.patient_id
   and a.bs_date = e.bs_date
  where a.rehos30_eligible = 1
    and not missing(e.enc_start)
    and e.encounter_id ne a.encounter_id
    and e.enc_start > a.enc_end
    and e.enc_start <= (a.enc_end + 30);
quit;

proc sql;
  create table ywan2026.rehos90_long as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    a.encounter_id as index_encounter_id,
    a.enc_end format=yymmdd10.,
    e.encounter_id as rehos_encounter_id,
    e.type as rehos_type length=12,
    e.enc_start format=yymmdd10.,
    e.enc_end format=yymmdd10.,
    (e.enc_start - a.enc_end) as days_from_discharge
  from ywan2026.bs_pt_enc_elig90 as a
  inner join ywan2026.bs_enc_post90 as e
    on a.patient_id = e.patient_id
   and a.bs_date = e.bs_date
  where a.rehos90_eligible = 1
    and not missing(e.enc_start)
    and e.encounter_id ne a.encounter_id
    and e.enc_start > a.enc_end
    and e.enc_start <= (a.enc_end + 90);
quit;

proc sql;
  create table ywan2026.rehos_flags30_dx as
  select
    patient_id,
    bs_date format=yymmdd10.,
    1 as rehos_30,
    max(case when upcase(rehos_type)="IMP" then 1 else 0 end) as rehos_imp_30,
    max(case when upcase(rehos_type)="EMER" then 1 else 0 end) as rehos_emer_30,
    max(case when missing(rehos_type) or upcase(rehos_type) not in ("IMP","EMER") then 1 else 0 end) as rehos_other_30
  from ywan2026.rehos30_long
  group by patient_id, bs_date;
quit;

proc sql;
  create table ywan2026.rehos_flags90_dx as
  select
    patient_id,
    bs_date format=yymmdd10.,
    1 as rehos_90,
    max(case when upcase(rehos_type)="IMP" then 1 else 0 end) as rehos_imp_90,
    max(case when upcase(rehos_type)="EMER" then 1 else 0 end) as rehos_emer_90,
    max(case when missing(rehos_type) or upcase(rehos_type) not in ("IMP","EMER") then 1 else 0 end) as rehos_other_90
  from ywan2026.rehos90_long
  group by patient_id, bs_date;
quit;

proc sql;
  create table ywan2026.rehos_flags_allpt as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    a.rehos30_eligible,
    c.rehos90_eligible,
    coalesce(b.rehos_30,0) as rehos_30,
    coalesce(b.rehos_imp_30,0) as rehos_imp_30,
    coalesce(b.rehos_emer_30,0) as rehos_emer_30,
    coalesce(b.rehos_other_30,0) as rehos_other_30,
    coalesce(d.rehos_90,0) as rehos_90,
    coalesce(d.rehos_imp_90,0) as rehos_imp_90,
    coalesce(d.rehos_emer_90,0) as rehos_emer_90,
    coalesce(d.rehos_other_90,0) as rehos_other_90
  from ywan2026.bs_pt_enc_elig30 as a
  left join ywan2026.rehos_flags30_dx as b
    on a.patient_id = b.patient_id and a.bs_date = b.bs_date
  left join ywan2026.bs_pt_enc_elig90 as c
    on a.patient_id = c.patient_id and a.bs_date = c.bs_date
  left join ywan2026.rehos_flags90_dx as d
    on a.patient_id = d.patient_id and a.bs_date = d.bs_date;
quit;

proc sql;
  create table qc07.rehos_counts as
  select
    (select count(*) from ywan2026.bs_pt) as n_bs_pt,
    (select count(*) from ywan2026.bs_pte) as n_bs_pte_rows,
    (select count(*) from ywan2026.bs_pt_enc) as n_bs_pt_enc_rows,
    (select count(*) from ywan2026.rehos30_long) as n_rehos30_long,
    (select count(*) from ywan2026.rehos90_long) as n_rehos90_long,
    (select count(*) from ywan2026.rehos_flags_allpt) as n_rehos_allpt,
    (select count(*) from qc07.enc_bad_date) as n_enc_bad_date
  from sashelp.class(obs=1);
quit;
