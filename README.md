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

#### Files Structure

In the `2026` directory you can find a few files and directories:

- `recipes` - some recipes for the demo
- `vespa_app` - the Vespa application used for the demo
- `demo.nr` - Navigator file for used demo
- `requirements.txt` - Python requirements file

And some used to prepare the talk, including:

- `schemas` - old Vespa schemas used for experiments
- `scripts` - scripts used for experiments 
- `experiments` - Navigator recipes for experiments

#### Demo Flow

To be able to use the `demo.nr` open it in the Navigator and adjust the following properties in the `0. Config & shared helpers` section:

- `VESPA_CONFIG_URL` - Vespa configuration URL, defaults to `http://localhost:19071`
- `VESPA_FEED_URL` - Vespa feed URL, defaults to `http://localhost:8080`
- `NAMESPACE` - Vespa namespace, defaults to `movies`
- `VESPA_APP_DIR` - Vespa application directory, defaults to `./vespa_app`
- `DATA_DIR` - Directory with MovieLens data, defaults to `./ml-25m`
- `TMDB_API_KEY` - [TMDB](https://www.themoviedb.org) API key, needs to be set if you want to see parts of the flow - steps 6 to 9.