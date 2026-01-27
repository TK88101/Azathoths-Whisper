
import re

icon_b64_path = '/Users/ibridgezhao/Documents/Bjork/icon_b64.txt'
target_file_path = '/Users/ibridgezhao/Documents/Bjork/lyrics_fetcher.py'

with open(icon_b64_path, 'r') as f:
    new_b64 = f.read().strip()

with open(target_file_path, 'r') as f:
    content = f.read()

# Pattern to find the img tag with the base64 source
# Looking for: <img src="data:image/png;base64,[...]" class="w-full h-full object-contain" />
# We want to replace the src and add the shadow style.

pattern = r'(<img src="data:image/png;base64,)([^"]+)(" class="w-full h-full object-contain")'

# Ensure we found it
match = re.search(pattern, content)
if not match:
    print("Could not find the image tag pattern!")
    exit(1)

# Construct new tag with style for white glow
# Added style="filter: drop-shadow(0 0 8px rgba(255, 255, 255, 0.8));"
new_tag = f'<img src="data:image/png;base64,{new_b64}" class="w-full h-full object-contain" style="filter: drop-shadow(0 0 10px rgba(255, 255, 255, 0.6));"'

# Replace
new_content = content.replace(match.group(0), new_tag + ' />') # Close tag manually as regex group 3 ends with "

with open(target_file_path, 'w') as f:
    f.write(new_content)

print("Successfully updated lyrics_fetcher.py with new icon and glow effect.")
