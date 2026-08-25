package com.example.segnalazioni_app.car

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Una segnalazione ridotta ai soli campi mostrabili sullo schermo dell'auto.
 * Le foto restano fuori: Android Auto non le consente durante la guida.
 */
data class Segnalazione(
    val id: String,
    val tipo: String,
    val indirizzo: String,
    val stato: String,
    val priorita: String,
    val data: String,
    val dettagli: String,
    val latitudine: Double?,
    val longitudine: Double?,
)

/**
 * Client HTTP minimale per la parte auto.
 *
 * Il codice dell'auto gira in Kotlin nativo e non può chiamare
 * `lib/services/api_service.dart`, quindi le chiamate sono riscritte qui.
 * Il token di sessione viene però condiviso: `shared_preferences` salva su
 * Android nel file `FlutterSharedPreferences` con prefisso `flutter.`, così
 * l'auto riusa il login fatto sul telefono senza chiedere di nuovo le
 * credenziali (cosa comunque impossibile alla guida).
 */
object SegnalazioniApi {

    private const val BASE_URL = "https://www.castellazzodestampi.org"
    private const val PREFS_FILE = "FlutterSharedPreferences"
    private const val TOKEN_KEY = "flutter.auth_token"

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Token salvato dall'app Flutter, oppure null se l'utente non ha fatto login. */
    fun token(context: Context): String? =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getString(TOKEN_KEY, null)
            ?.takeIf { it.isNotEmpty() }

    /** Scarica le segnalazioni dell'utente. Il callback torna sul main thread. */
    fun elenco(context: Context, onResult: (Result<List<Segnalazione>>) -> Unit) {
        val token = token(context)
        executor.execute {
            val esito = runCatching {
                requireNotNull(token) { "Accedi dall'app sul telefono." }
                parseElenco(get("$BASE_URL/api/segnalazioni", token))
            }
            mainHandler.post { onResult(esito) }
        }
    }

    private fun get(url: String, token: String): JSONObject {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            setRequestProperty("X-AUTH-TOKEN", token)
            setRequestProperty("Content-Type", "application/json")
            connectTimeout = 15_000
            readTimeout = 15_000
        }
        try {
            val codice = conn.responseCode
            if (codice == 401 || codice == 403) {
                error("Sessione scaduta. Riaccedi dall'app sul telefono.")
            }
            if (codice !in 200..299) {
                error("Il server ha risposto $codice.")
            }
            return JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
        } finally {
            conn.disconnect()
        }
    }

    private fun parseElenco(body: JSONObject): List<Segnalazione> {
        if (!body.optBoolean("success", false)) {
            error(body.testo("message").ifEmpty { "Errore del server." })
        }
        val data: JSONArray = body.optJSONArray("data") ?: return emptyList()
        return (0 until data.length()).mapNotNull { i ->
            data.optJSONObject(i)?.toSegnalazione()
        }
    }

    private fun JSONObject.toSegnalazione() = Segnalazione(
        id = testo("id"),
        tipo = optJSONObject("type")?.testo("name")?.ifEmpty { null } ?: "Segnalazione",
        indirizzo = testo("address"),
        // status_label è già la dicitura in italiano usata dall'app.
        stato = testo("status_label").ifEmpty { testo("status") },
        // Ereditata dal tipo lato backend: qui si mostra e non si modifica.
        priorita = testo("priority_label"),
        data = testo("datetime"),
        dettagli = testo("details"),
        latitudine = testo("latitude").toDoubleOrNull(),
        longitudine = testo("longitude").toDoubleOrNull(),
    )

    /** optString restituisce "null" sui campi JSON null: qui li normalizziamo a "". */
    private fun JSONObject.testo(key: String): String =
        if (isNull(key)) "" else optString(key, "")
}
