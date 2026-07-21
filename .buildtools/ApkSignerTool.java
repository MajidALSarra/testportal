import com.android.apksig.ApkSigner;

import java.io.File;
import java.io.FileInputStream;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Minimal APK signer (v1 + v2) built on Google's apksig library. */
public class ApkSignerTool {
    public static void main(String[] args) throws Exception {
        String ksPath = args[0];
        String storePass = args[1];
        String alias = args[2];
        int minSdk = Integer.parseInt(args[3]);
        File in = new File(args[4]);
        File out = new File(args[5]);

        KeyStore ks = KeyStore.getInstance("PKCS12");
        FileInputStream fis = new FileInputStream(ksPath);
        ks.load(fis, storePass.toCharArray());
        fis.close();

        PrivateKey key = (PrivateKey) ks.getKey(alias, storePass.toCharArray());
        Certificate[] chain = ks.getCertificateChain(alias);
        List<X509Certificate> certs = new ArrayList<X509Certificate>();
        for (int i = 0; i < chain.length; i++) {
            certs.add((X509Certificate) chain[i]);
        }

        ApkSigner.SignerConfig signer =
                new ApkSigner.SignerConfig.Builder("CERT", key, certs).build();

        ApkSigner apkSigner = new ApkSigner.Builder(Collections.singletonList(signer))
                .setInputApk(in)
                .setOutputApk(out)
                .setMinSdkVersion(minSdk)
                .setV1SigningEnabled(false)
                .setV2SigningEnabled(true)
                .build();
        apkSigner.sign();
        System.out.println("Signed -> " + out.getAbsolutePath());
    }
}
