# Demo Script

## Start Solr with packages enabled

```sh
bin/solr start -f -c -Denable.packages=true
```

## Generate Key

```sh
openssl genrsa -out bbuzz_key.pem 512

openssl rsa -in bbuzz_key.pem -pubout -outform DER -out bbuzz_key.der
```

## Add Key to Solr

```sh
bin/solr package add-key bbuzz_key.der
```

## Sign the Library

```sh
openssl dgst -sha1 -sign bbuzz_key.pem plugin/bbuzz-1.0.jar | openssl enc -base64 | sed 's/+/%2B/g' | tr -d \\n | sed
```

## Upload the Library and Verify

```sh
curl --data-binary @plugin/bbuzz-1.0.jar -XPUT  http://localhost:8983/api/cluster/files/bbuzz/1.0/bbuzz-1.0.jar?sig=<SIG>

curl http://localhost:8983/api/node/files/bbuzz/1.0?omitHeader=true

curl  http://localhost:8983/api/cluster/package -H 'Content-type:application/json' -d  '{
 "add": {
    "package" : "bbuzz",
    "version":"1.0",
    "files" :[
      "/bbuzz/1.0/bbuzz-1.0.jar"
    ]
  }
}'

curl http://localhost:8983/api/cluster/package?omitHeader=true
```

## Upload Configuration and Create Collection

```sh
bin/solr zk upconfig -z localhost:9983 -n bbuzz -d plugin/config/

bin/solr create_collection -n bbuzz -c bbuzz -shards 1 -replicationFactor 1
```

## Run Queries

http://localhost:8983/solr/bbuzz/bbuzz?q=how%20do%20I%20become%20a%20data%20scientist&defType=bbuzz&debugQuery=on

http://localhost:8983/solr/bbuzz/bbuzz?q=how%20do%20I%20become%20a%20data%20scientist&defType=bbuzz_static&debugQuery=on
