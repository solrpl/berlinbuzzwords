import tensorflow as tf
from bert.tokenization.bert_tokenization import FullTokenizer

### ENV VARS (need to be the same as in training)
MAX_SEQ_LENGTH = 32
SAVED_MODEL_PATH = '/Users/radu/Documents/bbuzz/saved_model'
BERT_LOCATION = '/Users/radu/Documents/bbuzz/bert_tiny'

query = "which decision tree should I use"

UNIQUE_DOMAINS_FILE = "/Users/radu/Documents/bbuzz/classes"

def tokenize(query):
    tokenizer = FullTokenizer(vocab_file=f"{BERT_LOCATION}/vocab.txt")

    tokens = ["[CLS]"] + tokenizer.tokenize(query) + ["[SEP]"]
    token_ids = tokenizer.convert_tokens_to_ids(tokens)

    # padding as we do it in train.IntentDetectionData._pad
    token_ids = token_ids[:min(len(token_ids), MAX_SEQ_LENGTH - 2)]
    token_ids = token_ids + [0] * (MAX_SEQ_LENGTH - len(token_ids))

    return token_ids

def load_unique_domains():
    with open(UNIQUE_DOMAINS_FILE) as f:
        return [line.rstrip('\n') for line in f]

if __name__ == "__main__":
    new_model = tf.saved_model.load(SAVED_MODEL_PATH)

    # we do the BERT tokenization outside the model
    token_ids = tokenize(query)

    # this is our default signature, we just try to use it
    predict = new_model.signatures["serving_default"]

    # here we do the actual prediction
    predictions = predict(tf.convert_to_tensor(token_ids, dtype=tf.int32))

    # get the output of the last layer. We called it "predictions" in create_model()
    output_tensor = predictions['predictions']


    # the maximum is our best guess
    index = tf.math.argmax(output_tensor, axis=-1).numpy()[0]

    # classes are numeric, we load the text descriptions from where we saved them
    UNIQUE_DOMAINS = load_unique_domains()

    # print that best guess
    print("text:", query, "\nintent:", UNIQUE_DOMAINS[index])