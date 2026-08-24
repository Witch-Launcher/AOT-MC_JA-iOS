public class HelloMain {
    public static void main(String[] args) {
        String marker = System.getenv("AOT_MARKER");
        if (marker == null || marker.isEmpty()) marker = "AOT_HELLO_V1";
        System.out.println(marker);
        System.out.println("GraalVM native-image: " + System.getProperty("java.vm.name"));
        System.out.println("OS: " + System.getProperty("os.name") + " " + System.getProperty("os.arch"));
    }
}
