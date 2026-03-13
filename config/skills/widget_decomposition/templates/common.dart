// Template : constantes et widgets réutilisables pour un projet Flutter.
// Copier ce fichier dans lib/widgets/common.dart et adapter selon les besoins.

import "package:flutter/material.dart";

const shrinkedBlox = SizedBox.shrink();

// ============================================================================
// Espacements horizontaux
// ============================================================================

const hSpace2 = SizedBox(width: 2);
const hSpace4 = SizedBox(width: 4);
const hSpace8 = SizedBox(width: 8);
const hSpace12 = SizedBox(width: 12);
const hSpace16 = SizedBox(width: 16);
const hSpace24 = SizedBox(width: 24);
const hSpace32 = SizedBox(width: 32);

// ============================================================================
// Espacements verticaux
// ============================================================================

const vSpace2 = SizedBox(height: 2);
const vSpace4 = SizedBox(height: 4);
const vSpace8 = SizedBox(height: 8);
const vSpace12 = SizedBox(height: 12);
const vSpace16 = SizedBox(height: 16);
const vSpace24 = SizedBox(height: 24);
const vSpace32 = SizedBox(height: 32);

// ============================================================================
// Paddings
// ============================================================================

const padAll8 = EdgeInsets.all(8);
const padAll12 = EdgeInsets.all(12);
const padSymmetricVertical8 = EdgeInsets.symmetric(vertical: 8);

// ============================================================================
// Widgets réutilisables
// ============================================================================

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: TextAlign.center,
    );
  }
}
