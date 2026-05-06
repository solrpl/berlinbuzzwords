# Berlin Buzzwords Conference Materials

## 2023

The code is a PoC of how you can use Tensorflow in Solr query parser. It includes:

- `/2023/config` - the configuration files for Solr
- `/2023/solr` - the final PoC code that extends Solr
- `/2023/tf-java-poc` - the work in progress code for loading and working with the created model
- `/2023/tf-python-poc` - the code for creating the model used for PoC
- `/2023demo` - the script for the demo during the talk

The video of the talk is available on [YouTube](https://www.youtube.com/watch?v=VUdeeXgDfk8). 

## 2025 

The video of the talk is available on [YouTube](https://www.youtube.com/watch?v=pg_oPbYXTPU).

## 2026 

The code in the repository is the code used to prepare the data for the Berlin Buzzwords 2026 talk.

### MovieLens ml-25m Vespa Indexer

Indexes the [MovieLens ml-25m](https://grouplens.org/datasets/movielens/25m/) dataset into a locally running Vespa instance. Creates three document types — `movie`, `rating`, and `tag` — and deploys the full Vespa application package automatically.

### Prerequisites

- Python 3.10+
- Vespa running in Docker with ports **19071** (config server) and **8080** (feed/query) exposed
- The `ml-25m/` dataset directory (containing `movies.csv`, `ratings.csv`, `tags.csv`, `links.csv`)

#### Start Vespa in Docker

```bash
docker run --detach \
  --name vespa \
  --hostname vespa-container \
  --publish 8080:8080 \
  --publish 19071:19071 \
  vespaengine/vespa
```

#### Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

#### Run

```bash
DATA_DIR=./ml-25m python3 batch.py
```

The script will:
1. Generate the Vespa application package (schemas + `services.xml`)
2. Deploy it to the config server
3. Feed all movies (~62K docs)
4. Feed all ratings (~25M docs)
5. Feed all tags (~1M docs)
6. Print a final summary

> **Note:** It can take quite some time to index the data.

#### Verfication

You can run the `verify.py` during indexing to check its status:

```bash
python3 verify.py
```