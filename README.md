# GLP1 Bariatric TrinetX SAS Scripts

This repository contains SAS scripts used for the March 2026 TrinetX bariatric and GLP-1 analysis workflow.

## Script Order

1. `00_pipeline_updated.sas` - Pipeline setup and shared macro or library configuration.
2. `01_bs_patients_updated.sas` - Identify/index bariatric surgery cohort.
3. `02_glp_1_updated.sas` - Define GLP-1 exposure variables.
4. `03_other_medications_updated.sas` - Extract and classify non-GLP-1 medication use.
5. `04_comorbidity_elixhause_updated.sas` - Build baseline comorbidity variables (Elixhauser-related logic).
6. `05_post_op_complications_updated.sas` - Derive post-operative complication outcomes.
7. `06_post_op_reoperations_updated.sas` - Derive post-operative reoperation outcomes.
8. `07_post_op_rehospitalization_updated.sas` - Derive post-operative rehospitalization outcomes.
9. `08_BMI_updated.sas` - Process BMI baseline/follow-up variables.
10. `09_save_output_tables.sas` - Save and export final tables.
11. `10_weight.sas` - Process weight-related outcomes.

## Notes

- Run scripts in numeric order unless your local workflow specifies otherwise.
- Environment-specific paths may need to be updated before execution.
- Output datasets and logs are intentionally ignored via `.gitignore`.

## Author

Mindy Wang
