#%%bash
#H1 Run RRE
cd ~/gits/rated-ranking-evaluator/rre-tools
pwd
#%%bash
uv run dataset_generator --config ~/gits/berlinbuzzwords/2026/dataset-generator/config.yaml
#%%bash
#H1 Feed the output
cd ~/gits/berlinbuzzwords/2026
pwd
#%%bash
vespa feed --progress 3 dataset-generator/output/judgments.jsonl