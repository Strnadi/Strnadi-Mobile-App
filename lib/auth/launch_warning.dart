/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
import 'package:flutter/material.dart';
import 'package:strnadi/localization/translations.dart';

class WIP_warning extends StatelessWidget {
  const WIP_warning({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back),
                    SizedBox(width: 4),
                    Text(Translations.text('zpet')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Image.asset(
              'assets/images/WIP.png',
            ),
            const SizedBox(height: 16),
            const Text(
              Translations.text('nareci_ceskych_strnadu'),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              Translations.text('projekt_obcanske_vedy_zamereny_na_studium_rozmanitosti_ptaciho_zpevu_nahravanim_zpevu_strnadu_obecnych_po_celem_cesku_muzete_prispet_k_poznani_jak_se_v_krajine_udrzuji_ptaci_nareci'),
              style: TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              Translations.text('aplikace_i_web_stale_prochazeji_velmi_bourlivym_vyvojem_za_chyby_se_omlouvame_teste_se_na_caste_aktualizace_a_vylepsovani'),
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}