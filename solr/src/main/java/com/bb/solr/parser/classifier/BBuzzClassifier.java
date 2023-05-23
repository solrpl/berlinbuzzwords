package com.bb.solr.parser.classifier;

import org.tensorflow.SavedModelBundle;
import org.tensorflow.Tensor;
import org.tensorflow.ndarray.FloatNdArray;
import org.tensorflow.ndarray.IntNdArray;
import org.tensorflow.ndarray.NdArrays;
import org.tensorflow.ndarray.Shape;
import org.tensorflow.types.TFloat32;
import org.tensorflow.types.TInt32;

import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

public class BBuzzClassifier {
  private BBuzzTokenizer tokenizer;
  private SavedModelBundle model;
  private List<String> data;
  private int maxVectorLength = 32;

  public BBuzzClassifier(BBuzzTokenizer tokenizer, SavedModelBundle model, List<String> data) {
    this.tokenizer = tokenizer;
    this.model = model;
    this.data = data;
  }

  public String classify(String text) {
    IntNdArray inputArray = NdArrays.ofInts(Shape.of(this.maxVectorLength));
    inputArray.set(tokenizer.toNdArray(text));

    // create input
    Tensor inputTensor = TInt32.tensorOf(inputArray);
    Map<String, Tensor> inputDictionary = new HashMap<>();
    inputDictionary.put("input_ids", inputTensor);

    // get the results using the serving_default
    Map<String, Tensor> resultDictionary = model.function("serving_default").call(inputDictionary);

    // the results should be in the predictions tensor
    TFloat32 result = (TFloat32) resultDictionary.get("predictions");

    // get the best prediction
    int bestPosition = -1;
    if (result.size() > 0) {
      float max = result.scalars().iterator().next().getObject();
      int currentPosition = 0;
      bestPosition = currentPosition;
      Iterator<FloatNdArray> iterator = result.scalars().iterator();
      while (iterator.hasNext()) {
        FloatNdArray ndArray = iterator.next();
        if (ndArray.getObject() > max) {
          max = ndArray.getObject();
          bestPosition = currentPosition;
        }
        currentPosition++;
      }
    }

    // close everything
    inputTensor.close();

    // return results
    if (bestPosition > -1) {
      return data.get(bestPosition);
    }

    return "";
  }
}
