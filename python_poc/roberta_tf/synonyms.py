# from https://github.com/huggingface/notebooks/blob/main/examples/language_modeling-tf.ipynb

from transformers import pipeline

mask_filler = pipeline(
    "fill-mask",
    "roberta-base",
    framework="tf",
)

results = mask_filler("The most common household pets are <mask> and dogs.", top_k=3)

for result in results:
    print(result['sequence'])
# The most common household pets are cats and dogs.
# The most common household pets are children and dogs.
# The most common household pets are people and dogs.