package com.example.segnalazioni_app.car

import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Punto di ingresso di Android Auto: l'host (l'app Android Auto sul telefono
 * o l'head unit) si collega a questo service, non alla MainActivity Flutter.
 */
class SegnalazioniCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            // In debug accettiamo il Desktop Head Unit e gli emulatori.
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = SegnalazioniSession()
}
