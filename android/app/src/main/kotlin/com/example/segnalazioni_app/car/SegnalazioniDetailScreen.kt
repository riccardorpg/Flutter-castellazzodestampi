package com.example.segnalazioni_app.car

import android.content.Intent
import android.net.Uri
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

/** Dettaglio di una segnalazione, con avvio della navigazione se georiferita. */
class SegnalazioniDetailScreen(
    carContext: CarContext,
    private val segnalazione: Segnalazione,
) : Screen(carContext) {

    override fun onGetTemplate(): Template {
        // Il PaneTemplate consente poche righe: stato e priorita' stanno
        // insieme invece di occuparne una ciascuna.
        val statoEPriorita = listOf(segnalazione.stato, priorita())
            .filter { it.isNotEmpty() }
            .joinToString(" · ")

        val righe = buildList {
            add("Stato" to statoEPriorita.ifEmpty { "—" })
            if (segnalazione.indirizzo.isNotEmpty()) add("Indirizzo" to segnalazione.indirizzo)
            if (segnalazione.data.isNotEmpty()) add("Data" to segnalazione.data)
            if (segnalazione.dettagli.isNotEmpty()) add("Dettagli" to segnalazione.dettagli)
        }

        val limite = carContext
            .getCarService(ConstraintManager::class.java)
            .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_PANE)

        val pane = Pane.Builder()
        righe.take(limite).forEach { (titolo, testo) ->
            pane.addRow(Row.Builder().setTitle(titolo).addText(testo).build())
        }

        val lat = segnalazione.latitudine
        val lon = segnalazione.longitudine
        if (lat != null && lon != null) {
            pane.addAction(
                Action.Builder()
                    .setTitle("Naviga")
                    .setOnClickListener { naviga(lat, lon) }
                    .build()
            )
        }

        return PaneTemplate.Builder(pane.build())
            .setTitle(segnalazione.tipo)
            .setHeaderAction(Action.BACK)
            .build()
    }

    private fun priorita(): String =
        if (segnalazione.priorita.isEmpty()) "" else "priorita' ${segnalazione.priorita.lowercase()}"

    /** Passa le coordinate all'app di navigazione predefinita dell'auto. */
    private fun naviga(lat: Double, lon: Double) {
        carContext.startCarApp(
            Intent(CarContext.ACTION_NAVIGATE, Uri.parse("geo:$lat,$lon"))
        )
    }
}
