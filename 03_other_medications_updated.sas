/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 03_other_medications_updated
| Date (update): Mar 2026
| Task Purpose :
|   1) Identify selected comedications among BS cohort patients.
|   2) Keep long-format medication records in pre-op windows:
|        -365 to -1 days
|        -180 to -1 days
|   3) Create patient-level binary indicators for both windows.
|
| Inputs:
|   - ywan2026.bs_glp1_patient_v02
|   - tx.medication_ingredient
|
| Outputs:
|   - ywan2026.bs_pt
|   - ywan2026.med_relevant_raw
|   - ywan2026.med_relevant_365d
|   - ywan2026.med_relevant_180d
|   - ywan2026.bs_comed_flags_preop
|   - qc03.window_counts
|   - qc03.flag_prevalence
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname tx       "/dcs07/trinetx/data/may2025datasets/sas";
libname qc03     "/users/ywang6/home/trinetx/March2026_tx/qc/03_other_medications";

/*========================
  Code lists
========================*/
%let METFORMIN = "6809";

%let DPP4 = "593411","1100699","857974","1368001","1992825","729717","1598392","1243019",
            "2281864","1727500","1043562","2117292","1368402","1368384";

%let SGLT2 = "1545653","1373458","1488564","1992672","2627044","2638675","1664314","1545149",
             "1486436","1992684";

%let SULF = "4821","25789","4815","4816","352381","647235","606253","285129";

%let THIAZO = "33738","84108","607999","614348";

%let INSULIN = "253182","1008501","1008509","1605101";

%let AD = "704","7531","5691","3247","3634","3638","2597","321988","2556","32937","4493","36437",
          "72625","39786","30121","8123","10737","31565","15996","6646","6929";

%let AP = "7019","5093","8076","89013","115698","1040028","679314","73178","784649","46303","51272",
          "35636","41996","2626","61381";

%let AC = "38404","39998","28439","114477","31914","32624","25480","187832","40254","2002";

%let ANTIOB = "7243","1551467","37925","8152","1302826","2469247";

%let ALLCODES = &METFORMIN,&DPP4,&SGLT2,&SULF,&THIAZO,&INSULIN,&AD,&AP,&AC,&ANTIOB;

/*=============================================================
  STEP 1. Cohort anchor
=============================================================*/
proc sql;
  create table ywan2026.bs_pt as
  select patient_id, bs_date format=yymmdd10.
  from ywan2026.bs_glp1_patient_v02;
quit;

/*=============================================================
  STEP 2. Pull only relevant medication rows for cohort patients
=============================================================*/
proc sql;
  create table ywan2026.med_relevant_raw as
  select
    b.patient_id,
    b.bs_date format=yymmdd10.,
    m.unique_id,
    m.encounter_id,
    m.code,
    m.code_system,
    m.brand,
    m.route,
    m.strength,
    m.source_id,
    m.start_date
  from ywan2026.bs_pt as b
  inner join tx.medication_ingredient as m
    on b.patient_id = m.patient_id
  where m.code in (&ALLCODES)
    and not missing(m.start_date);
quit;

/*=============================================================
  STEP 3. Robust start_date parsing + derive pre-op windows
=============================================================*/
data ywan2026.med_relevant_all
     qc03.med_bad_start_date(keep=patient_id bs_date unique_id code start_date med_date);
  set ywan2026.med_relevant_raw;

  length start_date_c $40;
  format med_date yymmdd10.;

  start_date_c = strip(vvalue(start_date));
  med_date = input(start_date_c, anydtdte32.);
  if missing(med_date) then med_date = input(compress(start_date_c, '-/ '), yymmdd8.);

  if missing(med_date) then output qc03.med_bad_start_date;
  else output ywan2026.med_relevant_all;

  drop start_date_c;
run;

data ywan2026.med_relevant_365d ywan2026.med_relevant_180d;
  set ywan2026.med_relevant_all;

  if med_date >= (bs_date - 365) and med_date < bs_date then output ywan2026.med_relevant_365d;
  if med_date >= (bs_date - 180) and med_date < bs_date then output ywan2026.med_relevant_180d;
run;

/*=============================================================
  STEP 4. Patient-level flags for each window, then combine
=============================================================*/
proc sql;
  create table ywan2026.bs_comed_flags_365d as
  select
    b.patient_id,

    max(m365.code in (&METFORMIN)) as metformin_365d,
    max(m365.code in (&DPP4))      as dpp4_365d,
    max(m365.code in (&SGLT2))     as sglt2_365d,
    max(m365.code in (&SULF))      as sulfonylurea_365d,
    max(m365.code in (&THIAZO))    as thiazo_365d,
    max(m365.code in (&INSULIN))   as insulin_365d,
    max(m365.code in (&AD))        as antidepressant_365d,
    max(m365.code in (&AP))        as antipsychotic_365d,
    max(m365.code in (&AC))        as anticonvulsant_365d,
    max(m365.code in (&ANTIOB))    as antiobesity_med_365d

  from ywan2026.bs_pt as b
  left join ywan2026.med_relevant_365d as m365
    on b.patient_id = m365.patient_id
  group by b.patient_id;
quit;

proc sql;
  create table ywan2026.bs_comed_flags_180d as
  select
    b.patient_id,

    max(m180.code in (&METFORMIN)) as metformin_180d,
    max(m180.code in (&DPP4))      as dpp4_180d,
    max(m180.code in (&SGLT2))     as sglt2_180d,
    max(m180.code in (&SULF))      as sulfonylurea_180d,
    max(m180.code in (&THIAZO))    as thiazo_180d,
    max(m180.code in (&INSULIN))   as insulin_180d,
    max(m180.code in (&AD))        as antidepressant_180d,
    max(m180.code in (&AP))        as antipsychotic_180d,
    max(m180.code in (&AC))        as anticonvulsant_180d,
    max(m180.code in (&ANTIOB))    as antiobesity_med_180d

  from ywan2026.bs_pt as b
  left join ywan2026.med_relevant_180d as m180
    on b.patient_id = m180.patient_id
  group by b.patient_id;
quit;

proc sql;
  create table ywan2026.bs_comed_flags_preop as
  select
    b.patient_id,
    coalesce(f365.metformin_365d,0) as metformin_365d,
    coalesce(f365.dpp4_365d,0) as dpp4_365d,
    coalesce(f365.sglt2_365d,0) as sglt2_365d,
    coalesce(f365.sulfonylurea_365d,0) as sulfonylurea_365d,
    coalesce(f365.thiazo_365d,0) as thiazo_365d,
    coalesce(f365.insulin_365d,0) as insulin_365d,
    coalesce(f365.antidepressant_365d,0) as antidepressant_365d,
    coalesce(f365.antipsychotic_365d,0) as antipsychotic_365d,
    coalesce(f365.anticonvulsant_365d,0) as anticonvulsant_365d,
    coalesce(f365.antiobesity_med_365d,0) as antiobesity_med_365d,
    coalesce(f180.metformin_180d,0) as metformin_180d,
    coalesce(f180.dpp4_180d,0) as dpp4_180d,
    coalesce(f180.sglt2_180d,0) as sglt2_180d,
    coalesce(f180.sulfonylurea_180d,0) as sulfonylurea_180d,
    coalesce(f180.thiazo_180d,0) as thiazo_180d,
    coalesce(f180.insulin_180d,0) as insulin_180d,
    coalesce(f180.antidepressant_180d,0) as antidepressant_180d,
    coalesce(f180.antipsychotic_180d,0) as antipsychotic_180d,
    coalesce(f180.anticonvulsant_180d,0) as anticonvulsant_180d,
    coalesce(f180.antiobesity_med_180d,0) as antiobesity_med_180d
  from ywan2026.bs_pt as b
  left join ywan2026.bs_comed_flags_365d as f365
    on b.patient_id = f365.patient_id
  left join ywan2026.bs_comed_flags_180d as f180
    on b.patient_id = f180.patient_id;
quit;

/*=============================================================
  STEP 5. QC tables
=============================================================*/
proc sql;
  create table qc03.window_counts as
  select
    (select count(*) from ywan2026.bs_pt) as n_bs_pt,
    (select count(*) from ywan2026.med_relevant_raw) as n_med_relevant_raw,
    (select count(*) from ywan2026.med_relevant_all) as n_med_relevant_parsed,
    (select count(*) from ywan2026.med_relevant_365d) as n_med_365d_rows,
    (select count(distinct patient_id) from ywan2026.med_relevant_365d) as n_med_365d_patients,
    (select count(*) from ywan2026.med_relevant_180d) as n_med_180d_rows,
    (select count(distinct patient_id) from ywan2026.med_relevant_180d) as n_med_180d_patients,
    (select count(*) from qc03.med_bad_start_date) as n_bad_start_date
  from sashelp.class(obs=1);
quit;

proc sql;
  create table qc03.flag_prevalence as
  select
    count(*) as n_patients,
    sum(metformin_365d) as metformin_365d_n,
    sum(dpp4_365d) as dpp4_365d_n,
    sum(sglt2_365d) as sglt2_365d_n,
    sum(sulfonylurea_365d) as sulfonylurea_365d_n,
    sum(thiazo_365d) as thiazo_365d_n,
    sum(insulin_365d) as insulin_365d_n,
    sum(antidepressant_365d) as antidepressant_365d_n,
    sum(antipsychotic_365d) as antipsychotic_365d_n,
    sum(anticonvulsant_365d) as anticonvulsant_365d_n,
    sum(antiobesity_med_365d) as antiobesity_med_365d_n,
    sum(metformin_180d) as metformin_180d_n,
    sum(dpp4_180d) as dpp4_180d_n,
    sum(sglt2_180d) as sglt2_180d_n,
    sum(sulfonylurea_180d) as sulfonylurea_180d_n,
    sum(thiazo_180d) as thiazo_180d_n,
    sum(insulin_180d) as insulin_180d_n,
    sum(antidepressant_180d) as antidepressant_180d_n,
    sum(antipsychotic_180d) as antipsychotic_180d_n,
    sum(anticonvulsant_180d) as anticonvulsant_180d_n,
    sum(antiobesity_med_180d) as antiobesity_med_180d_n
  from ywan2026.bs_comed_flags_preop;
quit;
