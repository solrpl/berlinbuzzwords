package com.bb.solr.parser;

import com.bb.solr.parser.classifier.BBuzzClassifier;
import com.bb.solr.parser.classifier.BBuzzTokenizer;
import org.apache.lucene.index.Term;
import org.apache.lucene.search.*;
import org.apache.solr.common.params.SolrParams;
import org.apache.solr.request.SolrQueryRequest;
import org.apache.solr.search.ExtendedDismaxQParser;
import org.apache.solr.search.QParser;
import org.apache.solr.search.SyntaxError;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.tensorflow.SavedModelBundle;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.lang.invoke.MethodHandles;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class BBuzzQueryParser extends QParser {
  private static final Logger log = LoggerFactory.getLogger(MethodHandles.lookup().lookupClass());
  private BBuzzClassifier classifier;

  public BBuzzQueryParser(String qstr, SolrParams localParams, SolrParams params, SolrQueryRequest req) throws IOException {
    super(qstr, localParams, params, req);
    setupClassifier(params);
  }
  @Override
  public Query parse() throws SyntaxError {
    String classificationResult = this.classifier.classify(qstr);
    log.info("Classification result: " + classificationResult);

    // TODO: parse the query
    BooleanQuery.Builder builder = new BooleanQuery.Builder();
    builder.add(new TermQuery(new Term("name", this.qstr)), BooleanClause.Occur.SHOULD);
    if (!classificationResult.isEmpty()) {
      builder.add(new TermQuery(new Term("interest", classificationResult)), BooleanClause.Occur.SHOULD);
    }

    return builder.build();
  }

  private void setupClassifier(SolrParams params) throws IOException {
    List<String> data = loadClasses(params);

    SavedModelBundle model = SavedModelBundle.load(params.get("savedModelDirectory"), "serve");
    BBuzzTokenizer tokenizer = new BBuzzTokenizer(params.get("vocabularyFile"), true);
    this.classifier = new BBuzzClassifier(tokenizer, model, data);
  }

  private List<String> loadClasses(SolrParams params) throws IOException {
    List<String> lines = new ArrayList<>();
    BufferedReader reader = null;

    try {
      reader = new BufferedReader(new FileReader(params.get("classesFile")));
      String line;
      while ((line = reader.readLine()) != null) {
        lines.add(line);
      }
    } finally {
      if (reader != null) {
        try {
          reader.close();
        } catch (Exception ex) {
          ex.printStackTrace();
        }
      }
    }

    return lines;
  }
}
