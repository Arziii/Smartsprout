import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PlantSelectionGrid extends StatelessWidget {
  final Function(String) onPlantSelected;

  const PlantSelectionGrid({
    super.key,
    required this.onPlantSelected,
  });

  static const List<String> _plantImages = [
    'aloe_vera.jpg',
    'ampalaya.jpg',
    'basil.jpg',
    'bougainvillea.jpg',
    'calamansi.jpg',
    'gumamela.jpg',
    'kamatis.jpg',
    'kang_kong.jpg',
    'lemongrass.jpg',
    'mango.jpg',
    'mung_bean.jpg',
    'okra.jpg',
    'oregano.jpg',
    'papaya.jpg',
    'pechay.jpg',
    'sibuyas.jpg',
    'siling_labuyo.jpg',
    'snake_plant.jpg',
    'string_beans.jpg',
    'talong.jpg'
  ];

  Widget _buildTile({
    required BuildContext context,
    required String name,
    required Widget imageWidget,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2D30) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: imageWidget,
              ),
            ),
            Container(
              width: double.infinity,
              color: isDark ? const Color(0xFF162024) : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? Colors.white70
                      : const Color(0xFF4A6164),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1A1C) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F2027);
    final iconColor  = isDark ? Colors.white : const Color(0xFF0F2027);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          "Select Plant Type",
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: titleColor,
          ),
        ),
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: iconColor),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: iconColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _plantImages.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildTile(
                  context: context,
                  name: "DEFAULT / RESET",
                  imageWidget: Image.asset(
                    'assets/images/default_flower.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.local_florist,
                      size: 40,
                      color: isDark ? Colors.white38 : Colors.grey,
                    ),
                  ),
                  onTap: () {
                    onPlantSelected('');
                    Navigator.of(context).pop();
                  },
                );
              }
              final filename = _plantImages[index - 1];
              final name =
                  filename.split('.').first.replaceAll('_', ' ').toUpperCase();
              return _buildTile(
                context: context,
                name: name,
                imageWidget: Image.asset(
                  'assets/images/plants/$filename',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Icons.broken_image,
                          color: isDark ? Colors.white38 : Colors.grey),
                ),
                onTap: () {
                  onPlantSelected(filename);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
