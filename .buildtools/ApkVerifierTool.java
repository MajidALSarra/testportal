import com.android.apksig.ApkVerifier;

import java.io.File;

/** Prints which signature schemes verify on the finished APK. */
public class ApkVerifierTool {
    public static void main(String[] args) throws Exception {
        ApkVerifier.Result r = new ApkVerifier.Builder(new File(args[0])).build().verify();
        System.out.println("verified        : " + r.isVerified());
        System.out.println("v1 (JAR) scheme : " + r.isVerifiedUsingV1Scheme());
        System.out.println("v2 scheme       : " + r.isVerifiedUsingV2Scheme());
        if (!r.getErrors().isEmpty()) {
            System.out.println("errors: " + r.getErrors());
        }
        if (!r.isVerified()) System.exit(1);
    }
}
