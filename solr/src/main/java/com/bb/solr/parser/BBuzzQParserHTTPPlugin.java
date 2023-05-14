package com.bb.solr.parser;

import org.apache.solr.common.params.SolrParams;
import org.apache.solr.request.SolrQueryRequest;
import org.apache.solr.search.QParser;
import org.apache.solr.search.QParserPlugin;

import java.io.IOException;

public class BBuzzQParserHTTPPlugin extends QParserPlugin {
  @Override
  public QParser createParser(String qstr, SolrParams localParams, SolrParams params, SolrQueryRequest req) {
    return new BBuzzQueryParserHTTP(qstr, localParams, params, req);
  }
  @Override
  public String getDescription() {
    return "Example HTTP query parser plugin for Berlin Buzzwords 2023";
  }

  @Override
  public String getName() {
    return "BBuzzQParserHTTPPlugin";
  }

  public void close() throws IOException {
    super.close();
  }
}
