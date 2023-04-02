package com.bb.solr.parser;

import org.apache.solr.common.params.SolrParams;
import org.apache.solr.request.SolrQueryRequest;
import org.apache.solr.search.QParser;
import org.apache.solr.search.QParserPlugin;

public class BBuzzQParserPlugin extends QParserPlugin {

  @Override
  public QParser createParser(String qstr, SolrParams localParams, SolrParams params, SolrQueryRequest req) {
    return new BBuzzQueryParser(qstr, localParams, params, req);
  }


  @Override
  public String getDescription() {
    return "Example query parser plugin for Berlin Buzzowords 2023";
  }

  @Override
  public String getName() {
    return "BBuzzQParserPlugin";
  }
}