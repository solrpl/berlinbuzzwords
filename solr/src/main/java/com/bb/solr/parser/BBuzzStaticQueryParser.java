package com.bb.solr.parser;

import com.bb.solr.parser.classifier.BBuzzClassifier;
import com.bb.solr.parser.classifier.BBuzzTokenizer;
import org.apache.lucene.index.Term;
import org.apache.lucene.search.BooleanClause;
import org.apache.lucene.search.BooleanQuery;
import org.apache.lucene.search.Query;
import org.apache.lucene.search.TermQuery;
import org.apache.solr.common.params.SolrParams;
import org.apache.solr.request.SolrQueryRequest;
import org.apache.solr.search.LuceneQParser;
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
import java.util.List;

public class BBuzzStaticQueryParser extends BBuzzQueryParser {
  private static final Logger log = LoggerFactory.getLogger(MethodHandles.lookup().lookupClass());
  private static BBuzzClassifier CLASSIFIER;
  private LuceneQParser luceneQueryParser;

  public BBuzzStaticQueryParser(String qstr, SolrParams localParams, SolrParams params, SolrQueryRequest req) throws
      IOException {
    super(qstr, localParams, params, req);
    this.luceneQueryParser = new LuceneQParser(qstr, localParams, params, req);

    // This is just an example - shouldn't be done
    if (CLASSIFIER == null) {
      CLASSIFIER = setupClassifier(params);
    }
  }

  @Override
  protected void appendClassificationResults(BooleanQuery.Builder builder) {
    if (CLASSIFIER == null) {
      throw new RuntimeException("classifier is not initialized");
    }

    String classificationResult = CLASSIFIER.classify(qstr);
    if (!classificationResult.isEmpty()) {
      builder.add(new TermQuery(new Term("interest", classificationResult)), BooleanClause.Occur.SHOULD);
    }
  }
}
