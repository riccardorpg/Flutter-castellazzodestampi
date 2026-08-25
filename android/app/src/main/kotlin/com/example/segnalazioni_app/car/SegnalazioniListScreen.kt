package com.example.segnalazioni_app.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

/** Elenco delle segnalazioni dell'utente, in sola lettura. */
class SegnalazioniListScreen(carContext: CarContext) : Screen(carContext) {

    private var segnalazioni: List<Segnalazione>? = null
    private var errore: String? = null

    init {
        carica()
    }

    private fun carica() {
        SegnalazioniApi.elenco(carContext) { esito ->
            esito
                .onSuccess { segnalazioni = it; errore = null }
                .onFailure { errore = it.message ?: MESSAGGIO_ERRORE }
            invalidate()
        }
    }

    private fun ricarica() {
        segnalazioni = null
        errore = null
        invalidate()
        carica()
    }

    override fun onGetTemplate(): Template {
        errore?.let { return messaggio(it, conRiprova = true) }

        val elenco = segnalazioni ?: return ListTemplate.Builder()
            .setLoading(true)
            .setTitle(TITOLO)
            .setHeaderAction(Action.APP_ICON)
            .build()

        if (elenco.isEmpty()) {
            return messaggio("Nessuna segnalazione da mostrare.", conRiprova = true)
        }

        // Il numero di righe consentite lo decide l'host: superarlo fa
        // crashare l'app in auto, quindi tronchiamo sempre al limite.
        val limite = carContext
            .getCarService(ConstraintManager::class.java)
            .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)

        val lista = ItemList.Builder()
        elenco.take(limite).forEach { segnalazione ->
            lista.addItem(
                Row.Builder()
                    .setTitle(segnalazione.tipo)
                    .addText(sottotitolo(segnalazione))
                    .setOnClickListener {
                        screenManager.push(SegnalazioniDetailScreen(carContext, segnalazione))
                    }
                    .build()
            )
        }

        return ListTemplate.Builder()
            .setSingleList(lista.build())
            .setTitle(TITOLO)
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(
                androidx.car.app.model.ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Aggiorna")
                            .setOnClickListener { ricarica() }
                            .build()
                    )
                    .build()
            )
            .build()
    }

    private fun sottotitolo(segnalazione: Segnalazione): String =
        listOf(segnalazione.indirizzo, segnalazione.stato)
            .filter { it.isNotEmpty() }
            .joinToString(" · ")
            .ifEmpty { "—" }

    private fun messaggio(testo: String, conRiprova: Boolean): Template {
        val builder = MessageTemplate.Builder(testo)
            .setTitle(TITOLO)
            .setHeaderAction(Action.APP_ICON)
        if (conRiprova) {
            builder.addAction(
                Action.Builder()
                    .setTitle("Riprova")
                    .setOnClickListener { ricarica() }
                    .build()
            )
        }
        return builder.build()
    }

    private companion object {
        const val TITOLO = "Segnalazioni"
        const val MESSAGGIO_ERRORE = "Errore di connessione."
    }
}
