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
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * BricoShop : mini e-commerce de bricolage (zero dependance, zero build) pour formation CloudWatch.
 * Lancement : java App.java   (Java 11+ "source launcher"), depuis le dossier contenant static/
 * Ecoute sur 127.0.0.1:8080 ; Caddy fait le HTTPS devant.
 * DEMO_VULN=true active volontairement une XSS reflechie sur /search (lab uniquement).
 * Logs : une ligne JSON par evenement sur stdout + LOG_FILE (defaut /var/log/bricoshop/app.log).
 */
public class App {

    static final boolean DEMO_VULN = "true".equalsIgnoreCase(System.getenv("DEMO_VULN"));
    static final String LOG_FILE = System.getenv().getOrDefault("LOG_FILE", "/var/log/bricoshop/app.log");
    static final Path STATIC_DIR = Path.of(System.getenv().getOrDefault("STATIC_DIR", "static")).toAbsolutePath().normalize();
    static final Map<String, String> MIME = Map.of("html", "text/html", "css", "text/css", "js", "application/javascript", "svg", "image/svg+xml");
    static PrintWriter logFile;

    record Product(int id, String name, double price, String description, String category, String image) {
        String toJson() {
            return "{\"id\":" + id + ",\"name\":\"" + json(name) + "\",\"price\":" + price + ",\"description\":\"" + json(description)
                 + "\",\"category\":\"" + json(category) + "\",\"image\":\"" + json(image) + "\"}";
        }
    }

    static final Map<Integer, Product> PRODUCTS = new LinkedHashMap<>();
    static void product(String name, double price, String description, String category, String unsplashId) {
        int id = PRODUCTS.size() + 1;
        PRODUCTS.put(id, new Product(id, name, price, description, category,
            "https://images.unsplash.com/photo-" + unsplashId + "?w=600&h=400&fit=crop&auto=format&q=70"));
    }
    static {
        product("Perceuse-visseuse sans fil 18V", 129.90, "Mandrin 13 mm, 2 vitesses, livrée avec batterie 2 Ah et chargeur.", "Électroportatif", "1572981779307-38b8cabb2407");
        product("Perceuse à percussion compacte", 89.90, "Légère et puissante pour percer bois, métal et béton.", "Électroportatif", "1606676539940-12768ce0e762");
        product("Scie circulaire 1400W", 149.00, "Coupe jusqu'à 55 mm, guide parallèle et lame carbure 24 dents.", "Électroportatif", "1695734964302-262ec797a8d9");
        product("Marteau de charpentier", 19.90, "Tête forgée 500 g, arrache-clou, manche antivibration.", "Outillage à main", "1607870411590-d5e9e06da09a");
        product("Jeu de 12 tournevis", 24.90, "Plats, cruciformes et Torx, embouts magnétiques.", "Outillage à main", "1507126694149-a8685f99aa4f");
        product("Pince coupante diagonale", 16.90, "Acier chrome-vanadium, poignées bi-matière, 180 mm.", "Outillage à main", "1645449781249-27c94448f6f7");
        product("Niveau à bulle 60 cm", 22.50, "Profil aluminium, 3 fioles, précision 0,5 mm/m.", "Mesure", "1567361808976-260065224468");
        product("Mètre ruban 5 m", 9.90, "Ruban acier 25 mm avec blocage et clip ceinture.", "Mesure", "1716698286313-9a2349d41110");
        product("Peinture murale blanche 2,5 L", 34.90, "Mate, lessivable, haut pouvoir couvrant, env. 25 m².", "Peinture", "1673297821205-e0575bbc2ab7");
        product("Rouleau anti-goutte 180 mm", 12.90, "Manchon microfibre pour murs et plafonds, monture renforcée.", "Peinture", "1562259949-e8e7689d7828");
        product("Assortiment vis et écrous 500 pcs", 14.90, "Vis, boulons et écrous zingués dans un coffret à compartiments.", "Quincaillerie", "1710129084868-9ff5127b7e6e");
        product("Panneau mural porte-outils", 39.90, "Panneau perforé 120 × 60 cm avec 20 crochets assortis.", "Quincaillerie", "1602052793312-b99c2a9ee797");
    }

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));
        String bind = System.getenv().getOrDefault("BIND", "127.0.0.1");
        try { logFile = new PrintWriter(new FileWriter(LOG_FILE, StandardCharsets.UTF_8, true), true); }
        catch (IOException e) { System.err.println("Fichier de log indisponible (" + LOG_FILE + "), stdout uniquement"); }
        HttpServer server = HttpServer.create(new InetSocketAddress(bind, port), 0);

        route(server, "/", ex -> {
            if (!ex.getRequestURI().getPath().equals("/")) { send(ex, 404, "text/plain", "Not found"); return; }
            log(ex, "INFO", "page_view", "page", "home");
            sendFile(ex, STATIC_DIR.resolve("index.html"));
        });

        route(server, "/static/", ex -> {
            Path f = STATIC_DIR.resolve(ex.getRequestURI().getPath().substring("/static/".length())).normalize();
            if (!f.startsWith(STATIC_DIR) || !Files.isRegularFile(f)) { send(ex, 404, "text/plain", "Not found"); return; }
            sendFile(ex, f);
        });

        route(server, "/api/products", ex -> {
            String rest = ex.getRequestURI().getPath().substring("/api/products".length());
            if (rest.isEmpty()) {
                send(ex, 200, "application/json", PRODUCTS.values().stream().map(Product::toJson).collect(Collectors.joining(",", "[", "]")));
                return;
            }
            Product p = rest.matches("/\\d{1,9}") ? PRODUCTS.get(Integer.parseInt(rest.substring(1))) : null;
            if (p == null) {
                log(ex, "WARN", "product_view", "productId", rest.substring(Math.min(1, rest.length())),
                    "reason", rest.matches("/\\d{1,9}") ? "product_not_found" : "invalid_product_id");
                send(ex, 404, "application/json", "{\"error\":\"product_not_found\"}");
                return;
            }
            log(ex, "INFO", "product_view", "productId", p.id(), "productName", p.name(), "category", p.category(), "price", p.price());
            send(ex, 200, "application/json", p.toJson());
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

    static void sendFile(HttpExchange ex, Path f) throws IOException {
        String name = f.getFileName().toString();
        send(ex, 200, MIME.getOrDefault(name.substring(name.lastIndexOf('.') + 1), "application/octet-stream"), Files.readString(f));
    }
}
