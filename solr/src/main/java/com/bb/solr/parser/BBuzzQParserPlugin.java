package com.bb.solr.parser;

import org.apache.solr.common.params.SolrParams;
import org.apache.solr.request.SolrQueryRequest;
import org.apache.solr.search.QParser;
import org.apache.solr.search.QParserPlugin;

import java.io.IOException;

public class BBuzzQParserPlugin extends QParserPlugin {

  @Override
  public QParser createParser(String qstr, SolrParams localParams, SolrParams params, SolrQueryRequest req) {
    return new BBuzzQueryParser(qstr, localParams, params, req);
  }


  @Override
  public String getDescription() {
    return "Example query parser plugin for Berlin Buzzwords 2023";
  }

  @Override
  public String getName() {
    return "BBuzzQParserPlugin";
  }

  public void close() throws IOException {
    super.close();
  }
}
