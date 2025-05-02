package org.example;

import org.tensorflow.SavedModelBundle;

import java.util.Arrays;
import java.util.List;

public class Main {

    public static void main(String[] args) throws Exception {
        List<String> data = Arrays.asList("Techniques", "Hackathons", "Misc", "Tools", "Career", "Resources", "Other");

        SavedModelBundle model = SavedModelBundle.load("/tmp/bbuzz/saved_model", "serve");
        BBuzzTokenizer tokenizer = new BBuzzTokenizer("/tmp/bbuzz/bert_tiny/vocab.txt", true);
        BBuzzClassifier classifier = new BBuzzClassifier(tokenizer, model, data);

        String result = classifier.classify("There are awesome tools that we can use to support the use case");
        System.out.println("Classification result: " + result);

        model.close();
    }
}
