You're a helpful assistant and you'll answer the following questions based on the information from the following blog post.


#####

If you want to get started with Vespa, check out our [getting started guides](https://docs.vespa.ai/en/getting-started.html). They are based on the [sample apps](https://github.com/vespa-engine/sample-apps), which provide good inspiration for your own use-cases.

But what if you already have some data that you want to write to Vespa?

This is where Logstash comes in. Its [Output plugin for Vespa](https://github.com/vespa-engine/vespa/tree/master/integration/logstash-plugins/logstash-output-vespa) now has a `detect_schema` mode that can generate a Vespa [application package](https://docs.vespa.ai/en/application-packages.html) from your data. The application package contains all the configuration required for Vespa to run: from the number of nodes and machine learning models to the schema.

In this tutorial, we'll go through the fastest way to get your data into Vespa, whether you're running Vespa locally (e.g., with Docker/Podman/etc) or using [Vespa Cloud](https://cloud.vespa.ai). Either way, the high-level steps are the same:

1. Download Logstash.
2. Install the Vespa Output plugin.
3. Configure Logstash to use the `detect_schema` mode.
4. Upload the generated application package to Vespa.
5. Disable `detect_schema` and re-run Logstash to write your data.

Let's get into the specifics.

# Logstash to local Vespa

The easiest way to get started is to download a zip/tgz archive from the [Logstash download page](https://www.elastic.co/downloads/logstash). You can also install Logstash using your package manager or run it as a container.

Once it's unpacked, install the Vespa Output plugin by running:

```bash
bin/logstash-plugin install logstash-output-vespa_feed
```

The config file will depend on your data. Have a look at this [5-recipe blog post](https://blog.vespa.ai/logstash-vespa-tutorials/) for some inspiration. For now, let's just read JSON documents from standard input, as an example.

```ruby
# read JSON documents from standard input
input {
    stdin {
        codec => json
    }
}

# remove fields that are not part of our JSON documents
filter {
    mutate {
        remove_field => ["@timestamp", "@version", "event", "host", "log", "message"]
    }
}

output {
    # uncomment to print to stdout, for debugging
    # stdout {
    #     codec => rubydebug
    # }

    vespa_feed {
        # this will generate a Vespa application package, instead of feeding documents
        detect_schema => true
        # make Logstash deploy the application package to Vespa as well
        deploy_package => true
    }
}
```

Now, assuming Vespa is running locally with something like:
```bash
podman run --detach --name vespa-container --hostname vespa-container \  
  --publish 8080:8080 --publish 19071:19071 \  
  vespaengine/vespa
```

You can run Logstash and send a sample document to it:
```bash
echo '{"id": "1", "title": "Hello, world!"}' | bin/logstash -f config.conf
```

This will generate a Vespa application package and deploy it to your local container. At this point, you can disable `detect_schema` and re-run Logstash in exactly the same way to write your data to Vespa.

```bash
echo '{"id": "1", "title": "Hello, world!"}' | bin/logstash -f config.conf
```

Now you're ready to profit (i.e., [query](https://docs.vespa.ai/en/query-language.html)):
```bash
curl -XPOST -H "Content-Type: application/json" -d\  
  '{  "yql": "select * from sources * where true"}'\  
   'http://localhost:8080/search/' | jq .
```

Once you've satisfied the initial thirst, you can go back to the deployed [application package](https://docs.vespa.ai/en/application-packages.html) and iterate on it. The [schema documentation](https://docs.vespa.ai/en/schemas.html) and our [IDE plugins](https://docs.vespa.ai/en/ide-support) should help you along the way.

To deploy a new iteration of the application package, you'll need the [Vespa CLI](https://docs.vespa.ai/en/vespa-cli.html). With it, you can do:
```bash
# The --wait flag shows the deployment progress. Otherwise, you'll have to look in the logs.
vespa deploy --wait 900
```

Logstash prints the path to the generated application package when it deploys it. If you lost that output, Vespa CLI to the rescue:
```bash
vespa fetch /download/path
```

Speaking of the Vespa CLI, you'll need it for Vespa Cloud as well.

# Logstash to Vespa Cloud

With a [Vespa Cloud](https://cloud.vespa.ai) account created, you'll need to create [a tenant and an application](https://docs.vespa.ai/en/cloud/tenant-apps-instances.html?mode=cloud). Then, in your Logstash config, under the `output` section, add those details:
```ruby
# the `input` and `filter` sections are the same as for local Vespa
output {
    vespa_feed {
        # Vespa Cloud details
        vespa_cloud_tenant => "your-tenant"
        vespa_cloud_application => "your-application"

        ### same options as for local Vespa

        # this will generate a Vespa application package, instead of feeding documents
        detect_schema => true
        # make Logstash deploy the application package to Vespa as well
        deploy_package => true
    }
}
```

When you run Logstash (with the same `bin/logstash -f config.conf` command as before), there are two differences. First is that Logstash will, by default, generate mTLS certificates and copy them to `.vespa` under your home directory. You can do this manually, too, by running `vespa auth cert`.

Secondly, the application package won't be automatically deployed. Instead, you'll see four commands to copy-paste:
1. Point Vespa CLI to Vespa Cloud: `vespa config set target cloud`
2. Point it to your tenant and application: `vespa config set application YOUR_TENANT.YOUR_APPLICATION.default`. Where "default" is the default [instance name](https://docs.vespa.ai/en/cloud/tenant-apps-instances.html?mode=cloud) that you can change when you create the application. Adjust `vespa_cloud_instance` in the Logstash config if that's the case.
3. Authenticate your Vespa CLI to your Vespa Cloud account: `vespa auth login`
4. Deploy the application package: `vespa deploy --wait 900`

Once you've deployed the application package, you can disable `detect_schema` and re-run Logstash in exactly the same way as for local Vespa. Logstash will automatically set the mTLS certificates to those of the generated application package. If you need to change them, modify the `client_cert` and `client_key` options in the Vespa output of your Logstash config. Check out the full list of options in the [Logstash Output plugin for Vespa README](https://github.com/vespa-engine/vespa/tree/master/integration/logstash-plugins/logstash-output-vespa).

Happy hacking! Oh, and feel free to reach out on [LinkedIn](https://www.linkedin.com/groups/14536083/), [X](https://x.com/vespaengine) or [Slack](https://slack.vespa.ai/) if you have any questions!
