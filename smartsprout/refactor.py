import os, glob

base_dirs = ['d:/deisgn2/Smartsprout/smartsprout/lib/screens', 'd:/deisgn2/Smartsprout/smartsprout/lib/presentation/screens', 'd:/deisgn2/Smartsprout/smartsprout/lib/presentation/widgets']
files = []
for d in base_dirs:
    files.extend(glob.glob(d + '/*.dart'))

for f in files:
    with open(f, 'r', encoding='utf-8') as file:
        content = file.read()
    
    orig_content = content
    
    # Replace the old dark background gradient colors
    content = content.replace('Color(0xFF1E1E1E), const Color(0xFF121212)', 'Color(0xFF0F172A), const Color(0xFF064E3B)')
    content = content.replace('Color(0xFF1E1E1E), Color(0xFF121212)', 'Color(0xFF0F172A), Color(0xFF064E3B)')
    content = content.replace('const Color(0xFF1E1E1E), const Color(0xFF121212)', 'const Color(0xFF0F172A), const Color(0xFF064E3B)')
    content = content.replace('const [Color(0xFF1E1E1E), Color(0xFF121212)]', 'const [Color(0xFF0F172A), Color(0xFF064E3B)]')
    content = content.replace('[Color(0xFF1E1E1E), Color(0xFF121212)]', '[Color(0xFF0F172A), Color(0xFF064E3B)]')
    content = content.replace('0xFF1E1E1E', '0xFF0F172A')
    content = content.replace('0xFF121212', '0xFF064E3B')

    # Replace old light mode background gradient colors
    content = content.replace('Color(0xFFE0ECE9), Color(0xFFB4CDCA)', 'Color(0xFFF0FDF4), Color(0xFFCCFBF1)')
    content = content.replace('0xFFE0ECE9', '0xFFF0FDF4')
    content = content.replace('0xFFB4CDCA', '0xFFCCFBF1')
    
    # Now lets also upgrade _buildBlob logic
    # In dashboard its:
    # return Positioned(
    #   top: top,
    #   left: left,
    #   right: right,
    #   bottom: bottom,
    #   child: Container(
    #     width: size,
    #     height: size,
    #     decoration: BoxDecoration(
    #       shape: BoxShape.circle,
    #       gradient: RadialGradient(
    #         colors: [
    #           color.withValues(alpha: 0.8),
    #           color.withValues(alpha: 0.3),
    #           color.withValues(alpha: 0.0),
    #         ],
    #         stops: const [0.0, 0.5, 1.0],
    #       ),
    #     ),
    #   ),
    # );
    # We will let the user know we did static blobs for the rest, and manually replace BackdropFilter.
    
    if orig_content != content:
        with open(f, 'w', encoding='utf-8') as file:
            file.write(content)
        print('Updated ' + f)
