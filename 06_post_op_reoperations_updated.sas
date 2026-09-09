/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 06_post_op_reoperations_updated
| Date (update): Mar 2026
| Task Purpose :
|   1) Identify reoperations within 30d and 90d after BS using procedure codes.
|   2) Create patient-level 30d and 90d flags.
|
| Inputs:
|   - ywan2026.bs_pt
|   - tx.procedure
|
| Outputs:
|   - ywan2026.px_bs_post90
|   - ywan2026.px_bs_post90_prep
|   - ywan2026.reop_flags30_dx
|   - ywan2026.reop_flags90_dx
|   - ywan2026.reop_flags_allpt
|   - qc06.px_counts
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname tx       "/dcs07/trinetx/data/may2025datasets/sas";
libname qc06     "/users/ywang6/home/trinetx/March2026_tx/qc/06_post_op_reoperations";

%let REOP_ICD10_REOPEN =
  "0W3G0ZZ","0W3H0ZZ","0W3P0ZZ","0WJG0ZZ","0WJH0ZZ","0WJJ0ZZ",
  "0DJ00ZZ","0DJ60ZZ","0DJD0ZZ","0DJU0ZZ","0DJW0ZZ","0WJP0ZZ","0WJR0ZZ";
%let REOP_ICD10_RECLOSE = "0WQF0ZZ","0WQF3ZZ","0WQF4ZZ";
%let REOP_ICD10_HEM = "0W3G3ZZ","0W3G4ZZ","0W3H3ZZ","0W3H4ZZ","0W3P3ZZ","0W3P4ZZ";
%let REOP_ICD10_FOREIGN =
  "0DCU0ZZ","0DCU3ZZ","0DCU4ZZ","0DCV0ZZ","0DCV3ZZ","0DCV4ZZ",
  "0DCW0ZZ","0DCW3ZZ","0DCW4ZZ","0WCG0ZZ","0WCG3ZZ","0WCG4ZZ";
%let REOP_ICD10_SSI =
  "0W9F00Z","0W9F0ZZ","0W9H00Z","0W9H0ZZ","0W9H40Z","0W9H4ZZ","0W9G00Z","0W9G0ZZ",
  "0D9U00Z","0D9U0ZZ","0D9V00Z","0D9V0ZZ","0D9W00Z","0D9W0ZZ","0WCJ0ZZ","0WCJ3ZZ",
  "0WCJ4ZZ","0WCP0ZZ","0WCP3ZZ","0WCP4ZZ","0WCR0ZZ","0WCR3ZZ","0WCR4ZZ","0WJF0ZZ",
  "0WJH0ZZ","0Y9500Z","0Y950ZZ","0Y9540Z","0Y954ZZ","0Y9600Z","0Y960ZZ","0Y9640Z",
  "0Y964ZZ","0DQE0ZZ","0DQE3ZZ","0DQE4ZZ","0DQE7ZZ","0DQE8ZZ";
%let REOP_ICD10_ORGAN =
  "0DQ60ZZ","0DQ63ZZ","0DQ64ZZ","0DQ67ZZ","0DQ68ZZ","0DQ80ZZ","0DQ83ZZ","0DQ84ZZ",
  "0DQ87ZZ","0DQ88ZZ","0DQ90ZZ","0DQ93ZZ","0DQ94ZZ","0DQ97ZZ","0DQ98ZZ","0DQP0ZZ",
  "0DQP3ZZ","0DQP4ZZ","0DQP7ZZ","0DQP8ZZ","0FQ00ZZ","0FQ03ZZ","0FQ04ZZ";
%let REOP_ICD10PCS_ALL =
  &REOP_ICD10_REOPEN,&REOP_ICD10_RECLOSE,&REOP_ICD10_HEM,&REOP_ICD10_FOREIGN,&REOP_ICD10_SSI,&REOP_ICD10_ORGAN;

/*=============================================================
  STEP 1. Pull procedure rows for cohort and parse once
=============================================================*/
proc sql;
  create table ywan2026.px_bs_raw as
  select
    b.patient_id,
    b.bs_date format=yymmdd10.,
    p.encounter_id,
    p.code_system,
    p.code,
    p.source_id,
    p.date as proc_date_raw
  from ywan2026.bs_pt as b
  inner join tx.procedure as p
    on b.patient_id = p.patient_id
  where not missing(p.date);
quit;

data ywan2026.px_bs_all
     qc06.px_bad_date(keep=patient_id bs_date encounter_id code_system code proc_date_raw proc_date);
  set ywan2026.px_bs_raw;
  length proc_date_c $40 code_nodot $20;
  format proc_date yymmdd10.;

  proc_date_c = strip(vvalue(proc_date_raw));
  proc_date = input(proc_date_c, anydtdte32.);
  if missing(proc_date) then proc_date = input(compress(proc_date_c, '-/ '), yymmdd8.);

  if missing(proc_date) then output qc06.px_bad_date;
  else do;
    code_nodot = compress(upcase(code), '.');
    output ywan2026.px_bs_all;
  end;

  drop proc_date_c;
run;

data ywan2026.px_bs_post90 ywan2026.px_bs_post90_prep;
  set ywan2026.px_bs_all;
  if proc_date > bs_date and proc_date <= (bs_date + 90) then do;
    days_from_bs = proc_date - bs_date;
    output ywan2026.px_bs_post90;
    output ywan2026.px_bs_post90_prep;
  end;
run;

/*=============================================================
  STEP 2. Reoperation flags
=============================================================*/
proc sql;
  create table ywan2026.reop_flags90_dx as
  select
    patient_id,
    bs_date format=yymmdd10.,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_REOPEN) then 1 else 0 end) as reop_reopen_90,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_RECLOSE) then 1 else 0 end) as reop_reclose_90,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_HEM) then 1 else 0 end) as reop_hem_90,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_FOREIGN) then 1 else 0 end) as reop_foreign_90,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_SSI) then 1 else 0 end) as reop_ssi_90,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_ORGAN) then 1 else 0 end) as reop_organ_90,
    max(case when code_system="ICD-9-CM" and code_nodot in ("5412","5411") then 1 else 0 end) as reop_reopen9_90,
    max(case when code_system="ICD-9-CM" and code_nodot in ("5471") then 1 else 0 end) as reop_reclose9_90,
    max(case when code_system="ICD-9-CM" and code_nodot in ("3941","3998","4995","5793","6094","415") then 1 else 0 end) as reop_hem9_90,
    max(case when code_system="ICD-9-CM" and code_nodot in ("5492","9820") then 1 else 0 end) as reop_foreign9_90,
    max(case when code_system="ICD-9-CM" and code_nodot in ("540","5419","4694") then 1 else 0 end) as reop_ssi9_90,
    max(case when code_system="ICD-9-CM" and code_nodot in ("4461","4671","4673","4675","4871","5061") then 1 else 0 end) as reop_organ9_90,
    max(case when (code_system="ICD-10-PCS" and code in (&REOP_ICD10PCS_ALL))
               or (code_system="ICD-9-CM" and code_nodot in ("5412","5411","5471","3941","3998","4995","5793","6094","415","5492","9820","540","5419","4694","4461","4671","4673","4675","4871","5061"))
             then 1 else 0 end) as reop_any_90
  from ywan2026.px_bs_post90_prep
  where 1 <= days_from_bs <= 90
  group by patient_id, bs_date;
quit;

proc sql;
  create table ywan2026.reop_flags30_dx as
  select
    patient_id,
    bs_date format=yymmdd10.,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_REOPEN) then 1 else 0 end) as reop_reopen_30,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_RECLOSE) then 1 else 0 end) as reop_reclose_30,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_HEM) then 1 else 0 end) as reop_hem_30,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_FOREIGN) then 1 else 0 end) as reop_foreign_30,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_SSI) then 1 else 0 end) as reop_ssi_30,
    max(case when code_system="ICD-10-PCS" and code in (&REOP_ICD10_ORGAN) then 1 else 0 end) as reop_organ_30,
    max(case when code_system="ICD-9-CM" and code_nodot in ("5412","5411") then 1 else 0 end) as reop_reopen9_30,
    max(case when code_system="ICD-9-CM" and code_nodot in ("5471") then 1 else 0 end) as reop_reclose9_30,
    max(case when code_system="ICD-9-CM" and code_nodot in ("3941","3998","4995","5793","6094","415") then 1 else 0 end) as reop_hem9_30,
    max(case when code_system="ICD-9-CM" and code_nodot in ("5492","9820") then 1 else 0 end) as reop_foreign9_30,
    max(case when code_system="ICD-9-CM" and code_nodot in ("540","5419","4694") then 1 else 0 end) as reop_ssi9_30,
    max(case when code_system="ICD-9-CM" and code_nodot in ("4461","4671","4673","4675","4871","5061") then 1 else 0 end) as reop_organ9_30,
    max(case when (code_system="ICD-10-PCS" and code in (&REOP_ICD10PCS_ALL))
               or (code_system="ICD-9-CM" and code_nodot in ("5412","5411","5471","3941","3998","4995","5793","6094","415","5492","9820","540","5419","4694","4461","4671","4673","4675","4871","5061"))
             then 1 else 0 end) as reop_any_30
  from ywan2026.px_bs_post90_prep
  where 1 <= days_from_bs <= 30
  group by patient_id, bs_date;
quit;

proc sql;
  create table ywan2026.reop_flags_allpt as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    coalesce(b.reop_any_30,0) as reop_any_30,
    coalesce(c.reop_any_90,0) as reop_any_90,
    coalesce(b.reop_reopen_30,0)  as reop_reopen_30,
    coalesce(b.reop_reclose_30,0) as reop_reclose_30,
    coalesce(b.reop_hem_30,0)     as reop_hem_30,
    coalesce(b.reop_foreign_30,0) as reop_foreign_30,
    coalesce(b.reop_ssi_30,0)     as reop_ssi_30,
    coalesce(b.reop_organ_30,0)   as reop_organ_30,
    coalesce(c.reop_reopen_90,0)  as reop_reopen_90,
    coalesce(c.reop_reclose_90,0) as reop_reclose_90,
    coalesce(c.reop_hem_90,0)     as reop_hem_90,
    coalesce(c.reop_foreign_90,0) as reop_foreign_90,
    coalesce(c.reop_ssi_90,0)     as reop_ssi_90,
    coalesce(c.reop_organ_90,0)   as reop_organ_90
  from ywan2026.bs_pt as a
  left join ywan2026.reop_flags30_dx as b
    on a.patient_id = b.patient_id and a.bs_date = b.bs_date
  left join ywan2026.reop_flags90_dx as c
    on a.patient_id = c.patient_id and a.bs_date = c.bs_date;
quit;

proc sql;
  create table qc06.px_counts as
  select
    (select count(*) from ywan2026.bs_pt) as n_bs_pt,
    (select count(*) from ywan2026.px_bs_raw) as n_px_raw,
    (select count(*) from ywan2026.px_bs_all) as n_px_parsed,
    (select count(*) from qc06.px_bad_date) as n_px_bad_date,
    (select count(*) from ywan2026.px_bs_post90) as n_px_post90,
    (select count(*) from ywan2026.reop_flags_allpt) as n_reop_allpt
  from sashelp.class(obs=1);
quit;
