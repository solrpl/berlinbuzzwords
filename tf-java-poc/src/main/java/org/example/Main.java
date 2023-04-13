package org.example;

import org.tensorflow.Result;
import org.tensorflow.SavedModelBundle;
import org.tensorflow.Tensor;
import org.tensorflow.types.TFloat32;
import org.tensorflow.types.TString;
public class Main {

    public static void main(String[] args) {
        SavedModelBundle model = SavedModelBundle.load("/Users/radu/Documents/bbuzz/imdb_bert",
                "serve");

        String testString = "this is such an amazing movie!";

        Tensor input = TString.scalarOf(testString);

        Result rawResult = model.session()
                .runner()
                .feed("input_name", input)
                .fetch("output_name")
                .run();

        TFloat32 result = (TFloat32) rawResult.get(0); //we have one string to evaluate, so it should be the first

        System.out.println("prediction = " + result.getFloat());


    }


}