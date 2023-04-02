package com.bb.solr.parser;

import org.apache.lucene.index.Term;
import org.apache.lucene.search.BooleanClause;
import org.apache.lucene.search.BooleanQuery;
import org.apache.lucene.search.Query;
import org.apache.lucene.search.TermQuery;
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
    // TODO: get synonyms and just run multiple queries
    Query query = new BooleanQuery.Builder().
        add(new TermQuery(new Term("name", this.qstr)), BooleanClause.Occur.SHOULD).
        add(new TermQuery(new Term("name", this.qstr)), BooleanClause.Occur.SHOULD).
        build();

    return query;
  }
}
