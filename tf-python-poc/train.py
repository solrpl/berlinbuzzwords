# credits: https://curiousily.com/posts/intent-recognition-with-bert-using-keras-and-tensorflow-2/

# try with python 3.8
import pandas as pd  # used version 1.4
import tensorflow as tf  # used version 2.4
from tensorflow import keras
from bert import BertModelLayer
from bert.tokenization.bert_tokenization import FullTokenizer
from bert.loader import StockBertConfig, map_stock_config_to_params, load_stock_weights
import numpy as np


### GLOBAL VARS
# download from https://www.kaggle.com/datasets/gauravduttakiit/practice-problem-query-domain-classification?resource=download
LABELED_QUERIES = '/Users/radu/Documents/bbuzz/train.csv'

COLUMNS = ["Title", "Domain"]

# download and unpack from https://github.com/google-research/bert
BERT_LOCATION = '/Users/radu/Documents/bbuzz/bert_tiny'
BERT_CKPT_FILE = f"{BERT_LOCATION}/bert_model.ckpt"
BERT_CONFIG_FILE = f"{BERT_LOCATION}/bert_config.json"

# where to save the unique domains
UNIQUE_DOMAINS_FILE = "/Users/radu/Documents/bbuzz/classes"
UNIQUE_DOMAINS = []

# we truncate long queries to this many tokens
# shorter queries are 0-padded to this
MAX_SEQ_LENGTH = 32

SAVED_MODEL_PATH = '/Users/radu/Documents/bbuzz/saved_model'

LEARNING_RATE = 3e-5
BATCH_SIZE = 16
EPOCHS = 4

def load_data():
    queries = pd.read_csv(LABELED_QUERIES)
    queries = queries.dropna() # drop rows with null values
    queries = queries[["Title", "Domain"]]

    msk = np.random.rand(len(queries)) < 0.8  # 80% train, 20% test
    train = queries[msk]
    test = queries[~msk]

    #print(test.head())

    return queries, train, test, msk


class IntentDetectionData:
  DATA_COLUMN = "Title"
  LABEL_COLUMN = "Domain"

  def __init__(
    self,
    train,
    test,
    tokenizer: FullTokenizer,
    classes,
    max_seq_len=192
  ):
    self.tokenizer = tokenizer
    self.max_seq_len = 0
    self.classes = classes

    ((self.train_x, self.train_y), (self.test_x, self.test_y)) =\
     map(self._prepare, [train, test])

    print("max seq_len", self.max_seq_len)
    self.max_seq_len = min(self.max_seq_len, max_seq_len)
    self.train_x, self.test_x = map(
      self._pad,
      [self.train_x, self.test_x]
    )

  def _prepare(self, df):
    x, y = [], []

    for _, row in df.iterrows():
      text, label =\
       row[IntentDetectionData.DATA_COLUMN], \
       row[IntentDetectionData.LABEL_COLUMN]
      tokens = self.tokenizer.tokenize(text)
      tokens = ["[CLS]"] + tokens + ["[SEP]"]
      token_ids = self.tokenizer.convert_tokens_to_ids(tokens)
      self.max_seq_len = max(self.max_seq_len, len(token_ids))
      x.append(token_ids)
      y.append(self.classes.index(label))

    return np.array(x), np.array(y)

  def _pad(self, ids):
    x = []
    for input_ids in ids:
      input_ids = input_ids[:min(len(input_ids), self.max_seq_len - 2)]
      # FIXME this bugger seems to be sometimes list sometimes ndarray...
      try:
        input_ids = input_ids.tolist()
      except AttributeError:
          pass # I assume it's already a list
      for i in range(self.max_seq_len - len(input_ids)):
          input_ids.append(0)
      x.append(np.array(input_ids))
    return np.array(x)


def create_model(max_seq_len, bert_ckpt_file):

  with tf.io.gfile.GFile(BERT_CONFIG_FILE, "r") as reader:
      bc = StockBertConfig.from_json_string(reader.read())
      bert_params = map_stock_config_to_params(bc)
      bert_params.adapter_size = None
      bert = BertModelLayer.from_params(bert_params, name="bert")

  input_ids = keras.layers.Input(
    shape=(max_seq_len, ),
    dtype='int32',
    name="input_ids"
  )
  bert_output = bert(input_ids)

  #print("bert shape", bert_output.shape)

  cls_out = keras.layers.Lambda(lambda seq: seq[:, 0, :])(bert_output)
  cls_out = keras.layers.Dropout(0.5)(cls_out)
  logits = keras.layers.Dense(units=768, activation="tanh")(cls_out)
  logits = keras.layers.Dropout(0.5)(logits)
  logits = keras.layers.Dense(
    units=len(UNIQUE_DOMAINS),
    activation="softmax",
    name="predictions"
  )(logits)

  model = keras.Model(inputs=input_ids, outputs=logits)
  model.build(input_shape=(None, max_seq_len))

  load_stock_weights(bert, bert_ckpt_file)

  return model


def evaluate(data, model):
    _, train_acc = model.evaluate(data.train_x, data.train_y)
    _, test_acc = model.evaluate(data.test_x, data.test_y)

    print("train acc", train_acc)
    print("test acc", test_acc)


def manually_test(model):
    queries = ["which decision tree should I use",
               "How to become a data scientist"]
    pred_tokens = map(tokenizer.tokenize, queries)
    pred_tokens = map(lambda tok: ["[CLS]"] + tok + ["[SEP]"], pred_tokens)
    pred_token_ids = list(map(tokenizer.convert_tokens_to_ids, pred_tokens))

    pred_token_ids = map(
        lambda tids: tids + [0] * (data.max_seq_len - len(tids)),
        pred_token_ids
    )

    pred_token_ids = np.array(list(pred_token_ids))

    predictions = model.predict(pred_token_ids).argmax(axis=-1)

    for text, label in zip(queries, predictions):
        print("text:", text, "\nintent:", UNIQUE_DOMAINS[label])
        print()


def save(model):
    model.save(SAVED_MODEL_PATH)

    with open(UNIQUE_DOMAINS_FILE, 'w') as classes_file:
        classes_file.write('\n'.join(UNIQUE_DOMAINS))


def build_model():
    data = IntentDetectionData(
        train,
        test,
        tokenizer,
        UNIQUE_DOMAINS,
        max_seq_len=MAX_SEQ_LENGTH
    )

    model = create_model(data.max_seq_len, BERT_CKPT_FILE)

    model.summary()

    model.compile(
        optimizer=keras.optimizers.Adam(LEARNING_RATE),
        loss=keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=[keras.metrics.SparseCategoricalAccuracy(name="acc")]
    )

    model.fit(
        x=data.train_x,
        y=data.train_y,
        validation_split=0.1,
        batch_size=BATCH_SIZE,
        shuffle=True,
        epochs=EPOCHS
    )

    return data, model


if __name__ == "__main__":
    queries, train, test, msk = load_data()

    tokenizer = FullTokenizer(vocab_file=f"{BERT_LOCATION}/vocab.txt")

    UNIQUE_DOMAINS = queries.Domain.unique().tolist()

    data, model = build_model()

    evaluate(data, model)

    manually_test(model)

    save(model)