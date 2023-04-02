package com.bb.solr.parser;

import org.apache.lucene.search.Query;
import org.apache.solr.common.params.SolrParams;
import org.apache.solr.request.SolrQueryRequest;
import org.apache.solr.search.QParser;
import org.apache.solr.search.SyntaxError;

public class BBuzzQueryParser extends QParser {
  
  public BBuzzQueryParser(String qstr, SolrParams localParams, SolrParams params, SolrQueryRequest req) {
    super(qstr, localParams, params, req);
  }


  @Override
  public Query parse() throws SyntaxError {
    return null;
  }
}
