/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 05_post_op_complications_updated
| Date (update): Mar 2026
| Task Purpose :
|   1) Identify post-operative complications after BS using diagnosis codes.
|   2) Create patient-level complication flags within 30d and 90d.
|
| Inputs:
|   - ywan2026.bs_pt
|   - ywan2026.dx_bs_all   (from 04_comorbidity_elixhause_updated.sas)
|
| Outputs:
|   - ywan2026.dx_post90_long
|   - ywan2026.dx_post30
|   - ywan2026.dx_post90
|   - ywan2026.flag30_dx
|   - ywan2026.flag90_dx
|   - ywan2026.flag30_allpt
|   - ywan2026.flag90_allpt
|   - qc05.dx_window_counts
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname qc05     "/users/ywang6/home/trinetx/March2026_tx/qc/05_post_op_complications";

/*=============================================================
  STEP 1. Post-op diagnosis long table using dx already parsed in step 04
=============================================================*/
data ywan2026.dx_post90_long;
  set ywan2026.dx_bs_all;
  length dx_nodot $20;
  if missing(dx_date) or missing(bs_date) then delete;
  if dx_date < bs_date then delete;
  if dx_date > (bs_date + 90) then delete;

  days_from_bs = dx_date - bs_date;
  dx_nodot = compress(upcase(code), '.');
run;

data ywan2026.dx_post30 ywan2026.dx_post90;
  set ywan2026.dx_post90_long;
  if 0 <= days_from_bs <= 30 then output ywan2026.dx_post30;
  if 0 <= days_from_bs <= 90 then output ywan2026.dx_post90;
run;

/*=============================================================
  STEP 2. Patient-level flags for both windows
=============================================================*/
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

    max(case when 0 <= days_from_bs <= 30 and (
      dx_nodot in (
        "T8141","T8142",
        "L03311","L03312","L03313","L03314","L03315","L03316","L03317","L03319",
        "L03321","L03322","L03323","L03324","L03325","L03326","L03327","L03329",
        "L03811","L03818","L03891","L03898","L0390","L0391",
        "L080","L0881","L0882","L0889","L089","L928","L983"
      )
      or (substr(dx_nodot,1,4)="T814" and substr(dx_nodot,length(dx_nodot),1)="A")
    ) then 1 else 0 end) as WI,
    max(case when 0 <= days_from_bs <= 90 and (
      dx_nodot in (
        "T8141","T8142",
        "L03311","L03312","L03313","L03314","L03315","L03316","L03317","L03319",
        "L03321","L03322","L03323","L03324","L03325","L03326","L03327","L03329",
        "L03811","L03818","L03891","L03898","L0390","L0391",
        "L080","L0881","L0882","L0889","L089","L928","L983"
      )
      or (substr(dx_nodot,1,4)="T814" and substr(dx_nodot,length(dx_nodot),1)="A")
    ) then 1 else 0 end) as WI_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in (
      "D7801","D7802","D7821","D7822","D7831","D7832",
      "E3601","E3602","E89810","E89811","E89820","E89821",
      "G9731","G9732","G9751","G9752","G9761","G9762",
      "I97410","I97411","I97418","I9742",
      "I97610","I97611","I97618","I97620","I97621","I97630","I97631","I97638",
      "J9561","J9562","J95830","J95831","J95860","J95861",
      "K9161","K9162","K91840","K91841","K91870","K91871",
      "L7601","L7602","L7621","L7622","L7631","L7632",
      "N9961","N9962","N99820","N99821","N99840","N99841"
    ) then 1 else 0 end) as HEM,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in (
      "D7801","D7802","D7821","D7822","D7831","D7832",
      "E3601","E3602","E89810","E89811","E89820","E89821",
      "G9731","G9732","G9751","G9752","G9761","G9762",
      "I97410","I97411","I97418","I9742",
      "I97610","I97611","I97618","I97620","I97621","I97630","I97631","I97638",
      "J9561","J9562","J95830","J95831","J95860","J95861",
      "K9161","K9162","K91840","K91841","K91870","K91871",
      "L7601","L7602","L7621","L7622","L7631","L7632",
      "N9961","N9962","N99820","N99821","N99840","N99841"
    ) then 1 else 0 end) as HEM_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in (
      "I82210","I82211","I82220","I82221","I82290","I82291","I823",
      "I82401","I82402","I82403","I82409","I82411","I82412","I82413","I82419",
      "I82421","I82422","I82423","I82429","I82431","I82432","I82433","I82439",
      "I82441","I82442","I82443","I82449","I82491","I82492","I82493","I82499",
      "I824Y1","I824Y2","I824Y3","I824Y9","I824Z1","I824Z2","I824Z3","I824Z9",
      "I82501","I82502","I82503","I82509","I82511","I82512","I82513","I82519",
      "I82521","I82522","I82523","I82529","I82531","I82532","I82533","I82539",
      "I82541","I82542","I82543","I82549","I82591","I82592","I82593","I82599",
      "I825Y1","I825Y2","I825Y3","I825Y9","I825Z1","I825Z2","I825Z3","I825Z9",
      "I82601","I82602","I82603","I82609","I82611","I82612","I82613","I82619",
      "I82621","I82622","I82623","I82629",
      "I82701","I82702","I82703","I82709","I82711","I82712","I82713","I82719",
      "I82721","I82722","I82723","I82729",
      "I82811","I82812","I82813","I82819","I82890","I82891","I8290","I8291",
      "I82A11","I82A12","I82A13","I82A19","I82A21","I82A22","I82A23","I82A29",
      "I82B11","I82B12","I82B13","I82B19","I82B21","I82B22","I82B23","I82B29",
      "I82C11","I82C12","I82C13","I82C19","I82C21","I82C22","I82C23","I82C29"
    ) then 1 else 0 end) as DVT,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in (
      "I82210","I82211","I82220","I82221","I82290","I82291","I823",
      "I82401","I82402","I82403","I82409","I82411","I82412","I82413","I82419",
      "I82421","I82422","I82423","I82429","I82431","I82432","I82433","I82439",
      "I82441","I82442","I82443","I82449","I82491","I82492","I82493","I82499",
      "I824Y1","I824Y2","I824Y3","I824Y9","I824Z1","I824Z2","I824Z3","I824Z9",
      "I82501","I82502","I82503","I82509","I82511","I82512","I82513","I82519",
      "I82521","I82522","I82523","I82529","I82531","I82532","I82533","I82539",
      "I82541","I82542","I82543","I82549","I82591","I82592","I82593","I82599",
      "I825Y1","I825Y2","I825Y3","I825Y9","I825Z1","I825Z2","I825Z3","I825Z9",
      "I82601","I82602","I82603","I82609","I82611","I82612","I82613","I82619",
      "I82621","I82622","I82623","I82629",
      "I82701","I82702","I82703","I82709","I82711","I82712","I82713","I82719",
      "I82721","I82722","I82723","I82729",
      "I82811","I82812","I82813","I82819","I82890","I82891","I8290","I8291",
      "I82A11","I82A12","I82A13","I82A19","I82A21","I82A22","I82A23","I82A29",
      "I82B11","I82B12","I82B13","I82B19","I82B21","I82B22","I82B23","I82B29",
      "I82C11","I82C12","I82C13","I82C19","I82C21","I82C22","I82C23","I82C29"
    ) then 1 else 0 end) as DVT_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in ("I2601","I2602","I2609","I2690","I2692","I2693","I2694","I2699") then 1 else 0 end) as PE,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in ("I2601","I2602","I2609","I2690","I2692","I2693","I2694","I2699") then 1 else 0 end) as PE_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in ("I9788","I9789") then 1 else 0 end) as CARD,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in ("I9788","I9789") then 1 else 0 end) as CARD_90,

    max(case when 0 <= days_from_bs <= 30 and substr(dx_nodot,1,3)="I21" then 1 else 0 end) as AMI,
    max(case when 0 <= days_from_bs <= 90 and substr(dx_nodot,1,3)="I21" then 1 else 0 end) as AMI_90,

    max(case when 0 <= days_from_bs <= 30 and (
      dx_nodot in ("J182","J811","J810","J9600","J9690","J80","R0603")
      or substr(dx_nodot,1,3)="J95"
      or substr(dx_nodot,1,3)="J96"
    ) then 1 else 0 end) as PULM,
    max(case when 0 <= days_from_bs <= 90 and (
      dx_nodot in ("J182","J811","J810","J9600","J9690","J80","R0603")
      or substr(dx_nodot,1,3)="J95"
      or substr(dx_nodot,1,3)="J96"
    ) then 1 else 0 end) as PULM_90,

    max(case when 0 <= days_from_bs <= 30 and dx_nodot in (
      "J157","J160","J168","J180","J189","J690","J95851","J95859","J9588","J9589",
      "J13","J181","J150","J151","J1520","J15211","J1529","J15212","J153","J154",
      "J155","J156","J158","J159","J14","A481"
    ) then 1 else 0 end) as PINF,
    max(case when 0 <= days_from_bs <= 90 and dx_nodot in (
      "J157","J160","J168","J180","J189","J690","J95851","J95859","J9588","J9589",
      "J13","J181","J150","J151","J1520","J15211","J1529","J15212","J153","J154",
      "J155","J156","J158","J159","J14","A481"
    ) then 1 else 0 end) as PINF_90,

    max(case when 0 <= days_from_bs <= 30 and (
      dx_nodot in ("G970","G038") or substr(dx_nodot,1,4)="I978"
    ) then 1 else 0 end) as CNS,
    max(case when 0 <= days_from_bs <= 90 and (
      dx_nodot in ("G970","G038") or substr(dx_nodot,1,4)="I978"
    ) then 1 else 0 end) as CNS_90,

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

  from ywan2026.dx_post90_long
  group by patient_id, bs_date;
quit;

data ywan2026.flag30_dx;
  set ywan2026.comp_flags_dx(keep=patient_id bs_date BSCP LEAK WD WI HEM DVT PE CARD AMI PULM PINF CNS ARF SEPS OBS SPL SHK);
run;

data ywan2026.flag90_dx;
  set ywan2026.comp_flags_dx(keep=patient_id bs_date BSCP_90 LEAK_90 WD_90 WI_90 HEM_90 DVT_90 PE_90 CARD_90 AMI_90 PULM_90 PINF_90 CNS_90 ARF_90 SEPS_90 OBS_90 SPL_90 SHK_90);
run;

proc sql;
  create table ywan2026.flag30_allpt as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    coalesce(b.BSCP,0) as BSCP,
    coalesce(b.LEAK,0) as LEAK,
    coalesce(b.WD,0)   as WD,
    coalesce(b.WI,0)   as WI,
    coalesce(b.HEM,0)  as HEM,
    coalesce(b.DVT,0)  as DVT,
    coalesce(b.PE,0)   as PE,
    coalesce(b.CARD,0) as CARD,
    coalesce(b.AMI,0)  as AMI,
    coalesce(b.PULM,0) as PULM,
    coalesce(b.PINF,0) as PINF,
    coalesce(b.CNS,0)  as CNS,
    coalesce(b.ARF,0)  as ARF,
    coalesce(b.SEPS,0) as SEPS,
    coalesce(b.OBS,0)  as OBS,
    coalesce(b.SPL,0)  as SPL,
    coalesce(b.SHK,0)  as SHK
  from ywan2026.bs_pt as a
  left join ywan2026.flag30_dx as b
    on a.patient_id=b.patient_id and a.bs_date=b.bs_date;
quit;

proc sql;
  create table ywan2026.flag90_allpt as
  select
    a.patient_id,
    a.bs_date format=yymmdd10.,
    coalesce(b.BSCP_90,0) as BSCP_90,
    coalesce(b.LEAK_90,0) as LEAK_90,
    coalesce(b.WD_90,0)   as WD_90,
    coalesce(b.WI_90,0)   as WI_90,
    coalesce(b.HEM_90,0)  as HEM_90,
    coalesce(b.DVT_90,0)  as DVT_90,
    coalesce(b.PE_90,0)   as PE_90,
    coalesce(b.CARD_90,0) as CARD_90,
    coalesce(b.AMI_90,0)  as AMI_90,
    coalesce(b.PULM_90,0) as PULM_90,
    coalesce(b.PINF_90,0) as PINF_90,
    coalesce(b.CNS_90,0)  as CNS_90,
    coalesce(b.ARF_90,0)  as ARF_90,
    coalesce(b.SEPS_90,0) as SEPS_90,
    coalesce(b.OBS_90,0)  as OBS_90,
    coalesce(b.SPL_90,0)  as SPL_90,
    coalesce(b.SHK_90,0)  as SHK_90
  from ywan2026.bs_pt as a
  left join ywan2026.flag90_dx as b
    on a.patient_id=b.patient_id and a.bs_date=b.bs_date;
quit;

proc sql;
  create table qc05.dx_window_counts as
  select
    (select count(*) from ywan2026.bs_pt) as n_bs_pt,
    (select count(*) from ywan2026.dx_post90_long) as n_dx_post90_rows,
    (select count(distinct patient_id) from ywan2026.dx_post90_long) as n_dx_post90_patients,
    (select count(*) from ywan2026.dx_post30) as n_dx_post30_rows,
    (select count(*) from ywan2026.flag30_allpt) as n_flag30_rows,
    (select count(*) from ywan2026.flag90_allpt) as n_flag90_rows
  from sashelp.class(obs=1);
quit;
