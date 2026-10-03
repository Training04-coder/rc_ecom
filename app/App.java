import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;
import java.io.FileWriter;
import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Mini site web Java (zero dependance, zero build) pour lab AWS Security Agent.
 * Lancement : java App.java   (Java 11+ "source launcher")
 * Ecoute sur 127.0.0.1:8080 ; Caddy fait le HTTPS devant.
 * DEMO_VULN=true active volontairement une XSS reflechie sur /search (lab uniquement).
 * Logs : une ligne JSON par evenement sur stdout + LOG_FILE (defaut /var/log/bricoshop/app.log).
 */
public class App {

    static final boolean DEMO_VULN = "true".equalsIgnoreCase(System.getenv("DEMO_VULN"));
    static final String LOG_FILE = System.getenv().getOrDefault("LOG_FILE", "/var/log/bricoshop/app.log");
    static PrintWriter logFile;

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));
        String bind = System.getenv().getOrDefault("BIND", "127.0.0.1");
        try { logFile = new PrintWriter(new FileWriter(LOG_FILE, StandardCharsets.UTF_8, true), true); }
        catch (IOException e) { System.err.println("Fichier de log indisponible (" + LOG_FILE + "), stdout uniquement"); }
        HttpServer server = HttpServer.create(new InetSocketAddress(bind, port), 0);

        route(server, "/", ex -> {
            if (!ex.getRequestURI().getPath().equals("/")) { send(ex, 404, "text/plain", "Not found"); return; }
            send(ex, 200, "text/html", page("Accueil",
                "<p>Mini site Java deploye sur AWS avec Terraform.</p>"
              + "<ul><li><a href=\"/hello?name=Formation\">/hello?name=...</a></li>"
              + "<li><a href=\"/search?q=test\">/search?q=...</a></li>"
              + "<li><a href=\"/health\">/health</a></li></ul>"));
        });

        route(server, "/hello", ex -> {
            String name = query(ex).getOrDefault("name", "inconnu");
            send(ex, 200, "text/html", page("Hello", "<p>Bonjour " + escape(name) + " !</p>"));
        });

        route(server, "/search", ex -> {
            String q = query(ex).getOrDefault("q", "");
            // Volontaire si DEMO_VULN=true : sortie non echappee => XSS reflechie
            String shown = DEMO_VULN ? q : escape(q);
            send(ex, 200, "text/html", page("Recherche",
                "<form action=\"/search\"><input name=\"q\"><button>OK</button></form>"
              + "<p>Resultats pour : " + shown + "</p><p>Aucun resultat.</p>"));
        });

        route(server, "/health", ex ->
            send(ex, 200, "application/json", "{\"status\":\"UP\",\"time\":\"" + Instant.now() + "\"}"));

        server.start();
        log(null, "INFO", "app_startup", "bind", bind, "port", port, "demoVuln", DEMO_VULN, "logFile", logFile != null);
    }

    /** Enregistre une route : requestId, session, gestion d'erreur et log http_request. */
    static void route(HttpServer server, String path, HttpHandler h) {
        server.createContext(path, ex -> {
            long t0 = System.nanoTime();
            ex.setAttribute("requestId", UUID.randomUUID().toString());
            String cookie = ex.getRequestHeaders().getFirst("Cookie");
            String sid = cookie == null ? null : cookie.replaceAll(".*\\bSID=([0-9a-f-]{36}).*", "$1");
            if (sid == null || !sid.matches("[0-9a-f-]{36}")) {
                sid = UUID.randomUUID().toString();
                ex.getResponseHeaders().add("Set-Cookie", "SID=" + sid + "; Path=/; HttpOnly; SameSite=Lax");
            }
            ex.setAttribute("sessionId", sid);
            try {
                h.handle(ex);
            } catch (Exception e) {
                StringWriter sw = new StringWriter();
                e.printStackTrace(new PrintWriter(sw));
                log(ex, "ERROR", "app_error", "errorType", e.getClass().getSimpleName(), "reason", String.valueOf(e.getMessage()), "stackTrace", sw.toString());
                try { send(ex, 500, "text/plain", "Erreur interne"); } catch (Exception ignored) { }
            } finally {
                int status = ex.getResponseCode();
                log(ex, status >= 500 ? "ERROR" : status >= 400 ? "WARN" : "INFO", "http_request",
                    "status", status, "durationMs", (System.nanoTime() - t0) / 1_000_000);
            }
        });
    }

    /** Une ligne JSON par evenement (stdout + fichier). ex peut etre null (evenement hors requete). kv = cle, valeur, ... */
    static synchronized void log(HttpExchange ex, String level, String event, Object... kv) {
        StringBuilder sb = new StringBuilder("{\"timestamp\":\"" + Instant.now() + "\",\"level\":\"" + level + "\",\"event\":\"" + event + "\"");
        if (ex != null) {
            String xff = ex.getRequestHeaders().getFirst("X-Forwarded-For");
            Object userId = ex.getAttribute("userId");
            kv = concat(new Object[] {
                "requestId", ex.getAttribute("requestId"), "sessionId", ex.getAttribute("sessionId"),
                "userId", userId == null ? "anonymous" : userId,
                "ip", xff != null ? xff.split(",")[0].trim() : ex.getRemoteAddress().getAddress().getHostAddress(),
                "userAgent", ex.getRequestHeaders().getFirst("User-Agent"),
                "method", ex.getRequestMethod(), "path", ex.getRequestURI().getPath() }, kv);
        }
        for (int i = 0; i + 1 < kv.length; i += 2) {
            Object v = kv[i + 1];
            sb.append(",\"").append(kv[i]).append("\":");
            if (v == null) sb.append("null");
            else if (v instanceof Number || v instanceof Boolean) sb.append(v);
            else sb.append('"').append(json(v.toString())).append('"');
        }
        String line = sb.append('}').toString();
        System.out.println(line);
        if (logFile != null) logFile.println(line);
    }

    static Object[] concat(Object[] a, Object[] b) {
        Object[] r = java.util.Arrays.copyOf(a, a.length + b.length);
        System.arraycopy(b, 0, r, a.length, b.length);
        return r;
    }

    static String json(String s) {
        StringBuilder sb = new StringBuilder();
        for (char c : s.toCharArray()) {
            if (c == '"' || c == '\\') sb.append('\\').append(c);
            else if (c < 0x20) sb.append(String.format("\\u%04x", (int) c));
            else sb.append(c);
        }
        return sb.toString();
    }

    static Map<String, String> query(HttpExchange ex) {
        Map<String, String> m = new HashMap<>();
        String raw = ex.getRequestURI().getRawQuery();
        if (raw == null) return m;
        for (String kv : raw.split("&")) {
            String[] p = kv.split("=", 2);
            m.put(URLDecoder.decode(p[0], StandardCharsets.UTF_8),
                  p.length > 1 ? URLDecoder.decode(p[1], StandardCharsets.UTF_8) : "");
        }
        return m;
    }

    static String escape(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;").replace("'", "&#x27;");
    }

    static String page(String title, String body) {
        return "<!doctype html><html lang=\"fr\"><head><meta charset=\"utf-8\"><title>" + title
             + "</title></head><body style=\"font-family:sans-serif;max-width:640px;margin:40px auto\">"
             + "<h1>" + title + "</h1>" + body + "</body></html>";
    }

    static void send(HttpExchange ex, int code, String type, String body) throws IOException {
        byte[] b = body.getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().set("Content-Type", type + "; charset=utf-8");
        ex.sendResponseHeaders(code, b.length);
        try (OutputStream os = ex.getResponseBody()) { os.write(b); }
    }
}
