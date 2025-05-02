package com.bb.solr.parser.classifier;

import ai.djl.modality.nlp.DefaultVocabulary;
import ai.djl.modality.nlp.Vocabulary;
import ai.djl.modality.nlp.bert.BertFullTokenizer;
import org.tensorflow.ndarray.IntNdArray;
import org.tensorflow.ndarray.NdArrays;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

public class BBuzzTokenizer {
  private BertFullTokenizer tokenizer;
  private Vocabulary vocabulary;
  private int minFrequency = 1;
  private int maxVectorLength = 32;

  public BBuzzTokenizer(String path, boolean lowercase) throws IOException {
    Path vocabularyFile = Paths.get(path);
    this.vocabulary = DefaultVocabulary.builder()
        .optMinFrequency(minFrequency)
        .optUnknownToken("[UNK]")
        .addFromTextFile(vocabularyFile)
        .build();
    this.tokenizer = new BertFullTokenizer(this.vocabulary, lowercase);
  }

  public IntNdArray toNdArray(String sentence) {
    List<String> tokens = this.tokenizer.tokenize(sentence);
    List<Long> tokenIds = new ArrayList<>();

    for (String token : tokens) {
      tokenIds.add(vocabulary.getIndex(token));
    }

    // trim the length of the vector to the maximum size that we have in the model
    tokenIds = tokenIds.size() > maxVectorLength ? tokenIds.subList(0, maxVectorLength) : tokenIds;

    // the vector can be smaller than the max length, in such case pad with 0
    if (tokenIds.size() < maxVectorLength) {
      while (tokenIds.size() < maxVectorLength) {
        tokenIds.add(0l);
      }
    }

    int[] tokenIdsArray = tokenIds.stream().mapToInt(i -> i.intValue()).toArray();
    return NdArrays.vectorOf(tokenIdsArray);
  }
}
