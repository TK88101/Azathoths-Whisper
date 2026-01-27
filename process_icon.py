
from PIL import Image, ImageOps
import base64
import os

src_path = "/Users/ibridgezhao/Documents/Bjork/source_icon.jpg"
out_path = "/Users/ibridgezhao/Documents/Bjork/icon_b64.txt"

def process():
    try:
        if not os.path.exists(src_path):
            print(f"Source not found: {src_path}")
            return

        img = Image.open(src_path).convert("RGBA")
        
        # Resize to 256x256
        # Use simple resize since it is square 1024x1024
        img = img.resize((256, 256), Image.Resampling.LANCZOS)
        
        # Remove black background
        # We will iterate and set alpha to 0 for black pixels
        datas = img.getdata()
        new_data = []
        
        # Threshold for "black"
        limit = 20 
        
        for item in datas:
            # item is (r,g,b,a)
            if item[0] < limit and item[1] < limit and item[2] < limit:
                # Transparent
                new_data.append((0, 0, 0, 0))
            else:
                new_data.append(item)
                
        img.putdata(new_data)
        
        # We generally don't need to mask to rounded rect if we have a custom shape
        # But if the user wants it to look "standard", maybe they want the shield to be the icon?
        # Let's assume transparency is the key request.
        
        print(f"Processed image size: {img.size}")

        # Save to buffer then base64
        import io
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        b64_str = base64.b64encode(buf.getvalue()).decode('utf-8')
        
        with open(out_path, "w") as f:
            f.write(b64_str)
            
        print("BASE64 calculated and saved to icon_b64.txt")

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    process()
