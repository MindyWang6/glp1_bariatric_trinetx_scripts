/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 00_pipeline_updated
| Date (update): Mar 2026
| Purpose      : Faster end-to-end feature build on JHUPCE using one-time cohort caches.
|
| Core optimization:
|   1) Build bs_pt once.
|   2) Read each large tx.* table once into a small cohort cache.
|   3) Derive 03/04/05/06/07/08 outputs from cache tables.
|   4) Keep only required columns in each step.
************************************************************************************/

options compress=yes reuse=yes msglevel=i;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/jan2026";
libname tx       "/dcs07/trinetx/data/may2025datasets/sas";
libname elixfmt  "/users/ywang6/home/trinetx/elixhauser/fmtlib";
options fmtsearch=(elixfmt);

/*=============================================================
  STEP A. Cohort anchor (one row/patient)
=============================================================*/
proc sql;
  create table ywan2026.bs_pt as
  select distinct patient_id, bs_date format=yymmdd10.
  from ywan2026.bs_glp1_patient_v02;
quit;

/*=============================================================
  STEP B. One-time cache tables (the speed-up layer)
=============================================================*/

/* B1) Diagnosis cache: keep only window needed by comorbidity + complications */
proc sql;
  create table ywan2026.dx_cache_raw as
  select
    b.patient_id,
    b.bs_date,
    d.encounter_id,
    d.code_system,
    d.code,
    d.principal_diagnosis_indicator,
    d.admitting_diagnosis,
    d.reason_for_visit,
    d.source_id,
    d.date as dx_date_char
  from ywan2026.bs_pt as b
  inner join tx.diagnosis as d
    on b.patient_id = d.patient_id
  where not missing(d.date);
quit;

data ywan2026.dx_cache;
  set ywan2026.dx_cache_raw;
  dx_date = input(dx_date_char, yymmdd10.);
  format dx_date yymmdd10.;
  if missing(dx_date) then delete;

  /* one window for both modules: pre-365 to post+90 */
  if dx_date < (bs_date - 365) then delete;
  if dx_date > (bs_date + 90) then delete;

  dx_nodot = compress(upcase(code), '.');
run;

/* B2) Procedure cache: needed for reoperation */
proc sql;
  create table ywan2026.px_cache_raw as
  select
    b.patient_id,
    b.bs_date,
    p.encounter_id,
    p.code_system,
    p.code,
    p.source_id,
    p.date as proc_date_char
  from ywan2026.bs_pt as b
  inner join tx.procedure as p
    on b.patient_id = p.patient_id
  where not missing(p.date);
quit;

data ywan2026.px_cache;
  set ywan2026.px_cache_raw;
  proc_date = input(proc_date_char, yymmdd10.);
  format proc_date yymmdd10.;
  if missing(proc_date) then delete;

  /* post-op (exclude day 0) */
  if proc_date <= bs_date then delete;
  if proc_date > (bs_date + 90) then delete;

  days_from_bs = proc_date - bs_date;
  code_nodot   = compress(upcase(code), '.');
run;

/* B3) Medication cache: needed for other meds flags (pre-365 only) */
%let ALLCODES =
"6809",
"593411","1100699","857974","1368001","1992825","729717","1598392","1243019","2281864","1727500","1043562","2117292","1368402","1368384",
"1545653","1373458","1488564","1992672","2627044","2638675","1664314","1545149","1486436","1992684",
"4821","25789","4815","4816","352381","647235","606253","285129",
"33738","84108","607999","614348",
"253182","1008501","1008509","1605101",
"704","7531","5691","3247","3634","3638","2597","321988","2556","32937","4493","36437","72625","39786","30121","8123","10737","31565","15996","6646","6929",
"7019","5093","8076","89013","115698","1040028","679314","73178","784649","46303","51272","35636","41996","2626","61381",
"38404","39998","28439","114477","31914","32624","25480","187832","40254","2002",
"7243","1551467","37925","8152","1302826","2469247";

proc sql;
  create table ywan2026.med_cache_raw as
  select
    b.patient_id,
    b.bs_date,
    m.code,
    m.start_date as med_date_char
  from ywan2026.bs_pt as b
  inner join tx.medication_ingredient as m
    on b.patient_id = m.patient_id
  where m.code in (&ALLCODES)
    and not missing(m.start_date);
quit;

data ywan2026.med_cache;
  set ywan2026.med_cache_raw;
  med_date = input(med_date_char, yymmdd10.);
  format med_date yymmdd10.;
  if missing(med_date) then delete;
  if med_date < (bs_date - 365) then delete;
  if med_date >= bs_date then delete;
run;

/* B4) Vitals cache: needed for BMI baseline */
proc sql;
  create table ywan2026.bmi_cache_raw as
  select
    b.patient_id,
    b.bs_date,
    v.date  as bmi_date_char,
    v.value as bmi_value_char
  from ywan2026.bs_pt as b
  inner join tx.vitals_signs as v
    on b.patient_id = v.patient_id
  where v.code = "39156-5"
    and not missing(v.date)
    and not missing(v.value);
quit;

data ywan2026.bmi_cache;
  set ywan2026.bmi_cache_raw;
  bmi_date = inputn(strip(bmi_date_char), 'yymmdd10.');
  if missing(bmi_date) then bmi_date = inputn(strip(bmi_date_char), 'yymmdd8.');
  bmi = inputn(strip(bmi_value_char), 'best32.');
  format bmi_date yymmdd10. bmi 8.2;

  if missing(bmi_date) or missing(bmi) then delete;
  if bmi < 10 or bmi > 150 then delete;
  if bmi_date < (bs_date - 365) then delete;
  if bmi_date > bs_date then delete;
run;

/* B5) Encounter cache: based on 07_rehospitalization_1.sas */
proc sql;
  create table ywan2026.enc_cache as
  select
    b.patient_id,
    b.bs_date,
    e.encounter_id,
    e.type length=8,
    input(e.start_date, yymmdd10.) as enc_start format=yymmdd10.,
    input(e.end_date,   yymmdd10.) as enc_end   format=yymmdd10.,
    e.start_date as enc_start_char,
    e.end_date   as enc_end_char
  from ywan2026.bs_pt as b
  left join tx.encounter as e
    on b.patient_id = e.patient_id;
quit;

/*=============================================================
  STEP C. 03_other_medications flags (same output name)
=============================================================*/
proc sql;
  create table ywan2026.bs_comed_flags_365d_1 as
  select
    b.patient_id,

    max(m.code="6809") as metformin_365d,
    max(m.code in ("593411","1100699","857974","1368001","1992825","729717","1598392","1243019",
                   "2281864","1727500","1043562","2117292","1368402","1368384")) as dpp4_365d,
    max(m.code in ("1545653","1373458","1488564","1992672","2627044","2638675","1664314","1545149",
                   "1486436","1992684")) as sglt2_365d,
    max(m.code in ("4821","25789","4815","4816","352381","647235","606253","285129")) as sulfonylurea_365d,
    max(m.code in ("33738","84108","607999","614348")) as thiazo_365d,
    max(m.code in ("253182","1008501","1008509","1605101")) as insulin_365d,
    max(m.code in ("704","7531","5691","3247","3634","3638","2597","321988","2556","32937","4493","36437",
                   "72625","39786","30121","8123","10737","31565","15996","6646","6929")) as antidepressant_365d,
    max(m.code in ("7019","5093","8076","89013","115698","1040028","679314","73178","784649","46303","51272",
                   "35636","41996","2626","61381")) as antipsychotic_365d,
    max(m.code in ("38404","39998","28439","114477","31914","32624","25480","187832","40254","2002")) as anticonvulsant_365d,
    max(m.code in ("7243","1551467","37925","8152","1302826","2469247")) as antiobesity_med_365d

  from ywan2026.bs_pt as b
  left join ywan2026.med_cache as m
    on b.patient_id = m.patient_id
  group by b.patient_id;
quit;

/*=============================================================
  STEP D. 04_comorbidity_elixhause from dx_cache
=============================================================*/

data ywan2026.dx_bs_pre365_icd10;
  set ywan2026.dx_cache;
  if strip(upcase(code_system)) ne "ICD-10-CM" then delete;
  if dx_date >= bs_date then delete;
  if dx_date < (bs_date - 365) then delete;
  if missing(dx_nodot) then delete;
run;

data ywan2026.dx_bs_pre365_elix;
  set ywan2026.dx_bs_pre365_icd10;
  elix_grp = put(dx_nodot, $COMFMT.);
  if elix_grp ne dx_nodot;
run;

data ywan2026.dx_bs_pre365_elix_nb;
  set ywan2026.dx_bs_pre365_elix;
  if missing(elix_grp) then delete;
  flag = 1;
  keep patient_id elix_grp flag;
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
  create table ywan2026.elix_flags_pre365_allpt as
  select
    a.patient_id,
    b.*
  from ywan2026.bs_pt as a
  left join ywan2026.elix_flags_pre365 as b
    on a.patient_id = b.patient_id;
quit;

data ywan2026.elix_flags_pre365_allpt;
  set ywan2026.elix_flags_pre365_allpt;
  array x _numeric_;
  do over x;
    if missing(x) then x = 0;
  end;
run;

/*=============================================================
  STEP E. 05_post_op_complications from dx_cache (single aggregation)
=============================================================*/

data ywan2026.dx_post90;
  set ywan2026.dx_cache;
  days_from_bs = dx_date - bs_date;
  if 0 <= days_from_bs <= 90;
run;

proc sql;
  create table ywan2026.comp_flags_dx as
  select
    patient_id,
    bs_date format=yymmdd10.,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in ("K9501","K9509","K9581","K9589") then 1 else 0 end) as BSCP,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in ("K9501","K9509","K9581","K9589") then 1 else 0 end) as BSCP_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in ("T8183") then 1 else 0 end) as LEAK,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in ("T8183") then 1 else 0 end) as LEAK_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in ("T81328","T81329") then 1 else 0 end) as WD,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in ("T81328","T81329") then 1 else 0 end) as WD_90,

    max(case when 0 <= days_from_bs <= 30 and (dx_nodot in (
      "T8141","T8142","L03311","L03312","L03313","L03314","L03315","L03316","L03317","L03319",
      "L03321","L03322","L03323","L03324","L03325","L03326","L03327","L03329",
      "L03811","L03818","L03891","L03898","L0390","L0391","L080","L0881","L0882","L0889","L089","L928","L983")
      or (substr(dx_nodot,1,4)="T814" and substr(dx_nodot,length(dx_nodot),1)="A")) then 1 else 0 end) as WI,

    max(case when 0 <= days_from_bs <= 90 and (dx_nodot in (
      "T8141","T8142","L03311","L03312","L03313","L03314","L03315","L03316","L03317","L03319",
      "L03321","L03322","L03323","L03324","L03325","L03326","L03327","L03329",
      "L03811","L03818","L03891","L03898","L0390","L0391","L080","L0881","L0882","L0889","L089","L928","L983")
      or (substr(dx_nodot,1,4)="T814" and substr(dx_nodot,length(dx_nodot),1)="A")) then 1 else 0 end) as WI_90,

    max(case when 0 <= days_from_bs <= 30 and substr(dx_nodot,1,3)="I21" then 1 else 0 end) as AMI,
    max(case when 0 <= days_from_bs <= 90 and substr(dx_nodot,1,3)="I21" then 1 else 0 end) as AMI_90,

    max(case when 0 <= days_from_bs <= 30 and substr(dx_nodot,1,3)="N17" then 1 else 0 end) as ARF,
    max(case when 0 <= days_from_bs <= 90 and substr(dx_nodot,1,3)="N17" then 1 else 0 end) as ARF_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in ("A4159","A419") then 1 else 0 end) as SEPS,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in ("A4159","A419") then 1 else 0 end) as SEPS_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in ("K560","K561","K562","K563","K564","K565","K566","K567") then 1 else 0 end) as OBS,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in ("K560","K561","K562","K563","K564","K565","K566","K567") then 1 else 0 end) as OBS_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in ("S3600XA") then 1 else 0 end) as SPL,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in ("S3600XA") then 1 else 0 end) as SPL_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in ("T8110") then 1 else 0 end) as SHK,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in ("T8110") then 1 else 0 end) as SHK_90

  from ywan2026.dx_post90
  group by patient_id, bs_date;
quit;

proc sql;
  create table ywan2026.flag30_allpt as
  select
    a.patient_id,
    a.bs_date,
    coalesce(b.BSCP,0) as BSCP,
    coalesce(b.LEAK,0) as LEAK,
    coalesce(b.WD,0)   as WD,
    coalesce(b.WI,0)   as WI,
    0 as HEM,
    0 as DVT,
    0 as PE,
    0 as CARD,
    coalesce(b.AMI,0)  as AMI,
    0 as PULM,
    0 as PINF,
    0 as CNS,
    coalesce(b.ARF,0)  as ARF,
    coalesce(b.SEPS,0) as SEPS,
    coalesce(b.OBS,0)  as OBS,
    coalesce(b.SPL,0)  as SPL,
    coalesce(b.SHK,0)  as SHK
  from ywan2026.bs_pt as a
  left join ywan2026.comp_flags_dx as b
    on a.patient_id=b.patient_id and a.bs_date=b.bs_date;
quit;

proc sql;
  create table ywan2026.flag90_allpt as
  select
    a.patient_id,
    a.bs_date,
    coalesce(b.BSCP_90,0) as BSCP_90,
    coalesce(b.LEAK_90,0) as LEAK_90,
    coalesce(b.WD_90,0)   as WD_90,
    coalesce(b.WI_90,0)   as WI_90,
    0 as HEM_90,
    0 as DVT_90,
    0 as PE_90,
    0 as CARD_90,
    coalesce(b.AMI_90,0)  as AMI_90,
    0 as PULM_90,
    0 as PINF_90,
    0 as CNS_90,
    coalesce(b.ARF_90,0)  as ARF_90,
    coalesce(b.SEPS_90,0) as SEPS_90,
    coalesce(b.OBS_90,0)  as OBS_90,
    coalesce(b.SPL_90,0)  as SPL_90,
    coalesce(b.SHK_90,0)  as SHK_90
  from ywan2026.bs_pt as a
  left join ywan2026.comp_flags_dx as b
    on a.patient_id=b.patient_id and a.bs_date=b.bs_date;
quit;

/*=============================================================
  STEP F. 06_post_op_reoperations from px_cache
=============================================================*/

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
  &REOP_ICD10_REOPEN,&REOP_ICD10_RECLOSE,&REOP_ICD10_HEM,
  &REOP_ICD10_FOREIGN,&REOP_ICD10_SSI,&REOP_ICD10_ORGAN;

proc sql;
  create table ywan2026.reop_flags_allpt as
  select
    a.patient_id,
    a.bs_date,

    max(case when 1 <= p.days_from_bs <= 30 and
             ((p.code_system="ICD-10-PCS" and p.code in (&REOP_ICD10PCS_ALL)) or
              (p.code_system="ICD-9-CM" and p.code_nodot in
               ("5412","5411","5471","3941","3998","4995","5793","6094","415",
                "5492","9820","540","5419","4694","4461","4671","4673","4675","4871","5061")))
             then 1 else 0 end) as reop_any_30,

    max(case when 1 <= p.days_from_bs <= 90 and
             ((p.code_system="ICD-10-PCS" and p.code in (&REOP_ICD10PCS_ALL)) or
              (p.code_system="ICD-9-CM" and p.code_nodot in
               ("5412","5411","5471","3941","3998","4995","5793","6094","415",
                "5492","9820","540","5419","4694","4461","4671","4673","4675","4871","5061")))
             then 1 else 0 end) as reop_any_90

  from ywan2026.bs_pt as a
  left join ywan2026.px_cache as p
    on a.patient_id=p.patient_id and a.bs_date=p.bs_date
  group by a.patient_id, a.bs_date;
quit;

/*=============================================================
  STEP G. 08_BMI baseline (same output name)
=============================================================*/
proc sql;
  create table ywan2026.bmi_day as
  select
    patient_id,
    bs_date,
    bmi_date,
    mean(bmi) as bmi format=8.2
  from ywan2026.bmi_cache
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
    a.bs_date,
    d.baseline_bmi_date,
    p.bmi as bmi_index format=8.2
  from ywan2026.bs_pt as a
  left join ywan2026.bmi_baseline_date365 as d
    on a.patient_id=d.patient_id and a.bs_date=d.bs_date
  left join ywan2026.bmi_day as p
    on d.patient_id=p.patient_id and d.bs_date=p.bs_date and d.baseline_bmi_date=p.bmi_date;
quit;

/*=============================================================
  STEP H. quick QC
=============================================================*/
proc sql;
  title "QC sizes from updated pipeline";
  select "cohort" as tbl, count(*) as n from ywan2026.bs_pt
  union all select "dx_cache", count(*) from ywan2026.dx_cache
  union all select "px_cache", count(*) from ywan2026.px_cache
  union all select "med_cache", count(*) from ywan2026.med_cache
  union all select "bmi_cache", count(*) from ywan2026.bmi_cache
  union all select "enc_cache", count(*) from ywan2026.enc_cache
  union all select "elix_flags_pre365_allpt", count(*) from ywan2026.elix_flags_pre365_allpt
  union all select "flag30_allpt", count(*) from ywan2026.flag30_allpt
  union all select "reop_flags_allpt", count(*) from ywan2026.reop_flags_allpt
  union all select "bs_bmi_baseline365", count(*) from ywan2026.bs_bmi_baseline365;
quit;
title;
