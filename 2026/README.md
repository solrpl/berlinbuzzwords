[Follow-up info for our Berlin Buzzwords 2026 session](https://2026.berlinbuzzwords.de/session/circular-dependency-fixes-when-bootstrapping-a-golden-set/): "Circular Dependency Fixes When Bootstrapping a Golden Set".

![qr-code for the session](qr-code.png)

# More info

The people:
- [Rafał Kuć](https://www.linkedin.com/in/rafalkuc/) ([Authologic](https://authologic.com))
- [Radu Gheorghe](https://www.linkedin.com/in/ragheorghe/) ([Vespa](https://vespa.ai))

The tools:
- [Vespa](https://vespa.ai/). **NOTE**: [the fist live Vespa conference](https://vespaai.live/) will be in September 2026 in London. [Discounted tickets are available here](https://buytickets.at/vespaaias/2158210?a=VespaFriends20#ticket_selection)
- [Search Navigator](https://solr.search-navigator.org/)
- [dataset-generator from the RRE project](https://github.com/SeaseLtd/rated-ranking-evaluator/tree/dataset-generator/rre-tools/docs/dataset_generator)

# Demo Flow

This is a sample flow that:
1. Indexes the MovieLens ml-25m dataset into a locally running Vespa instance
2. Enriches the data with metadata from TMDB
3. Generates judgements for the data using LLM-as-a-judge (via [dataset-generator from the RRE project](https://github.com/SeaseLtd/rated-ranking-evaluator/tree/dataset-generator/rre-tools/docs/dataset_generator))
4. Explores the judgement data

## Prerequisites

You'll need:
* A Conda environment with Python 3.10+
* Search Navigator
* Vespa running in Docker/Podman/etc. with ports **19071** (config server) and **8080** (feed/query) exposed
* The MovieLens ml-25m dataset in `ml-25m/`
* A TMDB API key
* [RRE repository](https://github.com/SeaseLtd/rated-ranking-evaluator) cloned

**NOTE**: If [PR 266](https://github.com/SeaseLtd/rated-ranking-evaluator/pull/266) isn't merged yet, you need to clone the [PR branch](https://github.com/radu-gheorghe/rated-ranking-evaluator/tree/dataset-generator-llm-batching) instead. 

### Set up a Python 3.10+ Conda environment

Download and install Anaconda/Miniconda. For example, from [https://www.anaconda.com/download/success#miniconda](https://www.anaconda.com/download/success#miniconda).

Then prepare it for the Navigator:

```bash
conda create -n Python-for-Navigator
conda activate Python-for-Navigator
conda install python=3.10
conda install -c conda-forge jupyterlab=4.3.5
pip install -r requirements.txt
```

### Set up Search Navigator

Download and install Search Navigator from [here](https://solr.search-navigator.org/download)

Note: the packages aren't currently signed. You might need to override the OS complaint about it. On recent OSX versions, something like this will do:

```bash
# NOTE: replace with your path and version
xattr -d com.apple.quarantine ~/Downloads/Navigator_v0.0.37_mac-installer.pkg
```

### Run Vespa

To run Vespa in Docker/Podman/etc. with ports **19071** (config server) and **8080** (feed/query) exposed:


```bash
docker run --detach \
  --name vespa \
  --hostname vespa-container \
  --publish 8080:8080 \
  --publish 19071:19071 \
  vespaengine/vespa
```

### Download MovieLens

Download [MovieLens ml-25m](https://grouplens.org/datasets/movielens/25m/) (containing `movies.csv`, `ratings.csv`, `tags.csv`, `links.csv`) and put it in `ml-25m/`.

### Set up TMDB API key

Set the `TMDB_API_KEY` environment variable to your TMDB API key. You can get one from [here](https://www.themoviedb.org/settings/api) once you have a themoviedb.org account.

### Clone RRE repository

Clone the [RRE repository](https://github.com/SeaseLtd/rated-ranking-evaluator).

## Directory Structure

- `recipes` - Navigator recipes for the demo. Some more experiments are in the `experiments` subdirectory.
- `vespa_app` - the Vespa application used for the demo
- `scripts` - scripts used for experiments 
- `dataset-generator` - the dataset-generator configuration. Sample judgements are in the `output` subdirectory.


## Demo Flow

To be able to use the `demo.nr` open it in the Navigator and adjust the following properties in the `0. Config & shared helpers` section:

- `VESPA_CONFIG_URL` - Vespa configuration URL, defaults to `http://localhost:19071`
- `VESPA_FEED_URL` - Vespa feed URL, defaults to `http://localhost:8080`
- `NAMESPACE` - Vespa namespace, defaults to `movies`
- `VESPA_APP_DIR` - Vespa application directory, defaults to `./vespa_app`
- `DATA_DIR` - Directory with MovieLens data, defaults to `./ml-25m`
- `TMDB_API_KEY` - [TMDB](https://www.themoviedb.org) API key, needs to be set if you want to see parts of the flow - steps 6 to 9.

