package com.bb.solr.parser;

import org.apache.http.HttpStatus;
import org.apache.http.NameValuePair;
import org.apache.http.client.entity.UrlEncodedFormEntity;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.message.BasicNameValuePair;
import org.apache.lucene.index.Term;
import org.apache.lucene.search.BooleanClause;
import org.apache.lucene.search.BooleanQuery;
import org.apache.lucene.search.Query;
import org.apache.lucene.search.TermQuery;
import org.apache.solr.common.params.SolrParams;
import org.apache.solr.request.SolrQueryRequest;
import org.apache.solr.search.QParser;
import org.apache.solr.search.SyntaxError;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

public class BBuzzQueryParserHTTP extends QParser {
  private String apiHost = "localhost:3000";

  public BBuzzQueryParserHTTP(String qstr, SolrParams localParams, SolrParams params, SolrQueryRequest req) {
    super(qstr, localParams, params, req);
    this.setConfiguration(params);
  }

  @Override
  public Query parse() throws SyntaxError {
    // run the HTTP request to the API endpoint
    try {
      HttpPost post = new HttpPost(this.apiHost);
      final List<NameValuePair> params = new ArrayList<NameValuePair>();
      params.add(new BasicNameValuePair("phrase", this.qstr));
      post.setEntity(new UrlEncodedFormEntity(params));

      CloseableHttpClient client = HttpClients.createDefault();
      CloseableHttpResponse response = client.execute(post);
      final int statusCode = response.getStatusLine().getStatusCode();
      if (statusCode != HttpStatus.SC_OK) {
        throw new Exception("response code not equal 200");
      }

      // build new query
      BooleanQuery.Builder queryBuilder = new BooleanQuery.Builder();

      // TODO: in the response we get a list of strings
      InputStream is = response.getEntity().getContent();
      BufferedReader reader = new BufferedReader(new InputStreamReader(is));
      String line;
      while ((line = reader.readLine()) != null) {
        queryBuilder.add(new TermQuery(new Term("name", line)), BooleanClause.Occur.SHOULD);
      }

      return queryBuilder.build();

    } catch (Exception ex) {
      throw new SyntaxError("error while running request", ex);
    }
  }

  protected void setConfiguration(SolrParams params) {
    String apiHost = params.get("apiHost");
    int apiPort = params.getInt("apiPort", 3000);
    this.apiHost = apiHost + ":" + apiPort;
  }
}
