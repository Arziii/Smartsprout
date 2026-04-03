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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
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
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF4A6164),
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Select Plant Type",
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF0F2027),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF0F2027)),
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
                    errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.local_florist,
                        size: 40,
                        color: Colors.grey),
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
                      const Icon(Icons.broken_image, color: Colors.grey),
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
