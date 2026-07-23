/// Feuille modale glissée depuis le bas — port fidèle des `.modal-overlay`
/// / `.modal-sheet` / `.modal-handle` (base.css / components.css).
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

class ModalSheet extends StatelessWidget {
  final Widget child;
  final VoidCallback onClose;
  const ModalSheet({super.key, required this.child, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: GestureDetector(
        onTap: onClose,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // absorbe le tap pour ne pas fermer via le contenu
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.86,
              ),
              decoration: const BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                border: Border(
                  top: BorderSide(color: AppColors.border),
                  left: BorderSide(color: AppColors.border),
                  right: BorderSide(color: AppColors.border),
                ),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
