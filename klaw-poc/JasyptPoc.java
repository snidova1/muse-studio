import org.jasypt.util.text.BasicTextEncryptor;

/**
 * Simulates exactly what Klaw does with stored passwords, using the REAL Jasypt
 * library (org.jasypt:jasypt:1.9.3, the version behind jasypt-spring-boot-starter
 * 4.0.4 used by Klaw core):
 *
 * - DefaultDataService.getUser(): encryptor.setPasswordCharArray(secretKey); encrypt(password)
 *   where secretKey defaults to klaw.jasypt.encryptor.secretkey = "kw2021secretkey"
 * - ExportImportDataService.getUpdatedUserList(): encrypt("WelcomeToKlaw!!") for every user
 * - PasswordService/CommonUtilsService decodePwd(): decrypt(storedPwd) at login
 *
 * Usage: java -cp jasypt-1.9.3.jar:slf4j-api.jar:. JasyptPoc
 * No arguments needed; prints ciphertexts for known plaintexts and round-trips them.
 */
public class JasyptPoc {
  public static void main(String[] args) {
    BasicTextEncryptor enc = new BasicTextEncryptor();
    enc.setPasswordCharArray("kw2021secretkey".toCharArray());

    // 1. quickstart users william/jennifer: default pwd "welcome"
    String cWelcome = enc.encrypt("welcome");
    System.out.println("CIPHERTEXT[welcome] = " + cWelcome);

    // 2. ExportImportDataService default: klaw.export.users.pwd = WelcomeToKlaw!!
    String cWelcomeToKlaw = enc.encrypt("WelcomeToKlaw!!");
    System.out.println("CIPHERTEXT[WelcomeToKlaw!!] = " + cWelcomeToKlaw);

    // 3. stand-in operator-chosen superadmin password
    String cSuper = enc.encrypt("SuperSecret123");
    System.out.println("CIPHERTEXT[SuperSecret123] = " + cSuper);

    // round-trip sanity: decrypt with the same real Jasypt instance
    System.out.println("ROUNDTRIP[welcome] = " + enc.decrypt(cWelcome));
    System.out.println("ROUNDTRIP[WelcomeToKlaw!!] = " + enc.decrypt(cWelcomeToKlaw));
    System.out.println("ROUNDTRIP[SuperSecret123] = " + enc.decrypt(cSuper));

    // decrypt a ciphertext produced by the independent Python implementation (arg 1)
    if (args.length > 0) {
      System.out.println("DECRYPT[python-ciphertext] = " + enc.decrypt(args[0]));
    }
  }
}
