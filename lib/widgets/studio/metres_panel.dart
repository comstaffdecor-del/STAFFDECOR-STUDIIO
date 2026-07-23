/// Panel métrés — port fidèle de `#panel-metres` (shell.ts).
///
/// Saisie des dimensions de la pièce, calibrage d'échelle, talon plinthe,
/// marge de coupe. Alimente `getQteNetteForFamille` (CORRECTION Bug #7).
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/chiffrage.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import 'common_modal.dart';

class MetresPanel extends StatefulWidget {
  final VoidCallback onClose;
  const MetresPanel({super.key, required this.onClose});

  @override
  State<MetresPanel> createState() => _MetresPanelState();
}

class _MetresPanelState extends State<MetresPanel> {
  late TextEditingController _murA, _murB, _hauteur, _portes, _fenetres;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _murA = TextEditingController(text: s.metresMurA == 0 ? '' : _fmt(s.metresMurA));
    _murB = TextEditingController(text: s.metresMurB == 0 ? '' : _fmt(s.metresMurB));
    _hauteur = TextEditingController(text: _fmt(s.metresHauteur));
    _portes = TextEditingController(text: s.metresPortes.toStringAsFixed(0));
    _fenetres = TextEditingController(text: s.metresFenetres.toStringAsFixed(0));
  }

  String _fmt(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _murA.dispose();
    _murB.dispose();
    _hauteur.dispose();
    _portes.dispose();
    _fenetres.dispose();
    super.dispose();
  }

  double _d(TextEditingController c, double fallback) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? fallback;

  void _apply() {
    final s = context.read<AppState>();
    s.applyMetres(
      murA: _d(_murA, 0),
      murB: _d(_murB, 0),
      hauteur: _d(_hauteur, 2.5),
      portes: _d(_portes, 0),
      fenetres: _d(_fenetres, 0),
    );
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final metres = s.metresPerimetre > 0
        ? MetresResult(
            perimetre: s.metresPerimetre,
            perimetreNet: s.metresPerimetreNet,
            surface: s.metresSurface,
          )
        : null;

    return ModalSheet(
      onClose: widget.onClose,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Métrés de la pièce',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(FontAwesomeIcons.xmark, size: 15, color: AppColors.text2),
                ),
              ],
            ),
            const Text(
              'Saisissez les dimensions pour un chiffrage précis',
              style: TextStyle(color: AppColors.text3, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            _sectionTitle('Dimensions de la pièce'),
            _numRow('Longueur mur A', _murA, 'm'),
            _numRow('Longueur mur B', _murB, 'm'),
            _numRow('Hauteur plafond', _hauteur, 'm'),
            _numRow('Nb de portes', _portes, ''),
            _numRow('Nb de fenêtres', _fenetres, ''),
            if (metres != null) ...[
              const SizedBox(height: 12),
              _sectionTitle('Métrés calculés'),
              _computedRow('Périmètre total', '${fmtN(metres.perimetre)} m'),
              _computedRow('Périmètre net', '${fmtN(metres.perimetreNet)} m'),
              _computedRow('Surface murs', '${fmtN(metres.surface)} m²'),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(FontAwesomeIcons.ruler, size: 12, color: AppColors.gold),
                      const SizedBox(width: 6),
                      const Text(
                        "Calibrage d'échelle",
                        style: TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (s.isCalibrated ? AppColors.green : AppColors.red)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          s.isCalibrated ? 'Calibré' : 'Non calibré',
                          style: TextStyle(
                            color: s.isCalibrated ? AppColors.green : AppColors.red,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Identifiez un élément de hauteur connue sur la photo pour améliorer la précision (±3% au lieu de ±15%).",
                    style: TextStyle(color: AppColors.text3, fontSize: 10.5, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(FontAwesomeIcons.scissors, size: 12, color: AppColors.text2),
                  const SizedBox(width: 8),
                  const Text('Marge de coupe', style: TextStyle(color: AppColors.text2, fontSize: 12.5)),
                  const Spacer(),
                  DropdownButton<double>(
                    value: s.margeCoupePct,
                    dropdownColor: AppColors.card2,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(color: AppColors.gold, fontSize: 12.5),
                    items: const [0.05, 0.10, 0.15, 0.20]
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text('${(v * 100).toStringAsFixed(0)}%'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) s.setMargeCoupePct(v);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.bg,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Appliquer les métrés',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text2,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Fermer', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          t,
          style: const TextStyle(color: AppColors.text2, fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      );

  Widget _numRow(String label, TextEditingController ctrl, String unit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 12.5)),
          ),
          SizedBox(
            width: 76,
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.text, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.card2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 16,
              child: Text(unit, style: const TextStyle(color: AppColors.text3, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _computedRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 12.5))),
          Text(value, style: const TextStyle(color: AppColors.gold, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
