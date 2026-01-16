import os
import subprocess

def run(cmd):
    subprocess.check_call(cmd, shell=True)

def make_icns(source_img="source_icon.jpg"):
    iconset_dir = "MyIcon.iconset"
    if not os.path.exists(iconset_dir):
        os.makedirs(iconset_dir)
    
    # Dimensions for standard macOS icons
    sizes = [16, 32, 128, 256, 512]
    
    for size in sizes:
        # Normal
        run(f"sips -z {size} {size} --setProperty format png '{source_img}' --out '{iconset_dir}/icon_{size}x{size}.png'")
        # Retina (@2x)
        double_size = size * 2
        run(f"sips -z {double_size} {double_size} --setProperty format png '{source_img}' --out '{iconset_dir}/icon_{size}x{size}@2x.png'")

    print("Generating .icns file...")
    run(f"iconutil -c icns '{iconset_dir}'")
    print("Done: MyIcon.icns created.")

if __name__ == "__main__":
    make_icns()
