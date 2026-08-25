package com.example.segnalazioni_app.car

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

/** Una sessione per ogni collegamento all'auto. Apre la schermata elenco. */
class SegnalazioniSession : Session() {

    override fun onCreateScreen(intent: Intent): Screen =
        SegnalazioniListScreen(carContext)
}
