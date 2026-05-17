import os, glob, re

base_dirs = ['d:/deisgn2/Smartsprout/smartsprout/lib/screens', 'd:/deisgn2/Smartsprout/smartsprout/lib/presentation/screens']
files = []
for d in base_dirs:
    files.extend(glob.glob(d + '/*.dart'))

new_blob = """  Widget _buildBlob(
      {double? top,
      double? left,
      double? right,
      double? bottom,
      required double size,
      required Color color}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.8),
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }"""

# regex to find the old _buildBlob function
blob_regex = re.compile(
    r"  Widget _buildBlob\s*\(\s*\{double\? top,\s*double\? left,\s*double\? right,\s*double\? bottom,\s*required double size,\s*required Color color\}\s*\)\s*\{"
    r".*?return Positioned\(.*?\);\s*\}", re.DOTALL)

for f in files:
    with open(f, 'r', encoding='utf-8') as file:
        content = file.read()
    
    orig_content = content
    
    # Check if this isn't dashboard_page
    if 'dashboard_page.dart' not in f:
        content = blob_regex.sub(new_blob, content)
        
    if orig_content != content:
        with open(f, 'w', encoding='utf-8') as file:
            file.write(content)
        print('Updated blobs in ' + f)
