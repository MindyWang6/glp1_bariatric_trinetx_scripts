/************************************************************************************
| Project name : Thesis - BS and GLP1
| Program name : 09_save_output_tables
| Date (update): Mar 2026
| Purpose      :
|   Copy final March 2026 analysis-ready output tables and compact QC summaries
|   into /users/ywang6/home/trinetx/March2026_tx/output_march
|
| Notes:
|   - This script copies final outputs only, not large cache/staging tables.
|   - Output library is created if it does not already exist.
************************************************************************************/

options compress=yes reuse=yes msglevel=i dlcreatedir;

libname ywan2026 "/dcs07/trinetx/data/Users/ywan/mar2026";
libname qc01     "/users/ywang6/home/trinetx/March2026_tx/qc/01_bs_patients";
libname qc02     "/users/ywang6/home/trinetx/March2026_tx/qc/02_glp_1";
libname qc03     "/users/ywang6/home/trinetx/March2026_tx/qc/03_other_medications";
libname qc04     "/users/ywang6/home/trinetx/March2026_tx/qc/04_comorbidity_elixhauser";
libname qc05     "/users/ywang6/home/trinetx/March2026_tx/qc/05_post_op_complications";
libname qc06     "/users/ywang6/home/trinetx/March2026_tx/qc/06_post_op_reoperations";
libname qc07     "/users/ywang6/home/trinetx/March2026_tx/qc/07_post_op_rehospitalization";
libname qc08     "/users/ywang6/home/trinetx/March2026_tx/qc/08_bmi";
libname outm     "/users/ywang6/home/trinetx/March2026_tx/output_march";

/*---------------------------
  Final analysis-ready tables
---------------------------*/
proc datasets library=outm nolist;
  delete
    bs_user_demo_v05
    bs_type_combo
    bs_glp1_flags_pt
    bs_glp1_user_v01
    bs_glp1_patient_v02
    bs_comed_flags_preop
    elix_flags_pre365_allpt
    elix_counts_wide
    flag30_allpt
    flag90_allpt
    reop_flags30_dx
    reop_flags90_dx
    reop_flags_allpt
    rehos_flags30_dx
    rehos_flags90_dx
    rehos_flags_allpt
    bs_bmi_baseline365
    bs_bmi_change_pre1y
    bs_bmi_change_1y
  ;
quit;

proc datasets library=outm nolist;
  copy in=ywan2026 out=outm memtype=data;
  select
    bs_user_demo_v05
    bs_type_combo
    bs_glp1_flags_pt
    bs_glp1_user_v01
    bs_glp1_patient_v02
    bs_comed_flags_preop
    elix_flags_pre365_allpt
    elix_counts_wide
    flag30_allpt
    flag90_allpt
    reop_flags30_dx
    reop_flags90_dx
    reop_flags_allpt
    rehos_flags30_dx
    rehos_flags90_dx
    rehos_flags_allpt
    bs_bmi_baseline365
    bs_bmi_change_pre1y
    bs_bmi_change_1y
  ;
quit;

/*---------------------------
  QC summary tables
---------------------------*/
proc datasets library=outm nolist;
  delete
    qc01_bs_exclusion_deletes
    qc02_cohort_counts
    qc02_flag_prevalence
    qc02_final_n_check
    qc03_window_counts
    qc03_flag_prevalence
    qc04_dx_counts
    qc04_elix_flag_counts_any
    qc04_elix_flag_counts_ge2days
    qc05_dx_window_counts
    qc06_px_counts
    qc07_rehos_counts
    qc08_bmi_pre_counts
    qc08_bmi_post1y_counts
    qc08_bmi_baseline_summary
    qc08_bmi_pre1y_change_summary
    qc08_bmi_post1y_change_summary
  ;
quit;

data outm.qc01_bs_exclusion_deletes;   set qc01.bs_exclusion_deletes; run;
data outm.qc02_cohort_counts;          set qc02.cohort_counts; run;
data outm.qc02_flag_prevalence;        set qc02.flag_prevalence; run;
data outm.qc02_final_n_check;          set qc02.final_n_check; run;
data outm.qc03_window_counts;          set qc03.window_counts; run;
data outm.qc03_flag_prevalence;        set qc03.flag_prevalence; run;
data outm.qc04_dx_counts;              set qc04.dx_counts; run;
data outm.qc04_elix_flag_counts_any;   set qc04.elix_flag_counts_any; run;
data outm.qc04_elix_flag_counts_ge2days; set qc04.elix_flag_counts_ge2days; run;
data outm.qc05_dx_window_counts;       set qc05.dx_window_counts; run;
data outm.qc06_px_counts;              set qc06.px_counts; run;
data outm.qc07_rehos_counts;           set qc07.rehos_counts; run;
data outm.qc08_bmi_pre_counts;         set qc08.bmi_pre_counts; run;
data outm.qc08_bmi_post1y_counts;      set qc08.bmi_post1y_counts; run;
data outm.qc08_bmi_baseline_summary;   set qc08.bmi_baseline_summary; run;
data outm.qc08_bmi_pre1y_change_summary; set qc08.bmi_pre1y_change_summary; run;
data outm.qc08_bmi_post1y_change_summary; set qc08.bmi_post1y_change_summary; run;

/*---------------------------
  Simple inventory check
---------------------------*/
proc sql;
  create table outm.output_inventory as
  select memname, nobs
  from dictionary.tables
  where libname = "OUTM"
  order by memname;
quit;

